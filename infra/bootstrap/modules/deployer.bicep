// CI（GitHub Actions）がデプロイに使うユーザー割り当てマネージド ID。
// シークレットを持たず、GitHub の OIDC トークンとフェデレーションして Azure にサインインする。
//
// この ID は ops リソースグループに置き、CI 自身には ops RG への権限を与えない。
// ワークロード RG に置くと、Contributor 権限を持つ CI が自分の ID に別リポジトリの
// フェデレーション資格情報を追加でき、権限の横取りにつながるため。

@description('マネージド ID の名前。')
param identityName string

param location string
param tags object

param githubOwner string
param githubRepository string
param githubEnvironment string

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

// subject を GitHub Environment 単位に限定する。
// ブランチや PR からのトークンではサインインできず、Environment の保護ルール（承認者など）を通過したジョブだけが使える。
resource federation 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: identity
  name: 'github-${githubEnvironment}'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOwner}/${githubRepository}:environment:${githubEnvironment}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
