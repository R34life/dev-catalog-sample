// ============================================================
// azuredeploy.bicep — ADE LinuxPythonVM entry point
// ============================================================

@description('Name for the developer VM')
param vmName string

@description('Linux admin username')
param adminUsername string = 'devuser'

@description('SSH public key for the admin user')
@secure()
param sshPublicKey string

@description('Azure VM SKU')
@allowed([
  'Standard_D2s_v5'
  'Standard_D4s_v5'
  'Standard_D8s_v5'
])
param vmSize string = 'Standard_D4s_v5'

@description('Azure region')
param location string = resourceGroup().location

@description('OS disk size in GB')
@allowed([ 64, 128, 256 ])
param osDiskSizeGB int = 128

// ── Derived names ─────────────────────────────────────────────
var vnetName       = 'vnet-${vmName}'
var subnetVmName   = 'snet-vm'
var nsgName        = 'nsg-${vmName}'
var bastionName    = 'bas-${vmName}'
var bastionPipName = 'pip-bas-${vmName}'

// ── Networking module ─────────────────────────────────────────
module network 'modules/network.bicep' = {
  name: 'network-${vmName}'
  params: {
    location:      location
    vnetName:      vnetName
    subnetVmName:  subnetVmName
    nsgName:       nsgName
    bastionName:   bastionName
    bastionPipName: bastionPipName
  }
}

// ── VM module ─────────────────────────────────────────────────
module vm 'modules/vm.bicep' = {
  name: 'vm-${vmName}'
  params: {
    location:      location
    vmName:        vmName
    vmSize:        vmSize
    adminUsername: adminUsername
    sshPublicKey:  sshPublicKey
    osDiskSizeGB:  osDiskSizeGB
    nicId:         network.outputs.vmNicId
  }
}

// ── Outputs ───────────────────────────────────────────────────
output vmResourceId     string = vm.outputs.vmResourceId
output privateIpAddress string = network.outputs.vmPrivateIp
output bastionName      string = bastionName
output vnetName         string = vnetName
