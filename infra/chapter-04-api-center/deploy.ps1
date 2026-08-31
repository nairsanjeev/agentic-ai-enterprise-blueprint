[CmdletBinding()]
param(
    [string] $SubscriptionName = '<subscription-name>',
    [string] $Tenant = '<tenant-domain>',

    [string] $ResourceGroupName = 'rg-agentic-ai-blueprint-dev',
    [string] $Location = 'eastus',
    [string] $WorkloadName = 'agent-blueprint',
    [ValidateSet('dev', 'test', 'prod')]
    [string] $Environment = 'dev',

    # Existing APIM to link for automatic API/MCP sync.
    [string] $ApimName = 'apim-agent-blueprint-dev-a5jiq4re',

    # Object ID granted Azure API Center Data Reader. Defaults to the signed-in user.
    [string] $CatalogReaderObjectId = '',

    # Also create the Entra app registration for the managed developer portal sign-in.
    [switch] $ConfigurePortalApp,

    # Without -Execute, the script validates and previews changes but does not deploy.
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
    if (-not $Login) {
        throw "Azure CLI is not signed in. Run 'az login --tenant $Tenant --use-device-code', then rerun this script."
    }
    Invoke-AzureCli -Arguments @('login', '--tenant', $Tenant, '--use-device-code', '--output', 'none')
}

Invoke-AzureCli -Arguments @('account', 'set', '--subscription', $SubscriptionName)
$account = (& $az account show --output json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the selected Azure account.' }

$signedInUser = $account.user.name
if ($account.name -ne $SubscriptionName) {
    throw "Safety check failed. Selected subscription is '$($account.name)', expected '$SubscriptionName'."
}
if ([string]::IsNullOrWhiteSpace($signedInUser) -or -not $signedInUser.ToLowerInvariant().EndsWith('@' + $Tenant.ToLowerInvariant())) {
    throw "Safety check failed. Signed-in user '$signedInUser' is not in tenant '$Tenant'."
}

Write-Host "Target subscription: $($account.name) ($($account.id))"
Write-Host "Resource group:      $ResourceGroupName"
Write-Host "Azure region:        $Location"

# Confirm the APIM to link exists.
& $az apim show --resource-group $ResourceGroupName --name $ApimName --output none 2>$null
if ($LASTEXITCODE -ne 0) { throw "APIM '$ApimName' was not found in '$ResourceGroupName'. Deploy Chapter 02 first." }

if ([string]::IsNullOrWhiteSpace($CatalogReaderObjectId)) {
    $CatalogReaderObjectId = (& $az ad signed-in-user show --query id --output tsv)
    if ([string]::IsNullOrWhiteSpace($CatalogReaderObjectId)) {
        throw 'Could not resolve the signed-in user object ID. Pass -CatalogReaderObjectId explicitly.'
    }
}
Write-Host "Catalog reader grant: $CatalogReaderObjectId"

$requiredProviders = @('Microsoft.ApiCenter', 'Microsoft.ManagedIdentity', 'Microsoft.Authorization')
foreach ($provider in $requiredProviders) {
    Write-Host "Requesting registration for resource provider: $provider"
    Invoke-AzureCli -Arguments @('provider', 'register', '--namespace', $provider, '--output', 'none')
}

$deploymentName = "chapter-04-$Environment"
$deploymentArguments = @(
    '--resource-group', $ResourceGroupName,
    '--name', $deploymentName,
    '--template-file', $templateFile,
    '--parameters',
    "location=$Location",
    "workloadName=$WorkloadName",
    "environment=$Environment",
    "apimName=$ApimName",
    "catalogReaderPrincipalId=$CatalogReaderObjectId",
    'catalogReaderPrincipalType=User'
)

Write-Host 'Validating the Chapter 04 deployment...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'validate') + $deploymentArguments + @('--output', 'none'))

Write-Host 'Previewing Azure changes with what-if...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'what-if') + $deploymentArguments + @('--result-format', 'FullResourcePayloads'))

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Preview complete. Rerun with -Execute to deploy the resources shown above.'
    exit 0
}

Write-Host 'Deploying Chapter 04 (API Center, identity, APIM link, metadata, RBAC)...'
Invoke-AzureCli -Arguments (@('deployment', 'group', 'create') + $deploymentArguments + @('--output', 'none'))

$apiCenterName = (& $az deployment group show --resource-group $ResourceGroupName --name $deploymentName --query 'properties.outputs.apiCenterName.value' --output tsv)
$portalUrl = (& $az deployment group show --resource-group $ResourceGroupName --name $deploymentName --query 'properties.outputs.portalUrl.value' --output tsv)
Write-Host "API Center: $apiCenterName"
Write-Host "Portal URL: $portalUrl"

# The APIM link syncs on-demand the first time; trigger an import so the catalog is populated now.
Write-Host 'Importing APIM APIs and MCP servers into the catalog...'
Invoke-AzureCli -Arguments @('apic', 'import-from-apim', '--resource-group', $ResourceGroupName, '--service-name', $apiCenterName, '--apim-name', $ApimName, '--apim-apis', '*')

# Entra apps are not ARM; optionally create the managed-portal sign-in app here.
if ($ConfigurePortalApp) {
    Write-Host 'Creating the developer-portal sign-in Entra app...'
    $portalAppId = (& $az ad app create --display-name "API Center Portal - $apiCenterName" --sign-in-audience AzureADMyOrg --query appId --output tsv)
    $portalObjId = (& $az ad app show --id $portalAppId --query id --output tsv)
    $spa = "{""spa"":{""redirectUris"":[""$portalUrl""]}}"
    $tmp = New-TemporaryFile
    [System.IO.File]::WriteAllText($tmp.FullName, $spa, (New-Object System.Text.UTF8Encoding($false)))
    Invoke-AzureCli -Arguments @('rest', '--method', 'PATCH', '--url', "https://graph.microsoft.com/v1.0/applications/$portalObjId", '--headers', 'Content-Type=application/json', '--body', "@$($tmp.FullName)")
    Remove-Item $tmp.FullName
    Write-Host "Portal sign-in app clientId: $portalAppId"
    Write-Host "Finish in the Azure portal: API Center portal > Identity provider > Microsoft Entra ID > paste this clientId + tenant, then grant admin consent."
}

Write-Host ''
Write-Host 'Chapter 04 deployment completed.'
Write-Host 'Validate with TEST.md. Enable the managed developer portal in the Azure portal (see README).'
