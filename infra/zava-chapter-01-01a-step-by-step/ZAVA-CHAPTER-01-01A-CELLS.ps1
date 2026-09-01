#requires -Version 7.0
<#
.SYNOPSIS
    Zava Chapters 01 and 01a interactive PowerShell deployment workbook.

.DESCRIPTION
    This is a real executable PowerShell workbook organized with # %% cell markers.

    VS Code usage:
      1. Install the Microsoft PowerShell extension: ms-vscode.PowerShell.
      2. Open this file in VS Code.
      3. Place the cursor in one section between two # %% markers.
      4. Select that section and press F8 (Run Selection) in the PowerShell Extension terminal.
      5. Run cells from top to bottom. Variables persist in the same terminal session.

    The Microsoft PowerShell extension does not provide a native Jupyter notebook kernel.
    This file provides the notebook-like workflow without Polyglot Notebooks.

    SAFETY:
      - Preview and validation cells do not deploy resources.
      - Every Azure-changing cell has an approval variable that defaults to $false.
      - Step 00 lab simulation files are intentionally not used here.
      - Capability hosts are one-time resources and must never be blindly resubmitted.
#>

# %% [markdown] CELL 1 — HOW TO USE THIS WORKBOOK
# Run one cell at a time with F8 in the same PowerShell Extension terminal.
# A cell is all code between two lines beginning with "# %%".
#
# Install the supported extension if needed:
#   code --install-extension ms-vscode.PowerShell
#
# Use PowerShell 7. The status bar should show a PowerShell 7 session.
# Do not use "Run PowerShell File" because that would process every cell.
# Never run this entire file with F5 or .\ZAVA-CHAPTER-01-01A-CELLS.ps1.

# %% CELL 2 — CONFIGURE ZAVA VALUES (edit placeholders, then press F8)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 or later is required. Use PowerShell: Show Session Menu in VS Code to select PowerShell 7.'
}

# Customer identity and resource scopes.
$tenantId       = '<Zava-tenant-id>'
$subscription   = '<Zava-subscription-id-or-name>'
$workloadRg     = '<Zava-workload-resource-group>'
$networkRg      = '<Zava-network-resource-group>'
$dnsRg          = '<Zava-private-dns-resource-group>'

# Approved regional and network values.
$location          = 'eastus'
$searchLocation    = 'eastus'
$vnet              = 'azr-133-eastus'
$agentSubnet       = 'snet-zava-foundry-agent'
$agentSubnetPrefix = '10.75.139.160/27'
$peSubnet          = 'snet-zava-privateendpoints'
$peSubnetPrefix    = '10.75.139.144/28'

# Workload naming.
$workload    = 'zava'
$environment = 'dev'

# DNS ownership:
# $true  = workload deployment creates PE DNS-zone groups in existing Zava zones.
# $false = Zava DNS automation creates zone groups/records after endpoints are created.
$createPrivateEndpointDnsZoneGroups = $true

# Optional human access. This is resolved after login unless explicitly supplied.
$foundryUserObjectId = ''

# Resolve source paths from the cloned Git repository.
$repoRoot = (git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) { throw 'Open and run this file from the cloned Git repository.' }
$infraFolder = Join-Path $repoRoot 'infra\zava-chapter-01-01a-step-by-step'
$subnetTemplate    = Join-Path $infraFolder '01-create-foundry-subnets.bicep'
$dnsLinkTemplate   = Join-Path $infraFolder '02-link-customer-private-dns.bicep'
$chapter01Template = Join-Path $infraFolder '03-chapter-01-foundation.bicep'
$coreTemplate      = Join-Path $infraFolder '04-chapter-01a-standard-core.bicep'
$hostTemplate      = Join-Path $infraFolder '05-chapter-01a-capability-hosts.bicep'
$recoveryScript    = Join-Path $infraFolder 'recover-capability-hosts.ps1'

function Assert-Configured {
    param([string] $Name, [string] $Value)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -match '^<.*>$') {
        throw "Configure `$${Name} before continuing."
    }
}

function Invoke-AzChecked {
    param([Parameter(Mandatory)][string[]] $Arguments)
    Write-Host ('az ' + ($Arguments -join ' ')) -ForegroundColor DarkGray
    & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed with exit code $LASTEXITCODE."
    }
}

function Build-Bicep {
    param([Parameter(Mandatory)][string] $Template)
    Invoke-AzChecked @('bicep', 'build', '--file', $Template, '--stdout') | Out-Null
    Write-Host "Bicep compilation passed: $Template" -ForegroundColor Green
}

function Assert-Approval {
    param([bool] $Approved, [string] $Action)
    if (-not $Approved) {
        throw "$Action is blocked. Review the preceding what-if, then set its approval variable to `$true."
    }
}

'TenantId','Subscription','WorkloadRg','NetworkRg','DnsRg' | ForEach-Object {
    Assert-Configured $_ (Get-Variable -Name $_ -ValueOnly)
}

[pscustomobject]@{
    Repository            = $repoRoot
    TenantId              = $tenantId
    Subscription          = $subscription
    WorkloadResourceGroup = $workloadRg
    NetworkResourceGroup  = $networkRg
    DnsResourceGroup      = $dnsRg
    Location              = $location
    VNet                  = $vnet
    AgentSubnet           = "$agentSubnet ($agentSubnetPrefix)"
    PrivateEndpointSubnet = "$peSubnet ($peSubnetPrefix)"
    WorkloadManagesPeDns  = $createPrivateEndpointDnsZoneGroups
} | Format-List

# %% CELL 3 — SIGN IN AND VERIFY THE IMMUTABLE TENANT/SUBSCRIPTION
Invoke-AzChecked @('login', '--tenant', $tenantId, '--use-device-code')
Invoke-AzChecked @('account', 'set', '--subscription', $subscription)

$azureAccount = az account show --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the selected Azure account.' }
if ($azureAccount.tenantId -ne $tenantId) {
    throw "Tenant mismatch: active=$($azureAccount.tenantId), expected=$tenantId"
}
$subscriptionId = $azureAccount.id

if (-not $foundryUserObjectId) {
    $foundryUserObjectId = az ad signed-in-user show --query id --output tsv
    if ($LASTEXITCODE -ne 0 -or -not $foundryUserObjectId) {
        throw 'Unable to resolve the signed-in user object ID. Set $foundryUserObjectId explicitly.'
    }
}

[pscustomobject]@{
    Subscription   = $azureAccount.name
    SubscriptionId = $subscriptionId
    TenantId       = $azureAccount.tenantId
    User           = $azureAccount.user.name
    UserObjectId   = $foundryUserObjectId
} | Format-List

# %% CELL 4 — CHECK REQUIRED RESOURCE PROVIDERS (read-only)
# This does not register providers. Zava subscription administrators own registration.
$requiredProviders = @(
    'Microsoft.App',
    'Microsoft.CognitiveServices',
    'Microsoft.ContainerService',
    'Microsoft.DocumentDB',
    'Microsoft.KeyVault',
    'Microsoft.Network',
    'Microsoft.Search',
    'Microsoft.Storage'
)

$providerStates = foreach ($provider in $requiredProviders) {
    $state = az provider show --namespace $provider --query registrationState --output tsv
    if ($LASTEXITCODE -ne 0) { throw "Provider lookup failed: $provider" }
    [pscustomobject]@{ Provider = $provider; State = $state }
}
$providerStates | Format-Table -AutoSize

$missingProviders = @($providerStates | Where-Object State -ne 'Registered')
if ($missingProviders.Count -gt 0) {
    throw "Zava must register: $($missingProviders.Provider -join ', ')"
}

# %% CELL 5 — INSPECT THE EXISTING CUSTOMER VNET AND SUBNETS (read-only)
# Stop unless Zava confirms the address plan and the proposed ranges are unallocated.
Invoke-AzChecked @(
    'network','vnet','show',
    '--resource-group',$networkRg,
    '--name',$vnet,
    '--query','{name:name,location:location,addressSpace:addressSpace.addressPrefixes,state:provisioningState,dnsServers:dhcpOptions.dnsServers}',
    '--output','json'
)

Invoke-AzChecked @(
    'network','vnet','subnet','list',
    '--resource-group',$networkRg,
    '--vnet-name',$vnet,
    '--query','[].{name:name,prefix:addressPrefix,state:provisioningState,delegation:delegations[0].serviceName}',
    '--output','table'
)

Write-Host 'Expected occupied ranges:' -ForegroundColor Cyan
Write-Host '  dmzsubnet-1      10.75.139.128/29 (must be confirmed by Zava)'
Write-Host '  hybridsubnet-1   10.75.139.136/29'
Write-Host 'Proposed ranges:' -ForegroundColor Cyan
Write-Host "  $peSubnet   $peSubnetPrefix"
Write-Host "  $agentSubnet   $agentSubnetPrefix"

# %% CELL 6 — DISPLAY THE EXACT SUBNET BICEP (read-only)
Get-Content $subnetTemplate

# %% CELL 7 — COMPILE AND ARM-VALIDATE THE TWO NEW SUBNETS (read-only)
Build-Bicep $subnetTemplate
$subnetParameters = @(
    "vnetName=$vnet",
    "agentSubnetName=$agentSubnet",
    "agentSubnetPrefix=$agentSubnetPrefix",
    "privateEndpointSubnetName=$peSubnet",
    "privateEndpointSubnetPrefix=$peSubnetPrefix"
)
Invoke-AzChecked (@(
    'deployment','group','validate',
    '--resource-group',$networkRg,
    '--name','zava-01-foundry-subnets-validate',
    '--template-file',$subnetTemplate,
    '--parameters'
) + $subnetParameters + @('--output','none'))
Write-Host 'Subnet validation passed.' -ForegroundColor Green

# %% CELL 8 — WHAT-IF THE TWO NEW SUBNETS (read-only)
# Expected: exactly two Create operations and no modification/deletion of existing subnets.
Invoke-AzChecked (@(
    'deployment','group','what-if',
    '--resource-group',$networkRg,
    '--name','zava-01-foundry-subnets',
    '--template-file',$subnetTemplate,
    '--parameters'
) + $subnetParameters + @('--result-format','ResourceIdOnly'))

# %% CELL 9 — DEPLOY THE TWO NEW SUBNETS (changes Azure)
$approveSubnetDeployment = $false
Assert-Approval $approveSubnetDeployment 'Subnet deployment'
Invoke-AzChecked (@(
    'deployment','group','create',
    '--resource-group',$networkRg,
    '--name','zava-01-foundry-subnets',
    '--template-file',$subnetTemplate,
    '--parameters'
) + $subnetParameters + @('--output','none'))
Write-Host 'Subnet deployment completed.' -ForegroundColor Green

# %% CELL 10 — VERIFY ALL CUSTOMER AND FOUNDRY SUBNETS (read-only)
Invoke-AzChecked @(
    'network','vnet','subnet','list',
    '--resource-group',$networkRg,
    '--vnet-name',$vnet,
    '--query','[].{name:name,prefix:addressPrefix,delegation:delegations[0].serviceName,pePolicies:privateEndpointNetworkPolicies,state:provisioningState}',
    '--output','table'
)
$agentSubnetId = az network vnet subnet show `
    --resource-group $networkRg `
    --vnet-name $vnet `
    --name $agentSubnet `
    --query id `
    --output tsv
if ($LASTEXITCODE -ne 0 -or -not $agentSubnetId) { throw 'Agent subnet verification failed.' }
Write-Host "Agent subnet resource ID: $agentSubnetId"

# %% CELL 11 — VALIDATE THE SEVEN CUSTOMER-OWNED PRIVATE DNS ZONES (read-only)
# These normally live in a central connectivity subscription/resource group.
$zones = @(
    'privatelink.cognitiveservices.azure.com',
    'privatelink.openai.azure.com',
    'privatelink.services.ai.azure.com',
    'privatelink.blob.core.windows.net',
    'privatelink.vaultcore.azure.net',
    'privatelink.documents.azure.com',
    'privatelink.search.windows.net'
)
$zoneInventory = foreach ($zone in $zones) {
    $zoneId = az network private-dns zone show -g $dnsRg -n $zone --query id -o tsv 2>$null
    [pscustomobject]@{ Zone = $zone; Exists = ($LASTEXITCODE -eq 0 -and [bool]$zoneId); Id = $zoneId }
}
$zoneInventory | Format-Table -AutoSize
$missingZones = @($zoneInventory | Where-Object Exists -eq $false)
if ($missingZones.Count -gt 0) {
    throw "Missing customer DNS zones: $($missingZones.Zone -join ', ')"
}

# %% CELL 12 — DISPLAY AND VALIDATE DIRECT DNS LINKS (optional, read-only)
# Run Cells 12-14 only if Zava directly links private DNS zones to the spoke.
# Skip these cells if Zava uses a central hub resolver and does not use direct spoke links.
Get-Content $dnsLinkTemplate
Build-Bicep $dnsLinkTemplate
$dnsLinkParameters = @("networkResourceGroupName=$networkRg", "vnetName=$vnet")
Invoke-AzChecked (@(
    'deployment','group','validate',
    '--resource-group',$dnsRg,
    '--name','zava-02-private-dns-links-validate',
    '--template-file',$dnsLinkTemplate,
    '--parameters'
) + $dnsLinkParameters + @('--output','none'))

# %% CELL 13 — WHAT-IF DIRECT DNS LINKS (optional, read-only)
# Expected: seven VNet link creations; no DNS-zone modification/deletion.
Invoke-AzChecked (@(
    'deployment','group','what-if',
    '--resource-group',$dnsRg,
    '--name','zava-02-private-dns-links',
    '--template-file',$dnsLinkTemplate,
    '--parameters'
) + $dnsLinkParameters + @('--result-format','ResourceIdOnly'))

# %% CELL 14 — DEPLOY DIRECT DNS LINKS (optional, changes Azure)
$approveDirectDnsLinks = $false
Assert-Approval $approveDirectDnsLinks 'Direct DNS-link deployment'
Invoke-AzChecked (@(
    'deployment','group','create',
    '--resource-group',$dnsRg,
    '--name','zava-02-private-dns-links',
    '--template-file',$dnsLinkTemplate,
    '--parameters'
) + $dnsLinkParameters + @('--output','none'))
Write-Host 'Direct private DNS links completed.' -ForegroundColor Green

# %% CELL 15 — VERIFY DIRECT DNS LINKS (optional, read-only)
foreach ($zone in $zones) {
    Write-Host "--- $zone ---" -ForegroundColor Cyan
    Invoke-AzChecked @(
        'network','private-dns','link','vnet','list',
        '--resource-group',$dnsRg,
        '--zone-name',$zone,
        '--query',"[?contains(virtualNetwork.id, '/virtualNetworks/$vnet')].{name:name,state:virtualNetworkLinkState,vnet:virtualNetwork.id}",
        '--output','table'
    )
}

# %% CELL 16 — DISPLAY THE CHAPTER 01 FOUNDATION BICEP (read-only)
Get-Content $chapter01Template

# %% CELL 17 — COMPILE AND VALIDATE CHAPTER 01 (read-only)
Build-Bicep $chapter01Template
$chapter01Deployment = "zava-03-chapter-01-$environment"
$chapter01Parameters = @(
    "location=$location",
    "workloadName=$workload",
    "environment=$environment",
    "networkResourceGroupName=$networkRg",
    "vnetName=$vnet",
    "privateEndpointSubnetName=$peSubnet",
    "privateDnsResourceGroupName=$dnsRg",
    "createPrivateEndpointDnsZoneGroups=$($createPrivateEndpointDnsZoneGroups.ToString().ToLowerInvariant())",
    "foundryUserPrincipalId=$foundryUserObjectId"
)
Invoke-AzChecked (@(
    'deployment','group','validate',
    '--resource-group',$workloadRg,
    '--name',"$chapter01Deployment-validate",
    '--template-file',$chapter01Template,
    '--parameters'
) + $chapter01Parameters + @('--output','none'))
Write-Host 'Chapter 01 validation passed.' -ForegroundColor Green

# %% CELL 18 — WHAT-IF CHAPTER 01 (read-only)
# Stop if this modifies customer VNets, subnets, routes, NSGs, firewalls, zones, or links.
Invoke-AzChecked (@(
    'deployment','group','what-if',
    '--resource-group',$workloadRg,
    '--name',$chapter01Deployment,
    '--template-file',$chapter01Template,
    '--parameters'
) + $chapter01Parameters + @('--result-format','ResourceIdOnly'))

# %% CELL 19 — DEPLOY CHAPTER 01 (changes Azure)
$approveChapter01Deployment = $false
Assert-Approval $approveChapter01Deployment 'Chapter 01 deployment'
Invoke-AzChecked (@(
    'deployment','group','create',
    '--resource-group',$workloadRg,
    '--name',$chapter01Deployment,
    '--template-file',$chapter01Template,
    '--parameters'
) + $chapter01Parameters + @('--output','none'))
Write-Host 'Chapter 01 deployment completed.' -ForegroundColor Green

# %% CELL 20 — CAPTURE AND VERIFY CHAPTER 01 RESOURCES (read-only)
$chapter01Outputs = az deployment group show -g $workloadRg -n $chapter01Deployment `
    --query properties.outputs -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Chapter 01 output lookup failed.' }
$basicFoundry = $chapter01Outputs.foundryAccountName.value
$basicProject = $chapter01Outputs.foundryProjectName.value
$basicStorage = $chapter01Outputs.storageAccountName.value
$basicVault   = $chapter01Outputs.keyVaultName.value
if (-not $basicFoundry -or -not $basicProject -or -not $basicStorage -or -not $basicVault) {
    throw 'Chapter 01 outputs are incomplete.'
}

Invoke-AzChecked @('cognitiveservices','account','show','-g',$workloadRg,'-n',$basicFoundry,
    '--query','{name:name,state:properties.provisioningState,public:properties.publicNetworkAccess,localAuthDisabled:properties.disableLocalAuth,aclDefault:properties.networkAcls.defaultAction}','-o','table')
Invoke-AzChecked @('storage','account','show','-g',$workloadRg,'-n',$basicStorage,
    '--query','{name:name,state:provisioningState,public:publicNetworkAccess,sharedKey:allowSharedKeyAccess,blobPublic:allowBlobPublicAccess,tls:minimumTlsVersion}','-o','table')
Invoke-AzChecked @('keyvault','show','-g',$workloadRg,'-n',$basicVault,
    '--query','{name:name,public:properties.publicNetworkAccess,rbac:properties.enableRbacAuthorization,purgeProtection:properties.enablePurgeProtection}','-o','table')
Invoke-AzChecked @('network','private-endpoint','list','-g',$workloadRg,
    '--query',"[?contains(name, '$basicFoundry') || contains(name, '$basicStorage') || contains(name, '$basicVault')].{name:name,state:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status,subnet:subnet.id}",'-o','table')

# %% CELL 21 — DISPLAY THE CHAPTER 01A STANDARD CORE BICEP (read-only)
Get-Content $coreTemplate

# %% CELL 22 — COMPILE AND VALIDATE CHAPTER 01A CORE (read-only)
Build-Bicep $coreTemplate
$coreDeployment = "zava-04-chapter-01a-core-$environment"
$coreParameters = @(
    "location=$location",
    "searchLocation=$searchLocation",
    "workloadName=$workload",
    "environment=$environment",
    "networkResourceGroupName=$networkRg",
    "vnetName=$vnet",
    "agentSubnetName=$agentSubnet",
    "privateEndpointSubnetName=$peSubnet",
    "privateDnsResourceGroupName=$dnsRg",
    "createPrivateEndpointDnsZoneGroups=$($createPrivateEndpointDnsZoneGroups.ToString().ToLowerInvariant())",
    "foundryUserPrincipalId=$foundryUserObjectId"
)
Invoke-AzChecked (@(
    'deployment','group','validate',
    '--resource-group',$workloadRg,
    '--name',"$coreDeployment-validate",
    '--template-file',$coreTemplate,
    '--parameters'
) + $coreParameters + @('--output','none'))
Write-Host 'Chapter 01a core validation passed.' -ForegroundColor Green

# %% CELL 23 — WHAT-IF CHAPTER 01A CORE (read-only)
Invoke-AzChecked (@(
    'deployment','group','what-if',
    '--resource-group',$workloadRg,
    '--name',$coreDeployment,
    '--template-file',$coreTemplate,
    '--parameters'
) + $coreParameters + @('--result-format','ResourceIdOnly'))

# %% CELL 24 — DEPLOY CHAPTER 01A CORE (changes Azure)
$approveChapter01aCoreDeployment = $false
Assert-Approval $approveChapter01aCoreDeployment 'Chapter 01a core deployment'
Invoke-AzChecked (@(
    'deployment','group','create',
    '--resource-group',$workloadRg,
    '--name',$coreDeployment,
    '--template-file',$coreTemplate,
    '--parameters'
) + $coreParameters + @('--output','none'))
Write-Host 'Chapter 01a core deployment completed.' -ForegroundColor Green

# %% CELL 25 — CAPTURE CHAPTER 01A OUTPUTS AND VERIFY NETWORK INJECTION (read-only)
$coreOutputs = az deployment group show -g $workloadRg -n $coreDeployment `
    --query properties.outputs -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Chapter 01a output lookup failed.' }
$stdFoundry = $coreOutputs.foundryAccountName.value
$stdProject = $coreOutputs.foundryProjectName.value
$stdStorage = $coreOutputs.storageAccountName.value
$cosmos     = $coreOutputs.cosmosAccountName.value
$search     = $coreOutputs.searchServiceName.value
$projectMi  = $coreOutputs.projectPrincipalId.value
$stdId      = $coreOutputs.foundryAccountId.value
if (-not $stdFoundry -or -not $stdProject -or -not $stdStorage -or -not $cosmos -or -not $search -or -not $projectMi -or -not $stdId) {
    throw 'Chapter 01a outputs are incomplete.'
}

Invoke-AzChecked @('rest','--method','GET',
    '--url',"https://management.azure.com${stdId}?api-version=2025-06-01",
    '--query','properties.networkInjections','--output','json')

# %% CELL 26 — VERIFY CHAPTER 01A PRIVATE SERVICES AND ENDPOINTS (read-only)
Invoke-AzChecked @('cognitiveservices','account','show','-g',$workloadRg,'-n',$stdFoundry,
    '--query','{name:name,state:properties.provisioningState,public:properties.publicNetworkAccess,localAuthDisabled:properties.disableLocalAuth}','-o','table')
Invoke-AzChecked @('storage','account','show','-g',$workloadRg,'-n',$stdStorage,
    '--query','{name:name,state:provisioningState,public:publicNetworkAccess,sharedKey:allowSharedKeyAccess}','-o','table')
Invoke-AzChecked @('cosmosdb','show','-g',$workloadRg,'-n',$cosmos,
    '--query','{name:name,state:provisioningState,public:publicNetworkAccess,localAuthDisabled:disableLocalAuth}','-o','table')
Invoke-AzChecked @('search','service','show','-g',$workloadRg,'-n',$search,
    '--query','{name:name,state:status,public:publicNetworkAccess,localAuthDisabled:disableLocalAuth,sku:sku.name}','-o','table')
Invoke-AzChecked @('network','private-endpoint','list','-g',$workloadRg,
    '--query','[].{name:name,state:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status,subnet:subnet.id}','-o','table')

# %% CELL 27 — VERIFY PROJECT IDENTITY ROLES AND AAD CONNECTIONS (read-only)
Invoke-AzChecked @('role','assignment','list','--assignee',$projectMi,'--all',
    '--query','[].{role:roleDefinitionName,scope:scope}','-o','table')
Invoke-AzChecked @('cosmosdb','sql','role','assignment','list','-g',$workloadRg,'-a',$cosmos,
    '--query',"[?principalId=='$projectMi'].{principalId:principalId,roleDefinitionId:roleDefinitionId,scope:scope}",'-o','table')
Invoke-AzChecked @('rest','--method','GET',
    '--url',"https://management.azure.com${stdId}/projects/${stdProject}/connections?api-version=2025-06-01",
    '--query','value[].{name:name,category:properties.category,auth:properties.authType,target:properties.target}','-o','table')

# %% CELL 28 — MANDATORY PRIVATE DNS CHECKPOINT (run from a Zava-connected host)
# Stop if any lookup is public, times out, or resolves outside the PE subnet.
ipconfig /all
ipconfig /flushdns
$privateNames = @(
    "$stdFoundry.cognitiveservices.azure.com",
    "$stdFoundry.openai.azure.com",
    "$stdStorage.blob.core.windows.net",
    "$cosmos.documents.azure.com",
    "$search.search.windows.net"
)
foreach ($privateName in $privateNames) {
    Write-Host "`n--- $privateName ---" -ForegroundColor Cyan
    Resolve-DnsName $privateName -ErrorAction Stop |
        Format-Table Name,Type,IPAddress,NameHost -AutoSize
}

# %% CELL 29 — CHECK THAT CAPABILITY HOSTS DO NOT EXIST (read-only)
# Both lists must be empty before the initial deployment.
Invoke-AzChecked @('rest','--method','GET',
    '--url',"https://management.azure.com${stdId}/capabilityHosts?api-version=2025-06-01",
    '--query','value[].{name:name,state:properties.provisioningState}','-o','table')
Invoke-AzChecked @('rest','--method','GET',
    '--url',"https://management.azure.com${stdId}/projects/${stdProject}/capabilityHosts?api-version=2025-06-01",
    '--query','value[].{name:name,state:properties.provisioningState}','-o','table')

# %% CELL 30 — DISPLAY, COMPILE, AND VALIDATE CAPABILITY HOSTS (read-only)
Get-Content $hostTemplate
Build-Bicep $hostTemplate
$hostDeployment = "zava-05-capability-hosts-$environment"
$hostParameters = @(
    "workloadName=$workload",
    "environment=$environment",
    "networkResourceGroupName=$networkRg",
    "vnetName=$vnet",
    "agentSubnetName=$agentSubnet"
)
Invoke-AzChecked (@(
    'deployment','group','validate','-g',$workloadRg,
    '-n',"$hostDeployment-validate",'-f',$hostTemplate,'-p'
) + $hostParameters + @('-o','none'))

# %% CELL 31 — WHAT-IF THE TWO CAPABILITY HOSTS (read-only)
# Expected: exactly one account host and one project host.
Invoke-AzChecked (@(
    'deployment','group','what-if','-g',$workloadRg,
    '-n',$hostDeployment,'-f',$hostTemplate,'-p'
) + $hostParameters + @('--result-format','ResourceIdOnly'))

# %% CELL 32 — DEPLOY CAPABILITY HOSTS ONCE (changes Azure; never blindly rerun)
$approveOneTimeCapabilityHosts = $false
Assert-Approval $approveOneTimeCapabilityHosts 'One-time capability-host deployment'
Invoke-AzChecked (@(
    'deployment','group','create','-g',$workloadRg,
    '-n',$hostDeployment,'-f',$hostTemplate,'-p'
) + $hostParameters + @('-o','none'))
Write-Host 'Capability-host deployment submitted.' -ForegroundColor Green

# %% CELL 33 — VERIFY BOTH CAPABILITY HOSTS (read-only)
Invoke-AzChecked @('rest','--method','GET',
    '--url',"https://management.azure.com${stdId}/capabilityHosts?api-version=2025-06-01",
    '--query','value[].{name:name,state:properties.provisioningState,subnet:properties.customerSubnet}','-o','table')
Invoke-AzChecked @('rest','--method','GET',
    '--url',"https://management.azure.com${stdId}/projects/${stdProject}/capabilityHosts?api-version=2025-06-01",
    '--query','value[].{name:name,state:properties.provisioningState,storage:properties.storageConnections,threads:properties.threadStorageConnections,vectors:properties.vectorStoreConnections}','-o','json')

# %% CELL 34 — RECOVER ONLY A MISSING CAPABILITY HOST (safe preview by default)
# The helper refuses to overwrite an existing host. Leave execute false for preview.
$executeCapabilityHostRecovery = $false
$recoveryArguments = @{
    Subscription              = $subscription
    TenantId                  = $tenantId
    WorkloadResourceGroupName = $workloadRg
    FoundryAccountName        = $stdFoundry
    FoundryProjectName        = $stdProject
    AgentSubnetResourceId     = $agentSubnetId
}
if ($executeCapabilityHostRecovery) {
    & $recoveryScript @recoveryArguments -Confirm
} else {
    & $recoveryScript @recoveryArguments -WhatIf
}

# %% CELL 35 — CONFIGURE AND REVIEW THE APPROVED MODEL (read-only)
$modelDeployment = '<approved-deployment-name>'
$modelName       = '<approved-model-name>'
$modelVersion    = '<approved-model-version>'
$modelCapacity   = 0 # Replace with the approved positive capacity.

Assert-Configured 'modelDeployment' $modelDeployment
Assert-Configured 'modelName' $modelName
Assert-Configured 'modelVersion' $modelVersion
if ($modelCapacity -lt 1) { throw 'Set $modelCapacity to the approved positive capacity.' }

[pscustomobject]@{
    Account        = $stdFoundry
    DeploymentName = $modelDeployment
    Model          = $modelName
    Version        = $modelVersion
    SKU            = 'GlobalStandard'
    Capacity       = $modelCapacity
} | Format-List

# %% CELL 36 — DEPLOY THE APPROVED MODEL (changes Azure)
$approveModelDeployment = $false
Assert-Approval $approveModelDeployment 'Model deployment'
Invoke-AzChecked @(
    'cognitiveservices','account','deployment','create',
    '--resource-group',$workloadRg,
    '--name',$stdFoundry,
    '--deployment-name',$modelDeployment,
    '--model-name',$modelName,
    '--model-version',$modelVersion,
    '--model-format','OpenAI',
    '--sku-name','GlobalStandard',
    '--sku-capacity',"$modelCapacity",
    '--output','none'
)
Write-Host 'Model deployment completed.' -ForegroundColor Green

# %% CELL 37 — VERIFY MODEL AND FINAL RESOURCE INVENTORY (read-only)
Invoke-AzChecked @(
    'cognitiveservices','account','deployment','list',
    '-g',$workloadRg,'-n',$stdFoundry,
    '--query','[].{name:name,model:properties.model.name,version:properties.model.version,state:properties.provisioningState,sku:sku.name,capacity:sku.capacity}',
    '-o','table'
)
Invoke-AzChecked @(
    'resource','list','-g',$workloadRg,
    '--query','sort_by([].{name:name,type:type,location:location}, &type)',
    '-o','table'
)

# %% [markdown] CELL 38 — FINAL MANUAL ACCEPTANCE
# From a Zava-connected administrative host:
# 1. Open the Standard Foundry project (not the Chapter 01 basic project).
# 2. Confirm the Agents page loads through private connectivity.
# 3. Create a temporary prompt agent using the approved model.
# 4. Start a thread and send a basic prompt.
# 5. Confirm Storage, Cosmos DB, Search, and model access succeed.
# 6. Remove the temporary agent after acceptance.
#
# Do not create production agents until network injection, DNS, capability hosts,
# managed-identity roles, and customer-owned state are all verified.
