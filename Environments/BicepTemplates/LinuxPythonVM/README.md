# ADE Catalog — Linux Python Developer VM

This repository is an **Azure Deployment Environments (ADE) catalog**.
It contains environment definitions that developers can deploy as self-service
environments from the Azure Developer Portal, CLI, or automatically via GitHub Actions.

## Repo Structure

```
ade-catalog/
├── .github/
│   └── workflows/
│       └── ade-environments.yml     # Auto-create/delete on PR open/close
│
└── Environments/
    └── LinuxPythonVM/               # One folder = one ADE environment definition
        ├── environment.yaml         # ADE manifest (name, params, runner, templatePath)
        ├── azuredeploy.bicep        # Root Bicep template (entry point for ADE)
        └── modules/
            ├── network.bicep        # VNet, NSG (SSH from Bastion only), Bastion
            └── vm.bicep             # Ubuntu 22.04 VM + cloud-init (pyenv + Python)
```

## What Gets Deployed

| Resource             | Details                                          |
|----------------------|--------------------------------------------------|
| Virtual Network      | `10.0.0.0/16` with VM subnet + Bastion subnet    |
| NSG                  | Deny all inbound except SSH from Bastion subnet  |
| Azure Bastion        | Standard SKU, SSH tunneling enabled              |
| Ubuntu VM            | 22.04 LTS, SSH key auth only, no public IP       |
| Python (via pyenv)   | Configurable version (3.11, 3.12, 3.13)          |
| Dev virtualenv       | `devenv` with black, ruff, pytest, ipykernel     |

## Developer: How to Create an Environment

### Option 1 — Developer Portal
1. Go to [https://devportal.microsoft.com](https://devportal.microsoft.com)
2. Select your project → **New Environment**
3. Choose **LinuxPythonVM**, fill in parameters, deploy

### Option 2 — Azure CLI
```bash
az devcenter dev environment create \
  --dev-center-name  <devcenter-name> \
  --project-name     <project-name> \
  --environment-name my-dev-env \
  --environment-type Dev \
  --catalog-name     ade-catalog \
  --environment-definition-name LinuxPythonVM \
  --parameters '{
    "vmName":        "dev-alice",
    "adminUsername": "devuser",
    "sshPublicKey":  "ssh-rsa AAAA...",
    "pythonVersion": "3.12.3"
  }'
```

### Option 3 — Automatic via GitHub Actions
Open a PR → environment is created automatically and a comment is posted with
the resource group link and Bastion SSH command. Environment is deleted when the PR closes.

## Connect to Your VM

```bash
# Via Azure Bastion native client
az network bastion ssh \
  --name bas-<vm-name> \
  --resource-group <rg-name> \
  --target-resource-id <vm-resource-id> \
  --auth-type ssh-key \
  --username devuser \
  --ssh-key ~/.ssh/id_rsa
```

## Required GitHub Repository Variables

Set these in **Settings → Secrets and variables → Actions → Variables**:

| Variable                | Description                              |
|-------------------------|------------------------------------------|
| `DEVCENTER_NAME`        | Name of your Azure DevCenter             |
| `ADE_PROJECT_NAME`      | ADE Project name                         |
| `ADE_CATALOG_NAME`      | This catalog's name as registered in ADE |
| `AZURE_CLIENT_ID`       | Service Principal / App client ID        |
| `AZURE_TENANT_ID`       | Azure AD tenant ID                       |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID                   |

And this **Secret**:

| Secret               | Description                              |
|----------------------|------------------------------------------|
| `DEV_SSH_PUBLIC_KEY` | SSH public key injected into the VM      |

## Platform Admin: Attach This Catalog to DevCenter

```bash
az devcenter admin catalog create \
  --name            ade-catalog \
  --dev-center-name <devcenter-name> \
  --resource-group  <platform-rg> \
  --git-hub '{
    "uri":          "https://github.com/<org>/ade-catalog.git",
    "branch":       "main",
    "path":         "/Environments",
    "secretIdentifier": "https://<keyvault>.vault.azure.net/secrets/github-pat"
  }'
```

> **Tip:** Use the [Microsoft DevCenter GitHub App](https://github.com/apps/microsoft-devcenter)
> instead of a PAT to avoid credential rotation.
