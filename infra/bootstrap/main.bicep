// =============================================================================
// bootstrap: 特権を持つ人間が、環境ごとに一度だけ（または変更時に）実行する。
//
// ここで作るもの:
//   - ワークロード用リソースグループ（CI がデプロイする先）
//   - ops リソースグループ（CI のデプロイ用 ID を置く。CI 自身は権限を持たない）
//   - CI デプロイ用のマネージド ID と GitHub OIDC のフェデレーション資格情報
//   - デプロイ用 ID への最小権限ロール（Contributor + 付与可能ロールを絞った RBAC 管理者）
//   - ワークロード RG に対する Azure Policy（ガードレール）
//
// なぜ分けるか:
//   ガードレール（Policy・権限）を CI の手の届かない場所に置くため。
//   AI が書いたコードが CI 経由でデプロイされても、Policy の変更や権限の拡大はできない。
// =============================================================================
targetScope = 'subscription'

import { resourceNames, uniqueSuffix } from '../shared/naming.bicep'

@description('ワークロード名（英小文字と数字、3〜10 文字）。')
@minLength(3)
@maxLength(10)
param workloadName string

@description('環境名。')
@allowed([
  'dev'
  'stg'
  'prd'
])
param environmentName string

@description('リソースを配置するリージョン。')
param location string = 'japaneast'

@description('Policy で許可するリージョン。Front Door などのグローバルリソースのために global を含める。')
param allowedLocations array = [
  'japaneast'
  'japanwest'
  'global'
]

@description('GitHub の組織（またはユーザー）名。OIDC の subject に使う。')
param githubOwner string

@description('GitHub のリポジトリ名。')
param githubRepository string

@description('デプロイを許可する GitHub Environment 名。subject を environment に限定し、保護ルールを必須にする。')
param githubEnvironment string = environmentName

@description('Policy の強制モード。初回検証時は DoNotEnforce で影響を確認してから Default に戻す。')
@allowed([
  'Default'
  'DoNotEnforce'
])
param policyEnforcementMode string = 'Default'

@description('全リソースに付けるタグ。')
param tags object = {}

var names = resourceNames(workloadName, environmentName, uniqueSuffix(subscription().id, workloadName, environmentName))
var commonTags = union(tags, {
  workload: workloadName
  environment: environmentName
  managedBy: 'bicep'
})

resource workloadRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: names.workloadResourceGroup
  location: location
  tags: commonTags
}

resource opsRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: names.opsResourceGroup
  location: location
  tags: commonTags
}

module deployer 'modules/deployer.bicep' = {
  scope: opsRg
  name: 'deployer'
  params: {
    identityName: names.deployerIdentity
    location: location
    tags: commonTags
    githubOwner: githubOwner
    githubRepository: githubRepository
    githubEnvironment: githubEnvironment
  }
}

module deployerRoles 'modules/deployer-roles.bicep' = {
  scope: workloadRg
  name: 'deployer-roles'
  params: {
    deployerPrincipalId: deployer.outputs.principalId
  }
}

module guardrails 'modules/policy.bicep' = {
  scope: workloadRg
  name: 'guardrails'
  params: {
    allowedLocations: allowedLocations
    enforcementMode: policyEnforcementMode
    allowedGithubOwners: [
      githubOwner
    ]
    // 外部公開を許すのは Front Door の背後に置くフロントエンドアプリだけ。
    externalIngressExemptResourceIds: [
      resourceId(subscription().subscriptionId, workloadRg.name, 'Microsoft.App/containerApps', names.frontendApp)
    ]
  }
}

output workloadResourceGroupName string = workloadRg.name
output deployerClientId string = deployer.outputs.clientId
output tenantId string = tenant().tenantId
output subscriptionId string = subscription().subscriptionId
