[CmdletBinding()]
param(
    # These defaults target the subscription and tenant requested for this demo.
    [string] $SubscriptionName = 'ME-MngEnvMCAP152025-snair-1',
    [string] $Tenant = 'MngEnvMCAP152025.onmicrosoft.com',

    # A dedicated resource group keeps Chapter 01 isolated and easy to remove later.
    [string] $ResourceGroupName = 'rg-agentic-ai-blueprint-dev',
    [string] $Location = 'eastus2',
    [string] $WorkloadName = 'agent-blueprint',
    [ValidateSet('dev', 'test', 'prod')]
    [string] $Environment = 'dev',

    # Model deployment consumes quota. Use -DeployModel:$false if quota is unavailable.
    [bool] $DeployModel = $true,
    [string] $ModelDeploymentName = 'gpt-4o',
    [string] $ModelVersion = '2024-11-20',
    [ValidateRange(1, 1000)]
    [int] $ModelCapacity = 30,

    # Object ID granted the Foundry User role so it can build agents. Defaults to the signed-in user.
    [string] $FoundryUserObjectId = '',

    # Without -Execute, the script validates and previews changes but does not deploy resources.
    [switch] $Execute,

    # Login is normally performed separately. This switch starts Azure device-code login when needed.
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

# Authentication is deliberately explicit so resources cannot land in a cached personal tenant.
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

# Verify the signed-in user belongs to the requested tenant domain. This uses only
# built-in commands and avoids the interactive 'account' preview extension prompt.
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

# Resolve the principal to grant the Foundry User role. Default to the signed-in user's object ID.
if ([string]::IsNullOrWhiteSpace($FoundryUserObjectId)) {
    $FoundryUserObjectId = (& $az ad signed-in-user show --query id --output tsv)
    if ([string]::IsNullOrWhiteSpace($FoundryUserObjectId)) {
        throw 'Could not resolve the signed-in user object ID. Pass -FoundryUserObjectId explicitly.'
    }
}
Write-Host "Foundry User grant:  $FoundryUserObjectId"

# Foundry private networking depends on these resource providers. Registration is idempotent.
# Create the dedicated resource group first so progress is visible immediately in the portal.
Write-Host 'Creating or updating the dedicated resource group...'
Invoke-AzureCli -Arguments @(
    'group', 'create',
    '--name', $ResourceGroupName,
    '--location', $Location,
    '--tags', 'workload=agentic-ai-enterprise-blueprint', 'chapter=01', "environment=$Environment",
    '--output', 'none'
)
Write-Host "Resource group '$ResourceGroupName' is ready."

# Foundry private networking depends on these resource providers.
$requiredProviders = @(
    'Microsoft.App',
    'Microsoft.CognitiveServices',
    'Microsoft.ContainerService',
    'Microsoft.KeyVault',
    'Microsoft.Network',
    'Microsoft.Storage'
)

# Fire registration without --wait so the slow Microsoft.App provider does not block the run.
foreach ($provider in $requiredProviders) {
    Write-Host "Requesting registration for resource provider: $provider"
    Invoke-AzureCli -Arguments @('provider', 'register', '--namespace', $provider, '--output', 'none')
}

# Poll until every provider is Registered, printing progress so the run never looks stuck.
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

# The model deployment is created separately (below) rather than in-template. Deploying a
# Cognitive Services account and its model deployment in the same template races: each run
# re-submits the account, briefly returning it to the 'Accepted' state, which fails the
# child model deployment. The chapter itself creates the model with a dedicated CLI call.
$deploymentName = "chapter-01-$Environment"
$deploymentArguments = @(
    '--resource-group', $ResourceGroupName,
    '--name', $deploymentName,
    '--template-file', $templateFile,
    '--parameters',
    "location=$Location",
    "workloadName=$WorkloadName",
    "environment=$Environment",
    'deployModel=false',
    "foundryUserPrincipalId=$FoundryUserObjectId",
    'foundryUserPrincipalType=User'
)

# Validation catches policy, schema, and permission issues without deploying template resources.
Write-Host 'Validating the Chapter 01 deployment...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'validate') + $deploymentArguments + @('--output', 'none'))

# What-if prints the exact create/modify/delete plan. No deletes are expected for a new group.
Write-Host 'Previewing Azure changes with what-if...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'what-if') + $deploymentArguments + @('--result-format', 'FullResourcePayloads'))

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Preview complete. Rerun with -Execute to deploy the resources shown above.'
    exit 0
}

Write-Host 'Deploying Chapter 01 infrastructure (account, project, network, private endpoints)...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'create') + $deploymentArguments + @('--output', 'none'))

# Read the generated Foundry account name from deployment outputs for the model step.
$foundryAccountName = (& $az deployment group show --resource-group $ResourceGroupName --name $deploymentName --query 'properties.outputs.foundryAccountName.value' --output tsv)
if ([string]::IsNullOrWhiteSpace($foundryAccountName)) {
    throw 'Could not read the Foundry account name from deployment outputs.'
}

if ($DeployModel) {
    # Wait until the account is fully provisioned so the model deployment does not race it.
    Write-Host 'Waiting for the Foundry account to reach Succeeded state...'
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

    # Idempotent: creating an existing deployment with the same values is a no-op update.
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

# Control-plane checks verify the chapter's critical security posture after deployment.
Write-Host 'Verifying delegated subnet configuration...'
Invoke-AzureCli -Arguments @(
    'network', 'vnet', 'subnet', 'show',
    '--resource-group', $ResourceGroupName,
    '--vnet-name', "$WorkloadName-$Environment-vnet",
    '--name', 'snet-foundry',
    '--query', '{addressPrefix:addressPrefix,delegations:delegations[].serviceName}',
    '--output', 'table'
)

Write-Host 'Verifying public access and private endpoint connections...'
Invoke-AzureCli -Arguments @(
    'resource', 'list',
    '--resource-group', $ResourceGroupName,
    '--query', '[].{Name:name,Type:type,Location:location}',
    '--output', 'table'
)

Write-Host ''
Write-Host 'Chapter 01 infrastructure deployment completed.'
Write-Host 'Important: configure Foundry Agent Service virtual network injection with snet-foundry before creating agents.'
