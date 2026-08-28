[CmdletBinding()]
param(
    [string] $SubscriptionName = 'ME-MngEnvMCAP152025-snair-1',
    [string] $Tenant = 'MngEnvMCAP152025.onmicrosoft.com',

    [string] $ResourceGroupName = 'rg-agentic-ai-blueprint-dev',
    [string] $ApimName = 'apim-agent-blueprint-dev-a5jiq4re',
    [string] $AppInsightsName = 'agent-blueprint-dev-gateway-appi',
    [string] $FoundryAccountName = 'agent-blueprint-dev-foundry-std-vlpnxwtn',

    # Point the existing Application Insights at the new dedicated workspace so all
    # agent telemetry lands next to the gateway logs. Off by default (touches an existing resource).
    [switch] $MigrateAppInsights,

    # Apply the agent-guardrail-v1 RAI policy to a deployment. Off by default (redeploys the model deployment).
    [string] $ApplyGuardrailToDeployment = '',

    [switch] $Execute,
    [switch] $Login
)

$ErrorActionPreference = 'Stop'
$templateFile = Join-Path $PSScriptRoot 'main.bicep'

$azCommand = Get-Command az -ErrorAction SilentlyContinue
$az = if ($azCommand) { $azCommand.Source } else { 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd' }
if (-not (Test-Path $az)) {
    throw 'Azure CLI was not found. Install it with: winget install --exact --id Microsoft.AzureCLI'
}

function Invoke-AzureCli {
    param([Parameter(Mandatory)][string[]] $Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $az @Arguments 2>&1 | ForEach-Object { "$_" }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) { throw "Azure CLI failed with exit code $exitCode." }
}

& $az account show --only-show-errors --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    if (-not $Login) { throw "Azure CLI is not signed in. Run 'az login --tenant $Tenant --use-device-code', then rerun." }
    Invoke-AzureCli -Arguments @('login', '--tenant', $Tenant, '--use-device-code', '--output', 'none')
}

Invoke-AzureCli -Arguments @('account', 'set', '--subscription', $SubscriptionName)
$account = (& $az account show --output json | ConvertFrom-Json)
if ($account.name -ne $SubscriptionName) { throw "Safety check failed. Selected subscription is '$($account.name)', expected '$SubscriptionName'." }
$signedInUser = $account.user.name
if ([string]::IsNullOrWhiteSpace($signedInUser) -or -not $signedInUser.ToLowerInvariant().EndsWith('@' + $Tenant.ToLowerInvariant())) {
    throw "Safety check failed. Signed-in user '$signedInUser' is not in tenant '$Tenant'."
}

# Confirm the resources this chapter depends on exist.
& $az apim show -g $ResourceGroupName -n $ApimName --output none 2>$null
if ($LASTEXITCODE -ne 0) { throw "APIM '$ApimName' not found. Deploy Chapter 02 first." }
& $az resource show -g $ResourceGroupName -n $AppInsightsName --resource-type Microsoft.Insights/components --output none 2>$null
if ($LASTEXITCODE -ne 0) { throw "Application Insights '$AppInsightsName' not found. Deploy Chapter 02 first." }

$deploymentName = 'chapter-15-dev'
$deploymentArguments = @(
    '--resource-group', $ResourceGroupName,
    '--name', $deploymentName,
    '--template-file', $templateFile,
    '--parameters',
    "apimName=$ApimName",
    "appInsightsName=$AppInsightsName",
    "foundryAccountName=$FoundryAccountName"
)

Write-Host 'Validating the Chapter 15 deployment...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'validate') + $deploymentArguments + @('--output', 'none'))

Write-Host 'Previewing Azure changes with what-if...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'what-if') + $deploymentArguments)

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Preview only. Re-run with -Execute to apply.' -ForegroundColor Yellow
    return
}

Write-Host 'Deploying Chapter 15 observability resources...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'create') + $deploymentArguments + @('--output', 'none'))

$workspaceId = (& $az deployment group show -g $ResourceGroupName -n $deploymentName --query 'properties.outputs.workspaceId.value' -o tsv)
Write-Host "Log Analytics workspace: $workspaceId"

if ($MigrateAppInsights) {
    Write-Host 'Migrating Application Insights to the dedicated workspace...'
    Invoke-AzureCli -Arguments @('monitor', 'app-insights', 'component', 'update', '-g', $ResourceGroupName, '-a', $AppInsightsName, '--workspace', $workspaceId, '--output', 'none')
    Write-Host 'Application Insights now writes to the dedicated workspace.' -ForegroundColor Green
}

if (-not [string]::IsNullOrWhiteSpace($ApplyGuardrailToDeployment)) {
    Write-Host "Applying agent-guardrail-v1 to deployment '$ApplyGuardrailToDeployment'..."
    Invoke-AzureCli -Arguments @('cognitiveservices', 'account', 'deployment', 'update', '-g', $ResourceGroupName, '-n', $FoundryAccountName, '--deployment-name', $ApplyGuardrailToDeployment, '--rai-policy-name', 'agent-guardrail-v1', '--output', 'none')
    Write-Host "Guardrail policy applied to '$ApplyGuardrailToDeployment'." -ForegroundColor Green
}

Write-Host 'Chapter 15 deployment complete.' -ForegroundColor Green
