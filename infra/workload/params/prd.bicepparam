using '../main.bicep'

param workloadName = 'aidd'
param environmentName = 'prd'
param location = 'japaneast'
param vnetAddressPrefix = '10.20.0.0/16'
param containerAppsSubnetPrefix = '10.20.0.0/23'
param privateEndpointSubnetPrefix = '10.20.2.0/27'
param logRetentionInDays = 90
param minReplicas = 1
param maxReplicas = 5
