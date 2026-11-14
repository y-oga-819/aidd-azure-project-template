// App Service（Linux コンテナ 1 つ）。
//
// 構成:
//   インターネット → Front Door (WAF) ─ Private Link → [app] 1 つのコンテナで
//                                                       Angular の静的ファイルと Python の API（/api）を返す
//   - publicNetworkAccess を無効にし、Front Door の Private Link からのみ届く。
//   - コンテナイメージは閉域の ACR から、VNet 統合 + マネージド ID（AcrPull）で取得する。
//     アプリのデプロイは「どのイメージを使うか」の設定変更（Azure の管理 API）だけで済み、閉域の SCM サイトに届く必要がない。
//   - 送信は VNet 統合で VNet 経由にし、Key Vault へは Private Endpoint でつなぐ。
//   - シークレットは Key Vault 参照で受け取る。FTP / SCM の基本認証は無効にする。
//   - コンテナの中身（静的ファイルを Python が返すか、nginx と同居させるか）はアプリ側で決める。
//     インフラが前提にするのは「1 イメージ・1 ポート・API は /api 配下」だけ。

param planName string
param appName string
param location string
param tags object

@description('App Service プランの SKU。Private Link（Front Door からの接続）に対応した SKU にする。')
param planSkuName string

@minValue(1)
param planCapacity int

param appIntegrationSubnetId string
param logAnalyticsWorkspaceId string

param identityId string
param identityClientId string

@description('アプリのコンテナイメージ（例: <ACR>.azurecr.io/app:<tag>）。')
param image string
@description('コンテナが待ち受けるポート。')
param port int

@description('ACR のログインサーバー。イメージがこのレジストリのものなら、マネージド ID でプルする。')
param registryLoginServer string

param keyVaultUri string
param appInsightsConnectionString string

@description('アプリに渡す Key Vault のシークレット。{ secretName: Key Vault 上の名前, envName: 環境変数名 } の配列。')
param keyVaultSecrets array = []

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

var usesRegistry = startsWith(image, '${registryLoginServer}/')

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: appName
  location: location
  tags: tags
  kind: 'app,linux,container'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    virtualNetworkSubnetId: appIntegrationSubnetId
    // イメージのプルも VNet 経由にする（閉域の ACR に届くように）。
    vnetImagePullEnabled: true
    // Key Vault 参照（@Microsoft.KeyVault(...)）の解決に使う ID。
    keyVaultReferenceIdentity: identityId
    siteConfig: {
      linuxFxVersion: 'DOCKER|${image}'
      acrUseManagedIdentityCreds: usesRegistry
      acrUserManagedIdentityID: usesRegistry ? identityClientId : null
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      remoteDebuggingEnabled: false
      // 送信はすべて VNet 経由にする（Key Vault / ACR の Private Endpoint に届くように）。
      vnetRouteAllEnabled: true
      appSettings: concat(
        [
          {
            // DefaultAzureCredential がユーザー割り当て ID を選ぶために必要。
            name: 'AZURE_CLIENT_ID'
            value: identityClientId
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
            value: 'Authorization=AAD;ClientId=${identityClientId}'
          }
          {
            name: 'WEBSITES_PORT'
            value: string(port)
          }
          {
            // コンテナにストレージをマウントしない（状態を持たせない）。
            name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
            value: 'false'
          }
        ],
        map(keyVaultSecrets, s => {
          name: s.envName
          value: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/${s.secretName})'
        })
      )
    }
  }
}

// FTP と SCM（Kudu）の基本認証を無効にする。デプロイはイメージ指定の変更（管理 API）で行う。
resource ftpAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: app
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource scmAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: app
  name: 'scm'
  properties: {
    allow: false
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: app
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

output id string = app.id
output hostName string = app.properties.defaultHostName
