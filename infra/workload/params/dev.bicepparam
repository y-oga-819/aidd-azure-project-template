using '../main.bicep'

param workloadName = 'aidd'
param environmentName = 'dev'
param location = 'japaneast'
param logRetentionInDays = 30
param minReplicas = 0
param maxReplicas = 2
