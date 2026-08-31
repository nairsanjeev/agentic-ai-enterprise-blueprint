[CmdletBinding()]
param(
    [string] $SubscriptionName = '<subscription-name>',
    [string] $Tenant = '<tenant-domain>',
    [string] $ResourceGroupName = 'rg-agentic-ai-blueprint-dev',
    [string] $FoundryAccountName = 'agent-blueprint-dev-foundry-std-vlpnxwtn',
    [string] $WorkspaceName = 'agent-blueprint-dev-law',
    [string] $SecurityContactEmail = '',
    [ValidateSet('Low', 'Medium', 'High')]
    [string] $MinimumAlertSeverity = 'High',
    [switch] $EnableModelScanner,
    [switch] $Execute,
    [switch] $Login
)

$ErrorActionPreference = 'Stop'
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

& $az cognitiveservices account show -g $ResourceGroupName -n $FoundryAccountName --output none 2>$null
if ($LASTEXITCODE -ne 0) { throw "Foundry account '$FoundryAccountName' not found. Deploy Chapter 01a first." }
& $az monitor log-analytics workspace show -g $ResourceGroupName -n $WorkspaceName --output none 2>$null
if ($LASTEXITCODE -ne 0) { throw "Log Analytics workspace '$WorkspaceName' not found. Deploy Chapter 15 first." }

$pricing = (& $az security pricing show --name AI --output json | ConvertFrom-Json)
$extensionState = @{}
foreach ($extension in $pricing.extensions) { $extensionState[$extension.name] = $extension.isEnabled }

Write-Host 'Chapter 16 Defender for AI plan:'
Write-Host "  Tier: $($pricing.pricingTier)"
Write-Host "  AI prompt evidence: $($extensionState['AIPromptEvidence'])"
Write-Host "  Purview prompt sharing: $($extensionState['AIPromptSharingWithPurview'])"
Write-Host "  AI model scanner: $($extensionState['AIModelScanner'])"
Write-Host "  Foundry account: $FoundryAccountName"
Write-Host "  Log Analytics workspace: $WorkspaceName"

$desiredModelScannerState = if ($EnableModelScanner) { 'True' } else { $extensionState['AIModelScanner'] }
$needsPlanUpdate = $pricing.pricingTier -ne 'Standard' -or
    $extensionState['AIPromptEvidence'] -ne 'True' -or
    $extensionState['AIPromptSharingWithPurview'] -ne 'True' -or
    ($EnableModelScanner -and $extensionState['AIModelScanner'] -ne 'True')

if (-not $Execute) {
    Write-Host ''
    if ($needsPlanUpdate) {
        Write-Host 'Preview: Defender for AI will be set to Standard with prompt evidence and Purview sharing enabled.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Preview: Defender for AI is already configured; no plan update is required.' -ForegroundColor Green
    }
    if (-not [string]::IsNullOrWhiteSpace($SecurityContactEmail)) {
        Write-Host "Preview: security contact '$SecurityContactEmail' will receive $MinimumAlertSeverity-or-higher alerts."
    }
    else {
        Write-Host 'Preview: no security contact change (pass -SecurityContactEmail to configure one).'
    }
    return
}

if ($needsPlanUpdate) {
    Write-Host 'Applying Defender for AI plan and evidence extensions...'
    Invoke-AzureCli -Arguments @(
        'security', 'pricing', 'create', '--name', 'AI', '--tier', 'Standard',
        '--extensions', 'name=AIPromptEvidence', 'isEnabled=True',
        '--extensions', 'name=AIPromptSharingWithPurview', 'isEnabled=True',
        '--extensions', 'name=AIModelScanner', "isEnabled=$desiredModelScannerState",
        '--output', 'none'
    )
}

if (-not [string]::IsNullOrWhiteSpace($SecurityContactEmail)) {
    Write-Host "Configuring Defender security contact '$SecurityContactEmail'..."
    Invoke-AzureCli -Arguments @(
        'security', 'contact', 'create', '--name', 'default',
        '--emails', $SecurityContactEmail,
        '--alert-notifications', "{`"state`":`"On`",`"minimalSeverity`":`"$MinimumAlertSeverity`"}",
        '--notifications-by-role', '{"state":"On","roles":["Owner"]}',
        '--output', 'none'
    )
}

$verified = (& $az security pricing show --name AI --output json | ConvertFrom-Json)
if ($verified.pricingTier -ne 'Standard') { throw "Defender for AI verification failed: tier is '$($verified.pricingTier)'." }
Write-Host 'Chapter 16 deployment complete. Defender for AI is enabled at Standard tier.' -ForegroundColor Green