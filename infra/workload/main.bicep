// =============================================================================
// workload: CI（GitHub Actions / 将来は Azure DevOps）がデプロイするアプリ基盤。
// 前提として bootstrap でリソースグループ・デプロイ用 ID・Policy が作成済みであること。
//
// 構成の全体像と各ガードレールの理由は infra/docs/guardrails.md を参照。
// =============================================================================
targetScope = 'resourceGroup'

import { resourceNames, uniqueSuffix } from '../shared/naming.bicep'

@minLength(3)
@maxLength(10)
param workloadName string

@allowed([
  'dev'
  'stg'
  'prd'
])
param environmentName string

param location string = resourceGroup().location

param tags object = {}

// --- ネットワーク ---
param vnetAddressPrefix string = '10.10.0.0/16'
@description('App Service の VNet 統合用サブネット。スケールアウトに備えて /26 以上を推奨。')
param appIntegrationSubnetPrefix string = '10.10.0.0/26'
param privateEndpointSubnetPrefix string = '10.10.1.0/27'

// --- 監視 ---
@minValue(30)
@maxValue(730)
param logRetentionInDays int = 30

// --- アプリ ---
@description('App Service プランの SKU。Front Door からの Private Link に対応した SKU にする（Basic 以上）。')
param appServicePlanSku string = 'P0v3'
@minValue(1)
param appServicePlanCapacity int = 1
@description('アプリ（Angular の静的ファイルと Python の API を 1 つにまとめたもの）のコンテナイメージ。初回は ACR が空なのでサンプルイメージを使う。')
param appImage string = 'mcr.microsoft.com/appsvc/staticsite:latest'
@description('コンテナが待ち受けるポート。')
param appPort int = 80

@description('アプリに渡す Key Vault のシークレット。{ secretName, envName } の配列。')
param appKeyVaultSecrets array = []

// --- 入口 ---
@description('Front Door (WAF) を作成するか。false にするとインターネットからは到達できない。')
param enableFrontDoor bool = true

var names = resourceNames(workloadName, environmentName, uniqueSuffix(subscription().id, workloadName, environmentName))
var commonTags = union(tags, {
  workload: workloadName
  environment: environmentName
  managedBy: 'bicep'
})

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    logAnalyticsName: names.logAnalytics
    appInsightsName: names.appInsights
    location: location
    tags: commonTags
    retentionInDays: logRetentionInDays
    telemetryPublisherPrincipalIds: [
      appIdentity.properties.principalId
    ]
  }
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    vnetName: names.vnet
    nsgAppIntegrationName: names.nsgAppIntegration
    nsgPrivateEndpointsName: names.nsgPrivateEndpoints
    location: location
    tags: commonTags
    addressPrefix: vnetAddressPrefix
    appIntegrationSubnetPrefix: appIntegrationSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
  }
}

// アプリのマネージド ID。必要な権限（AcrPull / Key Vault Secrets User / Monitoring Metrics Publisher）だけを付ける。
resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.appIdentity
  location: location
  tags: commonTags
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    name: names.keyVault
    location: location
    tags: commonTags
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneId: network.outputs.keyVaultDnsZoneId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    secretReaderPrincipalIds: [
      appIdentity.properties.principalId
    ]
  }
}

module registry 'modules/registry.bicep' = {
  name: 'registry'
  params: {
    name: names.containerRegistry
    location: location
    tags: commonTags
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneId: network.outputs.containerRegistryDnsZoneId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    pullerPrincipalIds: [
      appIdentity.properties.principalId
    ]
  }
}

module appService 'modules/app-service.bicep' = {
  // keyVault / registry の出力を参照しているので、ロール割り当てと Private Endpoint の作成後にデプロイされる。
  name: 'app-service'
  params: {
    planName: names.appServicePlan
    appName: names.app
    location: location
    tags: commonTags
    planSkuName: appServicePlanSku
    planCapacity: appServicePlanCapacity
    appIntegrationSubnetId: network.outputs.appIntegrationSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    identityId: appIdentity.id
    identityClientId: appIdentity.properties.clientId
    image: appImage
    port: appPort
    registryLoginServer: registry.outputs.loginServer
    keyVaultUri: keyVault.outputs.uri
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    keyVaultSecrets: appKeyVaultSecrets
  }
}

module frontDoor 'modules/front-door.bicep' = if (enableFrontDoor) {
  name: 'front-door'
  params: {
    profileName: names.frontDoorProfile
    endpointName: names.frontDoorEndpoint
    wafPolicyName: names.wafPolicy
    tags: commonTags
    // 外部から届く経路はここに列挙したものだけ。経路を増やすときはこの配列を変更する（= レビュー対象）。
    origins: [
      {
        name: 'app'
        hostName: appService.outputs.hostName
        resourceId: appService.outputs.id
        patterns: [
          '/*'
        ]
      }
    ]
    privateLinkLocation: location
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

output frontDoorEndpoint string = enableFrontDoor ? 'https://${frontDoor!.outputs.endpointHostName}' : ''
output containerRegistryLoginServer string = registry.outputs.loginServer
output keyVaultName string = keyVault.outputs.name
output appName string = names.app
