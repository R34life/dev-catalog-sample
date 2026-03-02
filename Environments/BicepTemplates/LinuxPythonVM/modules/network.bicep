// ============================================================
// modules/network.bicep
// VNet, NSG, Azure Bastion Standard, VM NIC
// Fixed: AzureBastionSubnet /26, explicit dependsOn, resourceId refs
// ============================================================

param location string
param vnetName string
param subnetVmName string
param nsgName string
param bastionName string
param bastionPipName string

// ── Address spaces ───────────────────────────────────────────
var vnetAddressPrefix   = '10.0.0.0/16'
var subnetBastionPrefix = '10.0.0.0/26'   // /26 required for Bastion Standard SKU
var subnetVmPrefix      = '10.0.1.0/24'

// ── NSG (VM subnet only) ─────────────────────────────────────
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          priority:                 100
          protocol:                 'Tcp'
          access:                   'Allow'
          direction:                'Inbound'
          sourceAddressPrefix:      subnetBastionPrefix
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '22'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority:                 4096
          protocol:                 '*'
          access:                   'Deny'
          direction:                'Inbound'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '*'
        }
      }
      {
        name: 'Allow-Outbound-HTTPS'
        properties: {
          priority:                 100
          protocol:                 'Tcp'
          access:                   'Allow'
          direction:                'Outbound'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange:     '443'
        }
      }
      {
        name: 'Allow-Outbound-HTTP'
        properties: {
          priority:                 110
          protocol:                 'Tcp'
          access:                   'Allow'
          direction:                'Outbound'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange:     '80'
        }
      }
    ]
  }
}

// ── VNet + Subnets ───────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressPrefix ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'   // exact name required by Azure
        properties: {
          addressPrefix: subnetBastionPrefix
          // No NSG on Bastion subnet — Bastion manages its own rules
        }
      }
      {
        name: subnetVmName
        properties: {
          addressPrefix: subnetVmPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// ── Bastion Public IP ────────────────────────────────────────
resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: bastionPipName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ── Azure Bastion Standard ───────────────────────────────────
resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling:     true
    enableIpConnect:     true
    disableCopyPaste:    false
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'AzureBastionSubnet')
          }
          publicIPAddress: {
            id: bastionPip.id
          }
        }
      }
    ]
  }
  dependsOn: [ vnet ]
}

// ── VM NIC (no public IP) ────────────────────────────────────
resource vmNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'nic-vm-${vnetName}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetVmName)
          }
        }
      }
    ]
  }
  dependsOn: [ vnet ]
}

// ── Outputs ──────────────────────────────────────────────────
output vmNicId      string = vmNic.id
output vmPrivateIp  string = vmNic.properties.ipConfigurations[0].properties.privateIPAddress
output vnetId       string = vnet.id
output bastionId    string = bastion.id
