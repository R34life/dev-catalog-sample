// ============================================================
// modules/vm.bicep
// Ubuntu 22.04 LTS VM, SSH key auth, cloud-init bootstrap
// ============================================================

param location string
param vmName string
param vmSize string
param adminUsername string

@secure()
param sshPublicKey string

param pythonVersion string
param osDiskSizeGB int
param nicId string

// ── Cloud-Init script ────────────────────────────────────────
// Installs: pyenv, target Python version, virtualenv, dev tools
// Passed as base64-encoded customData to the VM
var cloudInitScript = '''
#cloud-config
package_update: true
package_upgrade: true

packages:
  - git
  - curl
  - wget
  - build-essential
  - libssl-dev
  - zlib1g-dev
  - libbz2-dev
  - libreadline-dev
  - libsqlite3-dev
  - libncursesw5-dev
  - xz-utils
  - tk-dev
  - libxml2-dev
  - libxmlsec1-dev
  - libffi-dev
  - liblzma-dev
  - unzip
  - jq

runcmd:
  # Install pyenv for the admin user
  - su - ${ADMIN_USER} -c 'curl https://pyenv.run | bash'
  # Add pyenv to shell profile
  - |
    cat >> /home/${ADMIN_USER}/.bashrc << 'PROFILE'
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
    PROFILE
  # Install target Python version
  - su - ${ADMIN_USER} -c 'source ~/.bashrc && pyenv install ${PYTHON_VERSION}'
  - su - ${ADMIN_USER} -c 'source ~/.bashrc && pyenv global ${PYTHON_VERSION}'
  # Create a default virtualenv
  - su - ${ADMIN_USER} -c 'source ~/.bashrc && pyenv virtualenv ${PYTHON_VERSION} devenv'
  - su - ${ADMIN_USER} -c 'source ~/.bashrc && pyenv activate devenv && pip install --upgrade pip setuptools wheel'
  # Install common dev tools into the default virtualenv
  - su - ${ADMIN_USER} -c 'source ~/.bashrc && pyenv activate devenv && pip install black ruff pytest ipykernel pre-commit'
  # Set devenv as the default for the user
  - su - ${ADMIN_USER} -c 'echo "devenv" > /home/${ADMIN_USER}/.python-version'
  # Create workspace directory
  - mkdir -p /home/${ADMIN_USER}/workspace
  - chown ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/workspace
  # Write a quick validation script
  - |
    cat > /home/${ADMIN_USER}/workspace/check-env.sh << 'CHECK'
    #!/bin/bash
    source ~/.bashrc
    echo "=== Python Environment Check ==="
    python --version
    pip --version
    pyenv versions
    echo "=== Installed Dev Tools ==="
    python -m black --version
    python -m ruff --version
    python -m pytest --version
    echo "=== Done ==="
    CHECK
  - chmod +x /home/${ADMIN_USER}/workspace/check-env.sh
  - chown ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/workspace/check-env.sh
'''

// Substitute admin username and python version into cloud-init
var cloudInitResolved = replace(replace(cloudInitScript, '${ADMIN_USER}', adminUsername), '${PYTHON_VERSION}', pythonVersion)
var cloudInitBase64   = base64(cloudInitResolved)

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
        sku:       '22_04-lts-gen2'
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
        // No storageUri = managed boot diagnostics (recommended)
      }
    }
  }
}

// ── Azure Monitor Agent extension ────────────────────────────
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

// ── Outputs ──────────────────────────────────────────────────
output vmResourceId string = vm.id
output vmName       string = vm.name
