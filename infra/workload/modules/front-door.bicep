// Front Door Premium + WAF。インターネットからの唯一の入口。
//   - オリジン（App Service）へは Private Link で接続する。アプリ自体はパブリックアクセス無効。
//   - 経路は origins 配列で受け取る。現在はアプリ 1 つに全パスを送る（/api の振り分けはアプリ内で行う）。
//   - WAF は Prevention モードで、マネージドルール（Default Rule Set と Bot Manager）を有効化。
//   - HTTP は HTTPS へリダイレクト。
//
// 注意: Private Link 接続は App Service 側で「承認」が必要。
//       デプロイ後に `mise run //infra:approve-private-link` を実行する（docs/guardrails.md 参照）。

param profileName string
param endpointName string
param wafPolicyName string
param tags object

@description('振り分け先。{ name, hostName, resourceId, patterns } の配列。patterns が具体的なものを先に書く。')
param origins array

@description('Private Link の接続先リージョン。')
param privateLinkLocation string

param logAnalyticsWorkspaceId string

resource waf 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: wafPolicyName
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: 'Enabled'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
        }
      ]
    }
  }
}

resource profile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: profileName
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: profile
  name: endpointName
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

// オリジンが 1 つだけなので、ヘルスプローブは無効にする（無駄なトラフィックを避ける。Microsoft の推奨）。
// Front Door の子リソースは並列に更新すると競合しやすいので 1 つずつ作る。
@batchSize(1)
resource originGroups 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = [
  for o in origins: {
    parent: profile
    name: o.name
    properties: {
      loadBalancingSettings: {
        sampleSize: 4
        successfulSamplesRequired: 3
        additionalLatencyInMilliseconds: 50
      }
    }
  }
]

// Front Door の子リソースは並列に更新すると競合しやすいので 1 つずつ作る。
@batchSize(1)
resource originResources 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = [
  for (o, i) in origins: {
    parent: originGroups[i]
    name: o.name
    properties: {
      hostName: o.hostName
      originHostHeader: o.hostName
      httpPort: 80
      httpsPort: 443
      priority: 1
      weight: 1000
      enabledState: 'Enabled'
      enforceCertificateNameCheck: true
      sharedPrivateLinkResource: {
        privateLink: {
          id: o.resourceId
        }
        groupId: 'sites'
        privateLinkLocation: privateLinkLocation
        requestMessage: 'Front Door ${profileName}'
      }
    }
  }
]

// Front Door の子リソースは並列に更新すると競合しやすいので 1 つずつ作る。
@batchSize(1)
resource routes 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = [
  for (o, i) in origins: {
    parent: endpoint
    name: o.name
    dependsOn: [
      originResources[i]
    ]
    properties: {
      originGroup: {
        id: originGroups[i].id
      }
      supportedProtocols: [
        'Http'
        'Https'
      ]
      patternsToMatch: o.patterns
      forwardingProtocol: 'HttpsOnly'
      httpsRedirect: 'Enabled'
      linkToDefaultDomain: 'Enabled'
    }
  }
]

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-02-01' = {
  parent: profile
  name: 'waf'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: waf.id
      }
      associations: [
        {
          domains: [
            {
              id: endpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: profile
  name: 'to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output endpointHostName string = endpoint.properties.hostName
