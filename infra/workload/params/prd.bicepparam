using '../main.bicep'

param workloadName = 'aidd'
param environmentName = 'prd'
param location = 'japaneast'
param vnetAddressPrefix = '10.20.0.0/16'
param appIntegrationSubnetPrefix = '10.20.0.0/26'
param privateEndpointSubnetPrefix = '10.20.1.0/27'
param logRetentionInDays = 90
param appServicePlanSku = 'P1v3'
// 可用性のため 2 インスタンス以上にする。
param appServicePlanCapacity = 2
// アプリのイメージは CD から環境変数で渡す（未指定ならサンプルイメージ）。
// インフラの再デプロイで稼働中のイメージが巻き戻らないよう、CD は同じ変数を渡して //infra:deploy を呼ぶ。
param frontendImage = readEnvironmentVariable('FRONTEND_IMAGE', 'mcr.microsoft.com/appsvc/staticsite:latest')
param backendImage = readEnvironmentVariable('BACKEND_IMAGE', 'mcr.microsoft.com/appsvc/staticsite:latest')
