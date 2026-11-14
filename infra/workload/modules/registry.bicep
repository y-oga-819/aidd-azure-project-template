// Azure Container Registry。
//   - Private Endpoint を使うため Premium SKU。
//   - 管理者ユーザー・匿名プル・エクスポートを無効化。プルはマネージド ID（AcrPull）のみ。
//   - パブリックアクセス無効。
//
// App Service は VNet 統合 + マネージド ID（AcrPull）でここからイメージを取得する。
//
// 注意: パブリックアクセスを無効にすると、GitHub ホストランナーからイメージを push できない。
// VNet 内のセルフホストランナーなどが必要。docs/azure-infra-guardrails.md の「既知の制約」を参照。

param name string
param location string
param tags object

param privateEndpointSubnetId string
param privateDnsZoneId string
param logAnalyticsWorkspaceId string

@description('イメージのプル（AcrPull）を許可するプリンシパル ID。')
param pullerPrincipalIds array = []

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource registry 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    publicNetworkAccess: 'Disabled'
    networkRuleBypassOptions: 'None'
    dataEndpointEnabled: false
    policies: {
      exportPolicy: {
        status: 'disabled'
      }
    }
  }
}

module privateEndpoint 'private-endpoint.bicep' = {
  name: '${name}-pe'
  params: {
    name: 'pe-${name}'
    location: location
    tags: tags
    subnetId: privateEndpointSubnetId
    targetResourceId: registry.id
    groupId: 'registry'
    privateDnsZoneId: privateDnsZoneId
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: registry
  name: 'to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource pullers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in pullerPrincipalIds: {
    scope: registry
    name: guid(registry.id, principalId, acrPullRoleId)
    properties: {
      principalId: principalId
      principalType: 'ServicePrincipal'
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    }
  }
]

output id string = registry.id
output name string = registry.name
output loginServer string = registry.properties.loginServer
