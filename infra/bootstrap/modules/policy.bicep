// ワークロード RG に割り当てる Azure Policy（ガードレール）。
//
// 方針:
//   - 「やってはいけない構成」を Deny で止める。IaC のレビューで見落としても、
//     Azure 側でデプロイ自体が失敗するので、AI が書いた IaC でも安全側に倒れる。
//   - すべて組み込みポリシーを使う。定義 ID は Azure/azure-policy リポジトリで確認済み。
//   - 例外が要る場合は notScopes で対象リソースを明示する（フロントエンドアプリの外部公開のみ）。
//
// 割り当ては bootstrap（特権者）からのみ行い、CI のデプロイ用 ID は変更できない。

param allowedLocations array

@allowed([
  'Default'
  'DoNotEnforce'
])
param enforcementMode string

@description('フェデレーション資格情報（GitHub）で許可するリポジトリ所有者。')
param allowedGithubOwners array

@description('Container Apps の外部公開禁止ポリシーから除外するアプリのリソース ID。')
param externalIngressExemptResourceIds array = []

var definitions = [
  // --- 全般 ---
  {
    key: 'allowed-locations'
    id: 'e56962a6-4747-49cd-b67b-bf8b01975c4c'
    parameters: {
      listOfAllowedLocations: { value: allowedLocations }
      effect: { value: 'Deny' }
    }
    notScopes: []
  }
  // --- Key Vault ---
  {
    key: 'kv-no-public-network'
    id: '405c5871-3e91-4644-8a63-58e19d68ff5b'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  {
    key: 'kv-rbac-only'
    id: '12d4fa5e-1f9f-4c21-97a9-b99b3c6611b5'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  {
    key: 'kv-purge-protection'
    id: '0b60c0b2-2dc2-4e1c-b5c9-abbed971de53'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  {
    key: 'kv-resource-logs'
    id: 'cf820ca0-f99e-4f3e-84fb-66e913812d21'
    // 保持日数はワークスペース側で管理するため 0（= 診断設定の存在のみ確認）にする。
    parameters: {
      effect: { value: 'AuditIfNotExists' }
      requiredRetentionDays: { value: '0' }
    }
    notScopes: []
  }
  // --- Container Registry ---
  {
    key: 'acr-no-public-network'
    id: '0fdf0491-d080-4575-b627-ad0e843cba0f'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  {
    key: 'acr-no-admin-user'
    id: 'dc921057-6b28-4fbe-9b83-f7bec05db6c2'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  {
    key: 'acr-no-anonymous-pull'
    id: '9f2dea28-e834-476c-99c5-3507b4728395'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  // --- Container Apps ---
  {
    key: 'cae-vnet-injection'
    id: '8b346db6-85af-419b-8557-92cee2c0f9bb'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  {
    key: 'cae-internal-only'
    id: 'd074ddf8-01a5-4b5e-a2b8-964aed452c0a'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  {
    key: 'ca-no-external-ingress'
    id: '783ea2a8-b8fd-46be-896a-9ae79643a0b1'
    parameters: { effect: { value: 'Deny' } }
    notScopes: externalIngressExemptResourceIds
  }
  {
    key: 'ca-https-only'
    id: '0e80e269-43a4-4ae9-b5bc-178126b8a5cb'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  {
    key: 'ca-managed-identity'
    id: 'b874ab2d-72dd-47f1-8cb5-4a306478a4e7'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  // --- Managed Identity ---
  {
    // [Preview] GitHub とのフェデレーションを自組織のリポジトリに限定する。
    key: 'fic-github-owner'
    id: 'fd1a8e20-2c4f-4a6c-9354-b58d786d9a1f'
    parameters: {
      allowedRepoOwners: { value: allowedGithubOwners }
      effect: { value: 'Deny' }
    }
    notScopes: []
  }
]

resource assignments 'Microsoft.Authorization/policyAssignments@2024-04-01' = [
  for def in definitions: {
    name: 'guardrail-${def.key}'
    properties: {
      displayName: 'guardrail: ${def.key}'
      policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', def.id)
      parameters: def.parameters
      enforcementMode: enforcementMode
      notScopes: def.notScopes
      nonComplianceMessages: [
        {
          message: 'このリソース構成はガードレール (${def.key}) に違反しています。infra/docs/guardrails.md を参照してください。'
        }
      ]
    }
  }
]
