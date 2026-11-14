// ネットワーク。
//   - snet-cae: Container Apps 環境（内部モード）を注入するサブネット。
//   - snet-pe : Key Vault / ACR などの Private Endpoint を置くサブネット。
//   - Private DNS ゾーン: Private Endpoint の名前解決用。
//
// PaaS は全て Private Endpoint 経由でのみ到達でき、パブリックアクセスは無効にする。
// インターネットからの入口は Front Door（Private Link 経由）だけ。

param vnetName string
param nsgContainerAppsName string
param nsgPrivateEndpointsName string
param location string
param tags object

param addressPrefix string
param containerAppsSubnetPrefix string
param privateEndpointSubnetPrefix string

// Private DNS ゾーン名。順序は outputs のインデックスと対応する。
var privateDnsZoneNames = [
  'privatelink.vaultcore.azure.net'
  'privatelink.azurecr.io'
]

resource nsgContainerApps 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgContainerAppsName
  location: location
  tags: tags
  properties: {
    // 内部モードの Container Apps 環境は Azure 管理のトラフィックを必要とするため、
    // 既定ルール（VNet 内と Azure Load Balancer からの受信のみ許可、インターネットからの受信は拒否）に任せる。
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
        name: 'Allow-ContainerApps-To-PrivateEndpoints-443'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: containerAppsSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: privateEndpointSubnetPrefix
          destinationPortRange: '443'
        }
      }
      {
        // Private Endpoint へは Container Apps からの HTTPS だけを通す（VNet 内の横移動を抑える）。
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
        name: 'snet-cae'
        properties: {
          addressPrefix: containerAppsSubnetPrefix
          networkSecurityGroup: {
            id: nsgContainerApps.id
          }
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
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
output containerAppsSubnetId string = vnet.properties.subnets[0].id
output privateEndpointSubnetId string = vnet.properties.subnets[1].id
output keyVaultDnsZoneId string = privateDnsZones[0].id
output containerRegistryDnsZoneId string = privateDnsZones[1].id
