// App Service（プラン 1 つに web と api を相乗り）。
//
// 構成:
//   インターネット → Front Door (WAF) ─ Private Link ─┬→ [web] Angular の静的ファイルを配信（Node）
//                                                      └→ [api] Python（/api/* を Front Door が振り分け）
//   - 両アプリとも publicNetworkAccess を無効にし、Front Door の Private Link からのみ届く。
//   - 送信は VNet 統合で VNet 経由にし、Key Vault へは Private Endpoint でつなぐ。
//   - 各アプリは専用のユーザー割り当てマネージド ID を持ち、シークレットは Key Vault 参照で受け取る。
//   - FTP / SCM の基本認証（発行プロファイルのユーザー名・パスワード）は無効にする。

param planName string
param frontendAppName string
param backendAppName string
param location string
param tags object

@description('App Service プランの SKU。Private Link（Front Door からの接続）に対応した SKU にする。')
param planSkuName string

@minValue(1)
param planCapacity int

param appIntegrationSubnetId string
param logAnalyticsWorkspaceId string

param frontendIdentityId string
param frontendIdentityClientId string
param backendIdentityId string
param backendIdentityClientId string

param frontendRuntime string
param backendRuntime string

param keyVaultUri string
param appInsightsConnectionString string

@description('api に渡す Key Vault のシークレット。{ secretName: Key Vault 上の名前, envName: 環境変数名 } の配列。')
param backendKeyVaultSecrets array = []

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: planSkuName
    capacity: planCapacity
  }
  properties: {
    reserved: true
  }
}

// 両アプリで共通の、セキュリティに関わる設定。
var commonSiteConfig = {
  alwaysOn: true
  ftpsState: 'Disabled'
  minTlsVersion: '1.2'
  scmMinTlsVersion: '1.2'
  http20Enabled: true
  remoteDebuggingEnabled: false
  // 送信はすべて VNet 経由にする（Key Vault の Private Endpoint に届くように）。
  vnetRouteAllEnabled: true
}

resource frontend 'Microsoft.Web/sites@2024-04-01' = {
  name: frontendAppName
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${frontendIdentityId}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    virtualNetworkSubnetId: appIntegrationSubnetId
    siteConfig: union(commonSiteConfig, {
      linuxFxVersion: frontendRuntime
      // Angular のビルド成果物を SPA として配信する（未知のパスは index.html を返す）。
      appCommandLine: 'pm2 serve /home/site/wwwroot --no-daemon --spa'
      appSettings: [
        {
          name: 'AZURE_CLIENT_ID'
          value: frontendIdentityClientId
        }
      ]
    })
  }
}

resource backend 'Microsoft.Web/sites@2024-04-01' = {
  name: backendAppName
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${backendIdentityId}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    virtualNetworkSubnetId: appIntegrationSubnetId
    // Key Vault 参照（@Microsoft.KeyVault(...)）の解決に使う ID。
    keyVaultReferenceIdentity: backendIdentityId
    siteConfig: union(commonSiteConfig, {
      linuxFxVersion: backendRuntime
      appSettings: concat(
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
          {
            name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
            value: 'true'
          }
        ],
        map(backendKeyVaultSecrets, s => {
          name: s.envName
          value: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/${s.secretName})'
        })
      )
    })
  }
}

// FTP と SCM（Kudu）の基本認証を無効にする。デプロイは Entra ID 認証で行う。
resource frontendFtpAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: frontend
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource frontendScmAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: frontend
  name: 'scm'
  properties: {
    allow: false
  }
}

resource backendFtpAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: backend
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource backendScmAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: backend
  name: 'scm'
  properties: {
    allow: false
  }
}

resource frontendDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: frontend
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

resource backendDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: backend
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

output frontendId string = frontend.id
output backendId string = backend.id
output frontendHostName string = frontend.properties.defaultHostName
output backendHostName string = backend.properties.defaultHostName
