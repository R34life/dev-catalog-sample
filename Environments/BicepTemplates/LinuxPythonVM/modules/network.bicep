// ============================================================
// modules/network.bicep
// VNet, Subnets, NSG, Azure Bastion, VM NIC
// ============================================================

param location string
param vnetName string
param subnetVmName string
param nsgName string
param bastionName string
param bastionPipName string

// ── Address spaces ───────────────────────────────────────────
var vnetAddressPrefix       = '10.0.0.0/16'
var subnetVmPrefix          = '10.0.1.0/24'
var subnetBastionPrefix     = '10.0.0.0/27'   // AzureBastionSubnet min /27

// ── NSG ─────────────────────────────────────────────────────
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      // Allow SSH only from the Bastion subnet
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: subnetBastionPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      // Deny all other inbound
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      // Allow outbound HTTPS (pip install, apt, etc.)
      {
        name: 'Allow-Outbound-HTTPS'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '443'
        }
      }
      // Allow outbound HTTP (apt mirrors)
      {
        name: 'Allow-Outbound-HTTP'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '80'
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
      // AzureBastionSubnet — name is REQUIRED by Azure
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: subnetBastionPrefix
        }
      }
      // VM subnet — NSG attached
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

// ── Azure Bastion (Standard SKU for native SSH tunneling) ────
resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: true   // Enables az network bastion ssh / VS Code Remote
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/AzureBastionSubnet'
          }
          publicIPAddress: {
            id: bastionPip.id
          }
        }
      }
    ]
  }
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
            id: '${vnet.id}/subnets/${subnetVmName}'
          }
        }
      }
    ]
  }
}

// ── Outputs ──────────────────────────────────────────────────
output vmNicId      string = vmNic.id
output vmPrivateIp  string = vmNic.properties.ipConfigurations[0].properties.privateIPAddress
output vnetId       string = vnet.id
output bastionId    string = bastion.id
