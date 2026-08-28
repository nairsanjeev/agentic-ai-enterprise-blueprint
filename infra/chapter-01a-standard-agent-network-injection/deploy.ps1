[CmdletBinding()]
param(
    # These defaults target the subscription and tenant used throughout the blueprint.
    [string] $SubscriptionName = 'ME-MngEnvMCAP152025-snair-1',
    [string] $Tenant = 'MngEnvMCAP152025.onmicrosoft.com',

    [string] $ResourceGroupName = 'rg-agentic-ai-blueprint-dev',
    [string] $Location = 'eastus2',
    [string] $WorkloadName = 'agent-blueprint',
    [ValidateSet('dev', 'test', 'prod')]
    [string] $Environment = 'dev',

    # The existing Chapter 01 network this Standard account reuses.
    [string] $ExistingVnetName = 'agent-blueprint-dev-vnet',
    [string] $AgentSubnetName = 'snet-foundry',
    [string] $PrivateEndpointSubnetName = 'snet-privateendpoints',

    # Model deployment consumes quota. Use -DeployModel:$false if quota is unavailable.
    [bool] $DeployModel = $true,
    [string] $ModelDeploymentName = 'gpt-4o',
    [string] $ModelVersion = '2024-11-20',
    [ValidateRange(1, 1000)]
    [int] $ModelCapacity = 30,

    # Object ID granted the Foundry User role. Defaults to the signed-in user.
    [string] $FoundryUserObjectId = '',

    # Without -Execute, the script validates and previews changes but does not deploy.
    [switch] $Execute,

    # Login is normally performed separately. This switch starts device-code login when needed.
    [switch] $Login
)

$ErrorActionPreference = 'Stop'
$templateFile = Join-Path $PSScriptRoot 'main.bicep'

# Locate Azure CLI in PATH first, then use the standard 64-bit Windows installation path.
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

# Authentication is deliberately explicit so resources cannot land in a cached personal tenant.
& $az account show --only-show-errors --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    if (-not $Login) {
        throw "Azure CLI is not signed in. Run 'az login --tenant $Tenant --use-device-code', then rerun this script."
    }
    Invoke-AzureCli -Arguments @('login', '--tenant', $Tenant, '--use-device-code', '--output', 'none')
}

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

Write-Host "Target subscription: $($account.name) ($($account.id))"
Write-Host "Target tenant:       $Tenant ($($account.tenantId))"
Write-Host "Signed-in user:      $signedInUser"
Write-Host "Resource group:      $ResourceGroupName"
Write-Host "Azure region:        $Location"

# Confirm the reused network exists before we try to build on it.
& $az network vnet show --resource-group $ResourceGroupName --name $ExistingVnetName --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "VNet '$ExistingVnetName' was not found in '$ResourceGroupName'. Deploy Chapter 01 first."
}

if ([string]::IsNullOrWhiteSpace($FoundryUserObjectId)) {
    $FoundryUserObjectId = (& $az ad signed-in-user show --query id --output tsv)
    if ([string]::IsNullOrWhiteSpace($FoundryUserObjectId)) {
        throw 'Could not resolve the signed-in user object ID. Pass -FoundryUserObjectId explicitly.'
    }
}
Write-Host "Foundry User grant:  $FoundryUserObjectId"

# Standard Agent Setup adds Cosmos DB and AI Search to the Chapter 01 provider set.
$requiredProviders = @(
    'Microsoft.App',
    'Microsoft.CognitiveServices',
    'Microsoft.DocumentDB',
    'Microsoft.KeyVault',
    'Microsoft.Network',
    'Microsoft.Search',
    'Microsoft.Storage'
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

# The model deployment is created after the account is Succeeded to avoid the account/deployment race.
$deploymentName = "chapter-01a-$Environment"
$deploymentArguments = @(
    '--resource-group', $ResourceGroupName,
    '--name', $deploymentName,
    '--template-file', $templateFile,
    '--parameters',
    "location=$Location",
    "workloadName=$WorkloadName",
    "environment=$Environment",
    "existingVnetName=$ExistingVnetName",
    "agentSubnetName=$AgentSubnetName",
    "privateEndpointSubnetName=$PrivateEndpointSubnetName",
    'deployModel=false',
    "foundryUserPrincipalId=$FoundryUserObjectId",
    'foundryUserPrincipalType=User'
)

Write-Host 'Validating the Chapter 01a Standard Agent deployment...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'validate') + $deploymentArguments + @('--output', 'none'))

Write-Host 'Previewing Azure changes with what-if...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'what-if') + $deploymentArguments + @('--result-format', 'FullResourcePayloads'))

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Preview complete. Rerun with -Execute to deploy the resources shown above.'
    exit 0
}

Write-Host 'Deploying Chapter 01a (Standard account, Cosmos, Search, Storage, PEs, capability hosts, network injection)...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'create') + $deploymentArguments + @('--output', 'none'))

$foundryAccountName = (& $az deployment group show --resource-group $ResourceGroupName --name $deploymentName --query 'properties.outputs.foundryAccountName.value' --output tsv)
if ([string]::IsNullOrWhiteSpace($foundryAccountName)) {
    throw 'Could not read the Foundry account name from deployment outputs.'
}
$foundryProjectName = (& $az deployment group show --resource-group $ResourceGroupName --name $deploymentName --query 'properties.outputs.foundryProjectName.value' --output tsv)

if ($DeployModel) {
    Write-Host 'Waiting for the Standard Foundry account to reach Succeeded state...'
    $accountTimeout = [TimeSpan]::FromMinutes(10)
    $accountStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        $accountState = (& $az cognitiveservices account show --resource-group $ResourceGroupName --name $foundryAccountName --query 'properties.provisioningState' --output tsv)
        if ($accountState -ne 'Succeeded') {
            Write-Host ("  account state: {0} ({1})" -f $accountState, $accountStopwatch.Elapsed.ToString('mm\:ss'))
            Start-Sleep -Seconds 10
        }
    } while ($accountState -ne 'Succeeded' -and $accountStopwatch.Elapsed -lt $accountTimeout)

    if ($accountState -ne 'Succeeded') {
        throw "Foundry account did not reach Succeeded state (last: $accountState)."
    }

    Write-Host "Deploying model '$ModelDeploymentName' (gpt-4o $ModelVersion, capacity $ModelCapacity)..."
    Invoke-AzureCli -Arguments @(
        'cognitiveservices', 'account', 'deployment', 'create',
        '--resource-group', $ResourceGroupName,
        '--name', $foundryAccountName,
        '--deployment-name', $ModelDeploymentName,
        '--model-name', 'gpt-4o',
        '--model-version', $ModelVersion,
        '--model-format', 'OpenAI',
        '--sku-name', 'GlobalStandard',
        '--sku-capacity', "$ModelCapacity",
        '--output', 'none'
    )
    Write-Host "Model '$ModelDeploymentName' deployed."
}
else {
    Write-Host 'Skipping model deployment (-DeployModel:$false).'
}

Write-Host ''
Write-Host 'Chapter 01a Standard Agent infrastructure deployment completed.'
Write-Host "Standard Foundry account: $foundryAccountName"
Write-Host "Standard Foundry project: $foundryProjectName"
Write-Host ''
Write-Host 'Network injection is active on this account. Next:'
Write-Host '  1. Rebuild your agent(s) on the Standard project above.'
Write-Host '  2. Recreate tool connections (MCP/A2A) using the Entra Application ID URI as the audience.'
Write-Host '  3. Validate with TEST.md — agent tool-call egress now flows through snet-foundry.'
