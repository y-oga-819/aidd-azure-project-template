using '../main.bicep'

param workloadName = 'aidd'
param environmentName = 'dev'
param location = 'japaneast'
param logRetentionInDays = 30
param appServicePlanSku = 'P0v3'
param appServicePlanCapacity = 1
// アプリのイメージは CD から環境変数で渡す（未指定ならサンプルイメージ）。
// インフラの再デプロイで稼働中のイメージが巻き戻らないよう、CD は同じ変数を渡して //infra:deploy を呼ぶ。
param appImage = readEnvironmentVariable('APP_IMAGE', 'mcr.microsoft.com/appsvc/staticsite:latest')
