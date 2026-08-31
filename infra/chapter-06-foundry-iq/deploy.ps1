[CmdletBinding()]
param(
    [string] $SubscriptionName = '<subscription-name>',
    [string] $Tenant = '<tenant-domain>',

    [string] $ResourceGroupName = 'rg-agentic-ai-blueprint-dev',
    [string] $FoundryAccountName = 'agent-blueprint-dev-foundry-std-vlpnxwtn',
    [string] $StorageAccountName = 'ststdfbconcwrg7ntw',
    [string] $KnowledgeContainerName = 'knowledge-base',
    [string] $EmbeddingModelName = 'text-embedding-3-small',
    [string] $EmbeddingModelVersion = '1',
    [ValidateRange(1, 1000)]
    [int] $EmbeddingCapacity = 50,

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

# Confirm the Standard Foundry account exists (Chapter 01a).
& $az cognitiveservices account show -g $ResourceGroupName -n $FoundryAccountName --output none 2>$null
if ($LASTEXITCODE -ne 0) { throw "Foundry account '$FoundryAccountName' not found. Deploy Chapter 01a first." }

$deploymentName = 'chapter-06-dev'
$deploymentArguments = @(
    '--resource-group', $ResourceGroupName,
    '--name', $deploymentName,
    '--template-file', $templateFile,
    '--parameters',
    "foundryAccountName=$FoundryAccountName",
    "storageAccountName=$StorageAccountName",
    "knowledgeContainerName=$KnowledgeContainerName",
    "embeddingModelName=$EmbeddingModelName",
    "embeddingModelVersion=$EmbeddingModelVersion",
    "embeddingCapacity=$EmbeddingCapacity"
)

Write-Host 'Validating the Chapter 06 deployment...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'validate') + $deploymentArguments + @('--output', 'none'))

Write-Host 'Previewing Azure changes with what-if...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'what-if') + $deploymentArguments)

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Preview complete. Rerun with -Execute to deploy (embedding model + knowledge-base container).'
    exit 0
}

Write-Host 'Deploying Chapter 06 (embedding model + knowledge-base container)...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'create') + $deploymentArguments + @('--output', 'none'))

Write-Host ''
Write-Host 'Chapter 06 infrastructure deployed.'
Write-Host 'Next (from inside the VNet — storage and Foundry data plane are private):'
Write-Host "  1. Upload .\sample-docs\*.md to the '$KnowledgeContainerName' container in '$StorageAccountName'."
Write-Host '  2. In the Foundry portal (Standard project) > Knowledge > Create Knowledge Index:'
Write-Host "       source = Blob '$KnowledgeContainerName', embedding = $EmbeddingModelName, search = Hybrid."
Write-Host '  3. Validate with TEST.md.'
