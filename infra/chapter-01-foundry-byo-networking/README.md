# Chapter 01 deployment

This folder turns `chapters/01-foundry-byo-networking.md` into a repeatable Azure deployment.
The Bicep template creates:

- A new VNet with a dedicated `/24` Foundry subnet delegated to `Microsoft.App/environments`.
- A separate `/24` subnet for private endpoints.
- A Microsoft Foundry account with public access and local API-key authentication disabled.
- An actual Foundry project. The chapter's Step 6 only creates a model deployment despite its heading.
- A `gpt-4o` Global Standard deployment at capacity 30, when enabled and quota is available. This is created by a separate idempotent CLI step, not in-template, because deploying a Cognitive Services account and its model deployment in one template races on the account's provisioning state.
- Private Storage and Key Vault resources from the chapter.
- Private endpoints and VNet-linked DNS zones for Foundry, Azure OpenAI, Foundry projects, Blob Storage, and Key Vault.

## Important scope note

This deployment faithfully implements the resources listed in Chapter 01. Current Microsoft guidance for a fully functional **Standard Agent with private networking** additionally requires bring-your-own Azure AI Search and Azure Cosmos DB resources, their private endpoints, project connections, and a capability host. Those resources are not in the chapter and are therefore not silently added here.

Foundry Agent Service network injection must be selected when the account/agent environment is configured. The chapter performs this in the Foundry portal. Do this before creating any hosted agents:

1. Open the Foundry resource in the Azure portal or Microsoft Foundry portal.
2. Keep public network access disabled and select the existing Foundry private endpoint.
3. Select virtual network injection.
4. Choose the emitted VNet and `snet-foundry` delegated subnet.

## Defaults

| Setting | Value |
|---|---|
| Subscription | `ME-MngEnvMCAP152025-snair-1` |
| Tenant | `MngEnvMCAP152025.onmicrosoft.com` |
| Resource group | `rg-agentic-ai-blueprint-dev` |
| Region | `eastus2` |
| Environment | `dev` |

Resource names that must be globally unique receive a deterministic suffix derived from the subscription and resource group.

## Deploy step by step

Run these commands from the repository root in PowerShell:

```powershell
# Sign in only to the requested tenant. Device-code login avoids storing credentials in files.
az login --tenant MngEnvMCAP152025.onmicrosoft.com --use-device-code

# Compile Bicep locally. Success produces no errors or warnings.
az bicep build --file .\infra\chapter-01-foundry-byo-networking\main.bicep

# Create the resource group, validate policy/permissions, and show Azure's exact change preview.
# This does not deploy the resources in the template.
.\infra\chapter-01-foundry-byo-networking\deploy.ps1

# Deploy exactly the previewed template and run control-plane verification commands.
.\infra\chapter-01-foundry-byo-networking\deploy.ps1 -Execute
```

If `gpt-4o` quota or version `2024-11-20` is unavailable in the selected region, deploy the infrastructure first and add a supported model later:

```powershell
.\infra\chapter-01-foundry-byo-networking\deploy.ps1 -DeployModel:$false -Execute
```

Changing `-Location` is supported, but first confirm that the region supports Foundry Agent Service private networking and the requested model. The VNet and Foundry account must use the same region.

## Cost and access considerations

- The Foundry account and Standard_LRS Storage are consumption-based.
- The model deployment consumes regional quota and bills for inference usage, not idle capacity alone.
- Key Vault operations and private endpoints have ongoing charges.
- Because public access is disabled, data-plane access requires VPN, ExpressRoute, or a development host inside the VNet. Azure Resource Manager deployment commands still work from this workstation.

## Validate after portal configuration

From a machine connected to the VNet, resolve each service endpoint with `nslookup`. It must return private IP addresses for the Foundry account, Blob Storage, and Key Vault. Then create and run a test agent only after network injection and all required Standard Agent data resources are connected.