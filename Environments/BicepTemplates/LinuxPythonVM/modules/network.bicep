// ============================================================
// modules/network.bicep
// VNet, Subnets, NSG, Azure Bastion, VM NIC
//
// Fixed:
//   - AzureBastionSubnet bumped to /26 (Standard SKU minimum)
//   - NSG only on VM subnet, NOT on Bastion subnet
//   - Bastion dependsOn vnet made explicit to avoid race condition
// ============================================================

param location string
param vnetName string
param subnetVmName string
param nsgName string
param bastionName string
param bastionPipName string

// ── Address spaces ───────────────────────────────────────────
var vnetAddressPrefix   = '10.0.0.0/16'
var subnetBastionPrefix = '10.0.0.0/26'   // /26 = 64 addresses, required for Standard SKU
var subnetVmPrefix      = '10.0.1.0/24'   // VM subnet, separate range

// ── NSG (VM subnet only) ─────────────────────────────────────
// Do NOT attach this NSG to AzureBastionSubnet.
// Bastion manages its own subnet rules implicitly.
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      // Allow SSH inbound from Bastion subnet only
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
      // Deny all other inbound
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
      // Allow outbound HTTPS (pip, apt, pyenv)
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
      // Allow outbound HTTP (apt mirrors)
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
      // AzureBastionSubnet — exact name required by Azure, no NSG
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: subnetBastionPrefix
        }
      }
      // VM subnet — NSG attached here only
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

// ── Azure Bastion Standard SKU ───────────────────────────────
// Standard SKU required for enableTunneling (native SSH from terminal)
// dependsOn vnet is implicit via subnet reference, but listed explicitly
// to prevent the race condition where Bastion provisions before subnets settle
resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling:         true
    enableIpConnect:         true
    disableCopyPaste:        false
    enableShareableLink:     false
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
