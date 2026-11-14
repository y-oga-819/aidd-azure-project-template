// ネットワーク。
//   - snet-app: App Service の VNet 統合（アプリからの送信）用。Microsoft.Web/serverFarms に委任する。
//   - snet-pe : Key Vault / ACR の Private Endpoint を置くサブネット。
//   - Private DNS ゾーン: Private Endpoint の名前解決用。
//
// アプリと PaaS はすべてパブリックアクセスを無効にする。
// インターネットからの入口は Front Door（Private Link 経由）だけ。

param vnetName string
param nsgAppIntegrationName string
param nsgPrivateEndpointsName string
param location string
param tags object

param addressPrefix string
param appIntegrationSubnetPrefix string
param privateEndpointSubnetPrefix string

// Private DNS ゾーン名。順序は outputs のインデックスと対応する。
var privateDnsZoneNames = [
  'privatelink.vaultcore.azure.net'
  'privatelink.azurecr.io'
]

resource nsgAppIntegration 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgAppIntegrationName
  location: location
  tags: tags
  properties: {
    // VNet 統合サブネットはアプリからの送信だけに使われ、受信はない。既定ルールに任せる。
    // 送信の制限（Azure Firewall + UDR）は未対応。docs/guardrails.md の「今後」を参照。
    securityRules: []
  }
}

resource nsgPrivateEndpoints 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgPrivateEndpointsName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-AppIntegration-To-PrivateEndpoints-443'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: appIntegrationSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: privateEndpointSubnetPrefix
          destinationPortRange: '443'
        }
      }
      {
        // Private Endpoint へはアプリからの HTTPS だけを通す（Key Vault 参照・イメージのプルとも 443）。
        name: 'Deny-All-Other-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: appIntegrationSubnetPrefix
          networkSecurityGroup: {
            id: nsgAppIntegration.id
          }
          delegations: [
            {
              name: 'Microsoft.Web.serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          networkSecurityGroup: {
            id: nsgPrivateEndpoints.id
          }
          // NSG を Private Endpoint にも効かせる。
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [
  for zoneName in privateDnsZoneNames: {
    name: zoneName
    location: 'global'
    tags: tags
  }
]

resource privateDnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for (zoneName, i) in privateDnsZoneNames: {
    parent: privateDnsZones[i]
    name: '${vnetName}-link'
    location: 'global'
    tags: tags
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
]

output vnetId string = vnet.id
output appIntegrationSubnetId string = vnet.properties.subnets[0].id
output privateEndpointSubnetId string = vnet.properties.subnets[1].id
output keyVaultDnsZoneId string = privateDnsZones[0].id
output containerRegistryDnsZoneId string = privateDnsZones[1].id
