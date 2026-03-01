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
// Built using Bicep string interpolation (NOT ''' raw literals)
// so that adminUsername and pythonVersion are substituted correctly.
//
// The script is split into logical sections and joined — this avoids
// BCP057/BCP062 errors caused by using ${VAR} inside raw string blocks.

var nl = '\n'  // newline shorthand for readability

var cloudInitHeader = '#cloud-config${nl}package_update: true${nl}package_upgrade: true${nl}'

var cloudInitPackages = '${nl}packages:${nl}'
  + '  - git${nl}'
  + '  - curl${nl}'
  + '  - wget${nl}'
  + '  - build-essential${nl}'
  + '  - libssl-dev${nl}'
  + '  - zlib1g-dev${nl}'
  + '  - libbz2-dev${nl}'
  + '  - libreadline-dev${nl}'
  + '  - libsqlite3-dev${nl}'
  + '  - libncursesw5-dev${nl}'
  + '  - xz-utils${nl}'
  + '  - tk-dev${nl}'
  + '  - libxml2-dev${nl}'
  + '  - libxmlsec1-dev${nl}'
  + '  - libffi-dev${nl}'
  + '  - liblzma-dev${nl}'
  + '  - unzip${nl}'
  + '  - jq${nl}'

var cloudInitRuncmd = '${nl}runcmd:${nl}'
  // Install pyenv
  + '  - su - ${adminUsername} -c \'curl https://pyenv.run | bash\'${nl}'
  // Add pyenv to .bashrc
  + '  - su - ${adminUsername} -c \'echo export PYENV_ROOT=\\\"\\$HOME/.pyenv\\\" >> ~/.bashrc\'${nl}'
  + '  - su - ${adminUsername} -c \'echo export PATH=\\\"\\$PYENV_ROOT/bin:\\$PATH\\\" >> ~/.bashrc\'${nl}'
  + '  - su - ${adminUsername} -c \'echo eval \\\"\\$(pyenv init -)\\\" >> ~/.bashrc\'${nl}'
  + '  - su - ${adminUsername} -c \'echo eval \\\"\\$(pyenv virtualenv-init -)\\\" >> ~/.bashrc\'${nl}'
  // Install Python version
  + '  - su - ${adminUsername} -c \'export PYENV_ROOT=\\$HOME/.pyenv && export PATH=\\$PYENV_ROOT/bin:\\$PATH && eval \\\"\\$(pyenv init -)\\\" && pyenv install ${pythonVersion}\'${nl}'
  + '  - su - ${adminUsername} -c \'export PYENV_ROOT=\\$HOME/.pyenv && export PATH=\\$PYENV_ROOT/bin:\\$PATH && eval \\\"\\$(pyenv init -)\\\" && pyenv global ${pythonVersion}\'${nl}'
  // Create virtualenv and install dev tools
  + '  - su - ${adminUsername} -c \'export PYENV_ROOT=\\$HOME/.pyenv && export PATH=\\$PYENV_ROOT/bin:\\$PATH && eval \\\"\\$(pyenv init -)\\\" && eval \\\"\\$(pyenv virtualenv-init -)\\\" && pyenv virtualenv ${pythonVersion} devenv\'${nl}'
  + '  - su - ${adminUsername} -c \'export PYENV_ROOT=\\$HOME/.pyenv && export PATH=\\$PYENV_ROOT/bin:\\$PATH && eval \\\"\\$(pyenv init -)\\\" && eval \\\"\\$(pyenv virtualenv-init -)\\\" && pyenv activate devenv && pip install --upgrade pip setuptools wheel\'${nl}'
  + '  - su - ${adminUsername} -c \'export PYENV_ROOT=\\$HOME/.pyenv && export PATH=\\$PYENV_ROOT/bin:\\$PATH && eval \\\"\\$(pyenv init -)\\\" && eval \\\"\\$(pyenv virtualenv-init -)\\\" && pyenv activate devenv && pip install black ruff pytest ipykernel pre-commit\'${nl}'
  // Set devenv as default and create workspace
  + '  - su - ${adminUsername} -c \'echo devenv > ~/.python-version\'${nl}'
  + '  - mkdir -p /home/${adminUsername}/workspace${nl}'
  + '  - chown ${adminUsername}:${adminUsername} /home/${adminUsername}/workspace${nl}'
  // Write validation script
  + '  - |${nl}'
  + '    cat > /home/${adminUsername}/workspace/check-env.sh << \'CHECKEOF\'${nl}'
  + '    #!/bin/bash${nl}'
  + '    source ~/.bashrc${nl}'
  + '    echo "=== Python Environment Check ==="${nl}'
  + '    python --version${nl}'
  + '    pip --version${nl}'
  + '    pyenv versions${nl}'
  + '    echo "=== Installed Dev Tools ==="${nl}'
  + '    python -m black --version${nl}'
  + '    python -m ruff --version${nl}'
  + '    python -m pytest --version${nl}'
  + '    echo "=== Done ==="${nl}'
  + '    CHECKEOF${nl}'
  + '  - chmod +x /home/${adminUsername}/workspace/check-env.sh${nl}'
  + '  - chown ${adminUsername}:${adminUsername} /home/${adminUsername}/workspace/check-env.sh${nl}'

var cloudInitFull   = '${cloudInitHeader}${cloudInitPackages}${cloudInitRuncmd}'
var cloudInitBase64 = base64(cloudInitFull)

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
        // No storageUri = managed boot diagnostics (free, recommended)
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
