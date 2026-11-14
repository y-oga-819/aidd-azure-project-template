// ログと監視の集約先。
//   - Log Analytics: 全リソースの診断ログとコンテナのログを集める。
//   - Application Insights: アプリのテレメトリ。ローカル認証（インストルメンテーションキー）を無効にし、
//     マネージド ID + Entra ID 認証でのみ送信を受け付ける。

param logAnalyticsName string
param appInsightsName string
param location string
param tags object

@minValue(30)
@maxValue(730)
param retentionInDays int

@description('テレメトリ送信（Monitoring Metrics Publisher）を許可するプリンシパル ID。')
param telemetryPublisherPrincipalIds array = []

var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      // 共有キーでの書き込みを禁止し、Entra ID 認証のみにする。
      disableLocalAuth: true
    }
    // 取り込み・クエリのプライベート化（AMPLS）は未対応。docs/guardrails.md の「今後」を参照。
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    DisableLocalAuth: true
    IngestionMode: 'LogAnalytics'
  }
}

resource telemetryPublishers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in telemetryPublisherPrincipalIds: {
    scope: appInsights
    name: guid(appInsights.id, principalId, monitoringMetricsPublisherRoleId)
    properties: {
      principalId: principalId
      principalType: 'ServicePrincipal'
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    }
  }
]

output workspaceId string = workspace.id
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
