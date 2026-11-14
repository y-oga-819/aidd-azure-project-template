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
@description('Container Apps 環境のサブネット。ワークロードプロファイル環境は /27 以上が必要。')
param containerAppsSubnetPrefix string = '10.10.0.0/23'
param privateEndpointSubnetPrefix string = '10.10.2.0/27'

// --- 監視 ---
@minValue(30)
@maxValue(730)
param logRetentionInDays int = 30

// --- アプリ ---
@description('フロントエンド（Angular を配信する nginx）のイメージ。初回は ACR が空なのでサンプルイメージを使う。')
param frontendImage string = 'mcr.microsoft.com/k8se/quickstart:latest'
@description('バックエンド（Python API）のイメージ。')
param backendImage string = 'mcr.microsoft.com/k8se/quickstart:latest'
param frontendTargetPort int = 80
param backendTargetPort int = 80

@description('バックエンドに渡す Key Vault のシークレット。{ secretName, envName } の配列。')
param backendKeyVaultSecrets array = []

param minReplicas int = 0
param maxReplicas int = 3

// --- 入口 ---
@description('Front Door (WAF) を作成するか。false にするとインターネットからは到達できない（VNet 内からのみ）。')
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
    nsgContainerAppsName: names.nsgContainerApps
    nsgPrivateEndpointsName: names.nsgPrivateEndpoints
    location: location
    tags: commonTags
    addressPrefix: vnetAddressPrefix
    containerAppsSubnetPrefix: containerAppsSubnetPrefix
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

module containerApps 'modules/container-apps.bicep' = {
  // keyVault / registry の出力を参照しているので、ロール割り当てと Private Endpoint の作成後にデプロイされる。
  name: 'container-apps'
  params: {
    environmentName: names.containerAppsEnvironment
    frontendAppName: names.frontendApp
    backendAppName: names.backendApp
    location: location
    tags: commonTags
    infrastructureSubnetId: network.outputs.containerAppsSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    frontendIdentityId: frontendIdentity.id
    backendIdentityId: backendIdentity.id
    backendIdentityClientId: backendIdentity.properties.clientId
    frontendImage: frontendImage
    backendImage: backendImage
    frontendTargetPort: frontendTargetPort
    backendTargetPort: backendTargetPort
    registryLoginServer: registry.outputs.loginServer
    keyVaultUri: keyVault.outputs.uri
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    backendKeyVaultSecrets: backendKeyVaultSecrets
    minReplicas: minReplicas
    maxReplicas: maxReplicas
  }
}

module frontDoor 'modules/front-door.bicep' = if (enableFrontDoor) {
  name: 'front-door'
  params: {
    profileName: names.frontDoorProfile
    endpointName: names.frontDoorEndpoint
    wafPolicyName: names.wafPolicy
    tags: commonTags
    originHostName: containerApps.outputs.frontendFqdn
    privateLinkResourceId: containerApps.outputs.environmentId
    privateLinkLocation: location
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

output frontDoorEndpoint string = enableFrontDoor ? 'https://${frontDoor!.outputs.endpointHostName}' : ''
output containerAppsEnvironmentName string = names.containerAppsEnvironment
output containerRegistryLoginServer string = registry.outputs.loginServer
output keyVaultName string = keyVault.outputs.name
output frontendAppName string = names.frontendApp
output backendAppName string = names.backendApp
