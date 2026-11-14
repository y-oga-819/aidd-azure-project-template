// 命名規約。
// bootstrap（特権者が実行）と workload（CI が実行）の両方から import し、
// 同じ入力から同じリソース名を導出する。ポリシーの除外スコープ（notScopes）や
// ロール割り当て先を、リソース作成前に名前で特定するために共有している。

@export()
@description('グローバル一意性が必要な名前に付ける短いサフィックス。subscription().id を渡すこと。')
func uniqueSuffix(subscriptionId string, workloadName string, environmentName string) string =>
  take(uniqueString(subscriptionId, workloadName, environmentName), 6)

@export()
@description('ワークロードの全リソース名。')
func resourceNames(workloadName string, environmentName string, suffix string) object => {
  workloadResourceGroup: 'rg-${workloadName}-${environmentName}'
  opsResourceGroup: 'rg-${workloadName}-${environmentName}-ops'
  deployerIdentity: 'id-${workloadName}-${environmentName}-deployer'

  vnet: 'vnet-${workloadName}-${environmentName}'
  nsgAppIntegration: 'nsg-${workloadName}-${environmentName}-app'
  nsgPrivateEndpoints: 'nsg-${workloadName}-${environmentName}-pe'

  logAnalytics: 'log-${workloadName}-${environmentName}'
  appInsights: 'appi-${workloadName}-${environmentName}'

  frontendIdentity: 'id-${workloadName}-${environmentName}-web'
  backendIdentity: 'id-${workloadName}-${environmentName}-api'

  keyVault: take('kv-${workloadName}-${environmentName}-${suffix}', 24)

  appServicePlan: 'asp-${workloadName}-${environmentName}'
  // App Service の既定ホスト名（*.azurewebsites.net）はグローバル一意なのでサフィックスを付ける。
  frontendApp: 'app-${workloadName}-${environmentName}-web-${suffix}'
  backendApp: 'app-${workloadName}-${environmentName}-api-${suffix}'

  frontDoorProfile: 'afd-${workloadName}-${environmentName}'
  frontDoorEndpoint: 'fde-${workloadName}-${environmentName}-${suffix}'
  wafPolicy: replace('waf${workloadName}${environmentName}', '-', '')
}
