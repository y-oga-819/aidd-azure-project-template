// Container Apps 環境とアプリ（フロントエンド / バックエンド）。
//
// 構成:
//   インターネット → Front Door (WAF) → Private Link → [web] Angular を配信する nginx
//                                                         └─ /api を内部で [api] Python へリバースプロキシ
//   - 環境は VNet 注入 + 内部モード + パブリックアクセス無効。
//   - web だけが環境外（Front Door の Private Link）から到達可能（ingress.external = true）。
//   - api は環境内からのみ到達可能（ingress.external = false）。ブラウザから直接は届かない。
//   - 各アプリは専用のユーザー割り当てマネージド ID を持ち、シークレットは Key Vault 参照で受け取る。
//     コンテナイメージやアプリ設定にシークレット値を置かない。

param environmentName string
param frontendAppName string
param backendAppName string
param location string
param tags object

param infrastructureSubnetId string
param logAnalyticsWorkspaceId string

param frontendIdentityId string
param backendIdentityId string
param backendIdentityClientId string

param frontendImage string
param backendImage string
param frontendTargetPort int
param backendTargetPort int

@description('ACR のログインサーバー。イメージがこのレジストリのものなら、マネージド ID でプルする。')
param registryLoginServer string

param keyVaultUri string
param appInsightsConnectionString string

@description('バックエンドに渡す Key Vault のシークレット。{ secretName: Key Vault 上の名前, envName: 環境変数名 } の配列。')
param backendKeyVaultSecrets array = []

param minReplicas int = 0
param maxReplicas int = 3

resource managedEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    vnetConfiguration: {
      infrastructureSubnetId: infrastructureSubnetId
      internal: true
    }
    // Front Door からは Private Link で接続するので、環境のパブリックエンドポイントは不要。
    publicNetworkAccess: 'Disabled'
    // ログは診断設定経由で Log Analytics に送る（共有キーを使わない）。
    appLogsConfiguration: {
      destination: 'azure-monitor'
    }
    zoneRedundant: false
  }
}

resource environmentDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: managedEnvironment
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

var frontendUsesRegistry = startsWith(frontendImage, '${registryLoginServer}/')
var backendUsesRegistry = startsWith(backendImage, '${registryLoginServer}/')

resource backend 'Microsoft.App/containerApps@2025-07-01' = {
  name: backendAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${backendIdentityId}': {}
    }
  }
  properties: {
    environmentId: managedEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: backendTargetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: backendUsesRegistry
        ? [
            {
              server: registryLoginServer
              identity: backendIdentityId
            }
          ]
        : []
      secrets: [
        for s in backendKeyVaultSecrets: {
          name: toLower(replace(s.secretName, '_', '-'))
          keyVaultUrl: '${keyVaultUri}secrets/${s.secretName}'
          identity: backendIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: backendImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: concat(
            [
              {
                // DefaultAzureCredential がユーザー割り当て ID を選ぶために必要。
                name: 'AZURE_CLIENT_ID'
                value: backendIdentityClientId
              }
              {
                name: 'KEY_VAULT_URI'
                value: keyVaultUri
              }
              {
                // ローカル認証が無効なので、送信には Entra ID 認証（マネージド ID）が必要。
                name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
                value: appInsightsConnectionString
              }
              {
                name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING'
                value: 'Authorization=AAD;ClientId=${backendIdentityClientId}'
              }
            ],
            map(backendKeyVaultSecrets, s => {
              name: s.envName
              secretRef: toLower(replace(s.secretName, '_', '-'))
            })
          )
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

resource frontend 'Microsoft.App/containerApps@2025-07-01' = {
  name: frontendAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${frontendIdentityId}': {}
    }
  }
  properties: {
    environmentId: managedEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        // 「環境の外」から到達可能にする。環境自体は内部モード + パブリック無効なので、
        // 実際に届くのは VNet 内と Front Door の Private Link だけ。
        external: true
        targetPort: frontendTargetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: frontendUsesRegistry
        ? [
            {
              server: registryLoginServer
              identity: frontendIdentityId
            }
          ]
        : []
    }
    template: {
      containers: [
        {
          name: 'web'
          image: frontendImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              // nginx が /api をプロキシする先。環境内の内部 FQDN。
              name: 'BACKEND_BASE_URL'
              value: 'https://${backend.properties.configuration.ingress.fqdn}'
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output environmentId string = managedEnvironment.id
output environmentDefaultDomain string = managedEnvironment.properties.defaultDomain
output frontendFqdn string = frontend.properties.configuration.ingress.fqdn
output backendFqdn string = backend.properties.configuration.ingress.fqdn
