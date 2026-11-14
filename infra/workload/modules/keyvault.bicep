// Key Vault。
//   - アクセス制御は RBAC のみ（アクセスポリシーは使わない）。
//   - パブリックアクセス無効、Private Endpoint 経由のみ。
//   - 論理削除 + 消去保護を有効化。
//   - 監査ログを Log Analytics に送る。
//   - シークレットの読み取り権限は、必要なアプリのマネージド ID にだけ付与する。

param name string
param location string
param tags object

param privateEndpointSubnetId string
param privateDnsZoneId string
param logAnalyticsWorkspaceId string

@description('シークレットの読み取り（Key Vault Secrets User）を許可するプリンシパル ID。')
param secretReaderPrincipalIds array = []

@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 90

var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6' // gitleaks:allow 組み込みロール定義の ID（秘密情報ではない）

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'None'
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
    targetResourceId: vault.id
    groupId: 'vault'
    privateDnsZoneId: privateDnsZoneId
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: vault
  name: 'to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        // allLogs は監査ログ（AuditEvent）を含む。
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

resource secretReaders 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in secretReaderPrincipalIds: {
    scope: vault
    name: guid(vault.id, principalId, keyVaultSecretsUserRoleId)
    properties: {
      principalId: principalId
      principalType: 'ServicePrincipal'
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    }
  }
]

output id string = vault.id
output name string = vault.name
output uri string = vault.properties.vaultUri
