using '../main.bicep'

param workloadName = 'aidd'
param environmentName = 'dev'
param location = 'japaneast'
param githubOwner = 'y-oga-819'
param githubRepository = 'aidd-azure-project-template'
// 初回は DoNotEnforce で準拠状況だけ確認し、問題がなければ Default に切り替える。
param policyEnforcementMode = 'DoNotEnforce'
