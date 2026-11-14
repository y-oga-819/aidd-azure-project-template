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
@description('web（Angular を nginx で配信）のコンテナイメージ。初回は ACR が空なのでサンプルイメージを使う。')
param frontendImage string = 'mcr.microsoft.com/appsvc/staticsite:latest'
@description('api（Python）のコンテナイメージ。')
param backendImage string = 'mcr.microsoft.com/appsvc/staticsite:latest'
param frontendPort int = 80
param backendPort int = 80

@description('api に渡す Key Vault のシークレット。{ secretName, envName } の配列。')
param backendKeyVaultSecrets array = []

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
      backendIdentity.properties.principalId
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

// アプリごとに専用の ID を持たせ、必要な権限だけを付ける（web は AcrPull のみ）。
resource frontendIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.frontendIdentity
  location: location
  tags: commonTags
}

resource backendIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.backendIdentity
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
      backendIdentity.properties.principalId
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
      frontendIdentity.properties.principalId
      backendIdentity.properties.principalId
    ]
  }
}

module appService 'modules/app-service.bicep' = {
  // keyVault / registry の出力を参照しているので、ロール割り当てと Private Endpoint の作成後にデプロイされる。
  name: 'app-service'
  params: {
    planName: names.appServicePlan
    frontendAppName: names.frontendApp
    backendAppName: names.backendApp
    location: location
    tags: commonTags
    planSkuName: appServicePlanSku
    planCapacity: appServicePlanCapacity
    appIntegrationSubnetId: network.outputs.appIntegrationSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    frontendIdentityId: frontendIdentity.id
    frontendIdentityClientId: frontendIdentity.properties.clientId
    backendIdentityId: backendIdentity.id
    backendIdentityClientId: backendIdentity.properties.clientId
    frontendImage: frontendImage
    backendImage: backendImage
    frontendPort: frontendPort
    backendPort: backendPort
    registryLoginServer: registry.outputs.loginServer
    keyVaultUri: keyVault.outputs.uri
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    backendKeyVaultSecrets: backendKeyVaultSecrets
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
        name: 'api'
        hostName: appService.outputs.backendHostName
        resourceId: appService.outputs.backendId
        patterns: [
          '/api/*'
        ]
      }
      {
        name: 'web'
        hostName: appService.outputs.frontendHostName
        resourceId: appService.outputs.frontendId
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
output frontendAppName string = names.frontendApp
output backendAppName string = names.backendApp
