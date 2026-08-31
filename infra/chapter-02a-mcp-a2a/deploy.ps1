[CmdletBinding()]
param(
    [string] $SubscriptionName = '<subscription-name>',
    [string] $Tenant = '<tenant-domain>',
    [string] $ResourceGroupName = 'rg-agentic-ai-blueprint-dev',
    [string] $ApimName = 'apim-agent-blueprint-dev-a5jiq4re',
    [ValidateSet('dev', 'test', 'prod')]
    [string] $Environment = 'dev',
    [ValidateRange(1, 1000)]
    [int] $CallsPerMinute = 30,
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

    & $az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed with exit code $LASTEXITCODE."
    }
}

& $az account show --only-show-errors --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    if (-not $Login) {
        throw "Azure CLI is not signed in. Run 'az login --tenant $Tenant --use-device-code', then rerun this script."
    }
    Invoke-AzureCli @('login', '--tenant', $Tenant, '--use-device-code', '--output', 'none')
}

Invoke-AzureCli @('account', 'set', '--subscription', $SubscriptionName)
$account = (& $az account show --output json | ConvertFrom-Json)
if ($account.name -ne $SubscriptionName -or $account.user.name -notlike "*@$Tenant") {
    throw "Safety check failed for subscription '$($account.name)' or signed-in user '$($account.user.name)'."
}

& $az apim show --resource-group $ResourceGroupName --name $ApimName --only-show-errors --output none
if ($LASTEXITCODE -ne 0) {
    throw "APIM '$ApimName' was not found in resource group '$ResourceGroupName'. Complete Chapter 02 first."
}

$deploymentName = "chapter-02a-$Environment"
$deploymentArguments = @(
    '--resource-group', $ResourceGroupName,
    '--name', $deploymentName,
    '--template-file', $templateFile,
    '--parameters', "apimName=$ApimName", "callsPerMinute=$CallsPerMinute"
)

Write-Host 'Validating Chapter 02a...'
Invoke-AzureCli (@('deployment', 'group', 'validate') + $deploymentArguments + @('--output', 'none'))
Write-Host 'Previewing Chapter 02a changes...'
Invoke-AzureCli (@('deployment', 'group', 'what-if') + $deploymentArguments + @('--result-format', 'ResourceIdOnly'))

if (-not $Execute) {
    Write-Host 'Preview complete. Rerun with -Execute to deploy.'
    exit 0
}

Write-Host 'Deploying the weather REST API, MCP server, and A2A sample backend...'
Invoke-AzureCli (@('deployment', 'group', 'create') + $deploymentArguments + @('--output', 'none'))
$outputs = (& $az deployment group show --resource-group $ResourceGroupName --name $deploymentName --query properties.outputs --output json | ConvertFrom-Json)

Write-Host "Weather API:    $($outputs.weatherApiUrl.value)"
Write-Host "MCP server:     $($outputs.mcpServerUrl.value)"
Write-Host "A2A agent card: $($outputs.a2aAgentCardUrl.value)"
Write-Host 'Import the A2A agent card using the supported portal workflow described in the chapter.'
