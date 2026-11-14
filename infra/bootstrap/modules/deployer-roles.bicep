// CI デプロイ用 ID に与えるロール（ワークロード RG スコープ）。
//
// 1. Contributor: リソースの作成・更新。ロール割り当てや Policy の変更はできない。
// 2. Role Based Access Control Administrator（条件付き）:
//    ワークロード内のマネージド ID に「決められたロールだけ」を割り当てられるようにする。
//    条件で付与可能なロールと割り当て先の種別を絞るので、CI が自分や他者に
//    Owner などを付与して権限を拡大することはできない。

@description('CI デプロイ用 ID のプリンシパル ID。')
param deployerPrincipalId string

// 組み込みロールの ID（全テナント共通）
var roleIds = {
  contributor: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  rbacAdministrator: 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
  // 以下はワークロードが必要とするロール。増やす場合はここを変更し、bootstrap を再実行する（= 人間のレビューを通す）。
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  monitoringMetricsPublisher: '3913510d-42f4-4e42-8a64-420c390055eb'
}

var assignableRoles = join(
  [
    roleIds.keyVaultSecretsUser
    roleIds.monitoringMetricsPublisher
  ],
  ', '
)

// ABAC 条件: 書き込み・削除とも、上記ロールかつ ServicePrincipal（マネージド ID）宛てのみ許可する。
var rbacCondition = '((!(ActionMatches{\'Microsoft.Authorization/roleAssignments/write\'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${assignableRoles}} AND @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {\'ServicePrincipal\'})) AND ((!(ActionMatches{\'Microsoft.Authorization/roleAssignments/delete\'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${assignableRoles}}))'

resource contributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deployerPrincipalId, roleIds.contributor)
  properties: {
    principalId: deployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.contributor)
    description: 'CI deployer: create and update workload resources'
  }
}

resource constrainedRbacAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deployerPrincipalId, roleIds.rbacAdministrator)
  properties: {
    principalId: deployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.rbacAdministrator)
    description: 'CI deployer: assign only allow-listed roles to workload managed identities'
    condition: rbacCondition
    conditionVersion: '2.0'
  }
}
