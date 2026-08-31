[CmdletBinding()]
param(
    # Override these placeholders with the customer subscription and tenant.
    [string] $SubscriptionName = '<subscription-name>',
    [string] $Tenant = '<tenant-domain>',

    # Chapter 02 deploys into the same resource group and reuses Chapter 01's VNet.
    [string] $ResourceGroupName = 'rg-agentic-ai-blueprint-dev',
    [string] $Location = 'eastus2',
    [string] $WorkloadName = 'agent-blueprint',
    [ValidateSet('dev', 'test', 'prod')]
    [string] $Environment = 'dev',

    [string] $ExistingVnetName = 'agent-blueprint-dev-vnet',
    [string] $ApimSubnetPrefix = '192.168.2.0/24',

    # The Foundry account created in Chapter 01 is reused as the private model backend.
    [string] $FoundryAccountName = '',

    [string] $PublisherName = 'Enterprise AI Platform',
    [string] $PublisherEmail = 'ai-platform@example.com',
    [ValidateSet('Developer', 'Premiumv2')]
    [string] $ApimSkuName = 'Developer',
    [ValidateRange(1, 12)]
    [int] $ApimCapacity = 1,

    # Without -Execute, the script validates and previews changes but deploys nothing.
    [switch] $Execute,

    # Starts Azure device-code login when the CLI is not already signed in.
    [switch] $Login
)

$ErrorActionPreference = 'Stop'
$templateFile = Join-Path $PSScriptRoot 'main.bicep'

# Locate Azure CLI in PATH first, then fall back to the standard 64-bit install path.
$azCommand = Get-Command az -ErrorAction SilentlyContinue
if ($azCommand) {
    $az = $azCommand.Source
}
else {
    $az = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
}

if (-not (Test-Path $az)) {
    throw 'Azure CLI was not found. Install it with: winget install --exact --id Microsoft.AzureCLI'
}

function Invoke-AzureCli {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    Write-Verbose ("az " + ($Arguments -join ' '))
    # az writes progress/warnings to stderr; relax Stop preference so those are not treated as fatal.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $az @Arguments 2>&1 | ForEach-Object { "$_" }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) {
        throw "Azure CLI failed with exit code $exitCode."
    }
}

# Explicit sign-in check so resources cannot land in a cached personal tenant.
& $az account show --only-show-errors --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    if (-not $Login) {
        throw "Azure CLI is not signed in. Run 'az login --tenant $Tenant --use-device-code', then rerun this script."
    }

    Invoke-AzureCli -Arguments @('login', '--tenant', $Tenant, '--use-device-code', '--output', 'none')
}

# Select by subscription display name, then prove subscription and tenant before any write.
Invoke-AzureCli -Arguments @('account', 'set', '--subscription', $SubscriptionName)
$account = (& $az account show --output json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read the selected Azure account.'
}

$signedInUser = $account.user.name
if ($account.name -ne $SubscriptionName) {
    throw "Safety check failed. Selected subscription is '$($account.name)', expected '$SubscriptionName'."
}
if ([string]::IsNullOrWhiteSpace($signedInUser) -or -not $signedInUser.ToLowerInvariant().EndsWith('@' + $Tenant.ToLowerInvariant())) {
    throw "Safety check failed. Signed-in user '$signedInUser' is not in tenant '$Tenant'."
}

# Resolve the Foundry account name if not supplied: pick the single AIServices account in the RG.
if ([string]::IsNullOrWhiteSpace($FoundryAccountName)) {
    $FoundryAccountName = (& $az cognitiveservices account list --resource-group $ResourceGroupName --query "[?kind=='AIServices'].name | [0]" --output tsv)
    if ([string]::IsNullOrWhiteSpace($FoundryAccountName)) {
        throw 'Could not find an AIServices (Foundry) account. Pass -FoundryAccountName explicitly.'
    }
}

Write-Host "Target subscription: $($account.name) ($($account.id))"
Write-Host "Target tenant:       $Tenant ($($account.tenantId))"
Write-Host "Signed-in user:      $signedInUser"
Write-Host "Resource group:      $ResourceGroupName"
Write-Host "Azure region:        $Location"
Write-Host "Reusing VNet:        $ExistingVnetName"
Write-Host "Model backend:       $FoundryAccountName"

# Providers needed by Chapter 02 on top of those registered in Chapter 01.
$requiredProviders = @(
    'Microsoft.ApiManagement',
    'Microsoft.Insights',
    'Microsoft.OperationalInsights'
)

foreach ($provider in $requiredProviders) {
    Write-Host "Requesting registration for resource provider: $provider"
    Invoke-AzureCli -Arguments @('provider', 'register', '--namespace', $provider, '--output', 'none')
}

$registrationTimeout = [TimeSpan]::FromMinutes(15)
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
do {
    $states = foreach ($provider in $requiredProviders) {
        $state = (& $az provider show --namespace $provider --query 'registrationState' --output tsv)
        [pscustomobject]@{ Provider = $provider; State = $state }
    }

    $pending = @($states | Where-Object { $_.State -ne 'Registered' })
    if ($pending.Count -gt 0) {
        Write-Host ("Waiting on provider registration ({0}): {1}" -f $stopwatch.Elapsed.ToString('mm\:ss'), (($pending | ForEach-Object { $_.Provider }) -join ', '))
        Start-Sleep -Seconds 15
    }
} while ($pending.Count -gt 0 -and $stopwatch.Elapsed -lt $registrationTimeout)

if ($pending.Count -gt 0) {
    throw ("Provider registration did not complete within {0} minutes: {1}" -f $registrationTimeout.TotalMinutes, (($pending | ForEach-Object { $_.Provider }) -join ', '))
}
Write-Host 'All required resource providers are registered.'

$deploymentName = "chapter-02-$Environment"
$deploymentArguments = @(
    '--resource-group', $ResourceGroupName,
    '--name', $deploymentName,
    '--template-file', $templateFile,
    '--parameters',
    "location=$Location",
    "workloadName=$WorkloadName",
    "environment=$Environment",
    "existingVnetName=$ExistingVnetName",
    "apimSubnetPrefix=$ApimSubnetPrefix",
    "foundryAccountName=$FoundryAccountName",
    "publisherName=$PublisherName",
    "publisherEmail=$PublisherEmail",
    "apimSkuName=$ApimSkuName",
    "apimCapacity=$ApimCapacity"
)

Write-Host 'Validating the Chapter 02 deployment...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'validate') + $deploymentArguments + @('--output', 'none'))

Write-Host 'Previewing Azure changes with what-if...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'what-if') + $deploymentArguments + @('--result-format', 'FullResourcePayloads'))

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Preview complete. Rerun with -Execute to deploy the resources shown above.'
    Write-Host "NOTE: APIM ($ApimSkuName) creation takes ~30-45 minutes."
    exit 0
}

Write-Host "Deploying Chapter 02 (APIM $ApimSkuName with VNet injection). This takes ~30-45 minutes..."
Invoke-AzureCli -Arguments (@('deployment', 'group', 'create') + $deploymentArguments + @('--output', 'none'))

# Read APIM name and private IP to publish the internal gateway DNS records.
$apimName = (& $az deployment group show --resource-group $ResourceGroupName --name $deploymentName --query 'properties.outputs.apimName.value' --output tsv)
if ([string]::IsNullOrWhiteSpace($apimName)) {
    throw 'Could not read the APIM name from deployment outputs.'
}

$apimPrivateIp = (& $az apim show --resource-group $ResourceGroupName --name $apimName --query 'privateIpAddresses[0]' --output tsv)
if ([string]::IsNullOrWhiteSpace($apimPrivateIp)) {
    throw 'Could not read the APIM private IP address.'
}
Write-Host "APIM private IP: $apimPrivateIp"

# Internal APIM exposes several hostnames; point each relative record at the private IP.
$recordNames = @($apimName, "$apimName.developer", "$apimName.management", "$apimName.portal", "$apimName.scm")
foreach ($record in $recordNames) {
    Write-Host "Creating A record: $record.azure-api.net -> $apimPrivateIp"
    Invoke-AzureCli -Arguments @('network', 'private-dns', 'record-set', 'a', 'create', '--resource-group', $ResourceGroupName, '--zone-name', 'azure-api.net', '--name', $record, '--output', 'none')
    Invoke-AzureCli -Arguments @('network', 'private-dns', 'record-set', 'a', 'add-record', '--resource-group', $ResourceGroupName, '--zone-name', 'azure-api.net', '--record-set-name', $record, '--ipv4-address', $apimPrivateIp, '--output', 'none')
}

Write-Host ''
Write-Host 'Chapter 02 gateway deployment completed.'
Write-Host "Gateway (private): https://$apimName.azure-api.net"
Write-Host 'Portal-only steps remain: import the Foundry API, build the unified model API, and export APIs as MCP servers.'
