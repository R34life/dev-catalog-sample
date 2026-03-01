// ============================================================
// modules/vm.bicep
// Ubuntu 22.04 LTS ARM64 VM — SSH key auth, cloud-init
//
// Uses ARM64 image (arm64) to match Standard_B*p*_v2 SKUs
// which are the only ones available on this subscription.
// ============================================================

param location string
param vmName string
param vmSize string
param adminUsername string

@secure()
param sshPublicKey string

param osDiskSizeGB int
param nicId string

// ── Load cloud-init from file ────────────────────────────────
var cloudInitBase64 = loadFileAsBase64('../cloud-init.yml')

// ── VM Resource ──────────────────────────────────────────────
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer:     '0001-com-ubuntu-server-jammy'
        sku:       '22_04-lts-arm64'       // ARM64 image for *p* SKUs
        version:   'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: osDiskSizeGB
      }
    }
    osProfile: {
      computerName:  vmName
      adminUsername: adminUsername
      customData:    cloudInitBase64
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path:    '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicId
          properties: {
            primary: true
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// ── Azure Monitor Agent ───────────────────────────────────────
resource amaExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: vm
  name: 'AzureMonitorLinuxAgent'
  location: location
  properties: {
    publisher:               'Microsoft.Azure.Monitor'
    type:                    'AzureMonitorLinuxAgent'
    typeHandlerVersion:      '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade:  true
  }
}

// ── Outputs ───────────────────────────────────────────────────
output vmResourceId string = vm.id
output vmName       string = vm.name
