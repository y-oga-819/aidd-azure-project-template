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
