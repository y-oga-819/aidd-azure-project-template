// ワークロード RG に割り当てる Azure Policy（ガードレール）。
//
// 方針:
//   - 「やってはいけない構成」を Deny で止める。IaC のレビューで見落としても、
//     Azure 側でデプロイ自体が失敗するので、AI が書いた IaC でも安全側に倒れる。
//   - すべて組み込みポリシーを使う。定義 ID は Azure/azure-policy リポジトリで確認済み。
//   - 例外が要る場合は notScopes で対象リソースを明示する（現時点で例外なし）。
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
  // --- App Service ---
  {
    // アプリに届くのは Front Door の Private Link だけにする。
    key: 'app-no-public-network'
    id: '1b5ef780-c53c-4a64-87f3-bb9c8c8094ba'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  {
    key: 'app-https-only'
    id: 'a4af4a39-4135-47fb-b175-47fbdf85311d'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  {
    // Private Link に対応しない SKU（Free / Shared）を拒否する。
    key: 'asp-private-link-sku'
    id: '546fe8d2-368d-4029-a418-6af48a7f61e5'
    parameters: { effect: { value: 'Deny' } }
    notScopes: []
  }
  // 以下は Deny を選べない組み込みポリシー（AuditIfNotExists のみ）。IaC 側で設定し、準拠状況を監査する。
  {
    key: 'app-private-link'
    id: '687aa49d-0982-40f8-bf6b-66d1da97a04b'
    parameters: { effect: { value: 'AuditIfNotExists' } }
    notScopes: []
  }
  {
    key: 'app-latest-tls'
    id: 'f0e6e85b-9b9f-4a4b-b67b-f730d42f1b0b'
    parameters: { effect: { value: 'AuditIfNotExists' } }
    notScopes: []
  }
  {
    key: 'app-ftps-only'
    id: '4d24b6d4-5e53-4a4f-a7f4-618fa573ee4b'
    parameters: { effect: { value: 'AuditIfNotExists' } }
    notScopes: []
  }
  {
    key: 'app-no-remote-debugging'
    id: 'cb510bfd-1cba-4d9f-a230-cb0976f4bb71'
    parameters: { effect: { value: 'AuditIfNotExists' } }
    notScopes: []
  }
  {
    key: 'app-no-ftp-basic-auth'
    id: '871b205b-57cf-4e1e-a234-492616998bf7'
    parameters: { effect: { value: 'AuditIfNotExists' } }
    notScopes: []
  }
  {
    key: 'app-no-scm-basic-auth'
    id: 'aede300b-d67f-480a-ae26-4b3dfb1a1fdc'
    parameters: { effect: { value: 'AuditIfNotExists' } }
    notScopes: []
  }
  {
    key: 'app-managed-identity'
    id: '2b9ad585-36bc-4615-b300-fd4435808332'
    parameters: { effect: { value: 'AuditIfNotExists' } }
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
          message: 'このリソース構成はガードレール (${def.key}) に違反しています。infra/docs/azure-infra-guardrails.md を参照してください。'
        }
      ]
    }
  }
]
