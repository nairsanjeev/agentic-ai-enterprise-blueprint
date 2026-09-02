[CmdletBinding()]
param(
    [string] $Subscription = 'ME-MngEnvMCAP152025-snair-1',
    [string] $TenantId = '645effea-ca6d-443c-9dea-ca4cc3a418ff',
    [string] $WorkloadResourceGroupName = 'rg-jnj-agentic-blueprint',
    [string] $NetworkResourceGroupName = 'rg-jnj-agentic-blueprint',
    [string] $PrivateDnsResourceGroupName = 'rg-jnj-agentic-blueprint',
    [string] $Location = 'eastus',
    [string] $SearchLocation = 'eastus',
    [string] $VnetName = 'azr-133-eastus',
    [string] $AgentSubnetName = 'snet-zava-foundry-agent',
    [string] $AgentSubnetPrefix = '10.75.139.160/27',
    [string] $PrivateEndpointSubnetName = 'snet-zava-privateendpoints',
    [string] $PrivateEndpointSubnetPrefix = '10.75.139.144/28',
    [bool] $CreatePrivateEndpointDnsZoneGroups = $true,
    [string] $WorkloadName = 'zava',
    [ValidateSet('dev', 'test', 'prod')]
    [string] $Environment = 'dev',
    [string] $FoundryUserObjectId = '',
    [ValidateSet('CustomerNetwork', 'CustomerDns', 'Subnets', 'DnsLinks', 'Chapter01', 'Chapter01aCore', 'CapabilityHosts', 'Model', 'All')]
    [string] $Step = 'All',
    [string] $ModelDeploymentName = 'gpt-4o',
    [string] $ModelName = 'gpt-4o',
    [string] $ModelVersion = '2024-11-20',
    [ValidateRange(1, 1000)]
    [int] $ModelCapacity = 30,
    [switch] $Execute
)

$ErrorActionPreference = 'Stop'
$folder = $PSScriptRoot

if ($Step -eq 'All' -and $Execute) {
    throw 'All-at-once execution is blocked. Deploy one reviewed stage at a time.'
}

function Invoke-Az {
    param([Parameter(Mandatory)][string[]] $Arguments)
    Write-Verbose ('az ' + ($Arguments -join ' '))
    & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed with exit code $LASTEXITCODE."
    }
}

function Invoke-BicepStage {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $ResourceGroup,
        [Parameter(Mandatory)][string] $Template,
        [Parameter(Mandatory)][string[]] $Parameters
    )

    $templatePath = Join-Path $folder $Template
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    Write-Host "Template:       $templatePath"
    Write-Host "Resource group: $ResourceGroup"

    Invoke-Az @('bicep', 'build', '--file', $templatePath)

    $base = @(
        '--resource-group', $ResourceGroup,
        '--name', $Name,
        '--template-file', $templatePath,
        '--parameters'
    ) + $Parameters

    Write-Host 'Validating ARM schema, policy, permissions, and references...'
    Invoke-Az (@('deployment', 'group', 'validate') + $base + @('--output', 'none'))

    Write-Host 'Showing the exact Azure change preview...'
    Invoke-Az (@('deployment', 'group', 'what-if') + $base + @('--result-format', 'ResourceIdOnly'))

    if ($Execute) {
        Write-Host 'Executing the reviewed deployment...' -ForegroundColor Yellow
        Invoke-Az (@('deployment', 'group', 'create') + $base + @('--output', 'none'))
        Write-Host "$Name completed." -ForegroundColor Green
    }
    else {
        Write-Host 'Preview only. Rerun with -Execute after approval.' -ForegroundColor Yellow
    }
}

# Safety: select the requested subscription, then verify the immutable tenant ID. This works
# for member and guest/#EXT# identities and avoids relying on an email-domain suffix.
Invoke-Az @('account', 'set', '--subscription', $Subscription)
$account = az account show --output json | ConvertFrom-Json
if ($account.tenantId -ne $TenantId) {
    throw "Tenant safety check failed. Active tenant is '$($account.tenantId)', expected '$TenantId'."
}
Write-Host "Subscription: $($account.name) ($($account.id))"
Write-Host "Tenant:       $($account.tenantId)"
Write-Host "User:         $($account.user.name)"

if ([string]::IsNullOrWhiteSpace($FoundryUserObjectId)) {
    $FoundryUserObjectId = az ad signed-in-user show --query id --output tsv
    if (-not $FoundryUserObjectId) {
        throw 'Unable to resolve the signed-in user object ID. Pass -FoundryUserObjectId explicitly.'
    }
}

# Zava owns provider registration. This script checks state but never changes subscription state.
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
$unregistered = @()
foreach ($provider in $requiredProviders) {
    $state = az provider show --namespace $provider --query registrationState --output tsv
    Write-Host ("Provider {0,-38} {1}" -f $provider, $state)
    if ($state -ne 'Registered') { $unregistered += $provider }
}
if ($unregistered.Count -gt 0) {
    throw "Zava must register these providers before deployment: $($unregistered -join ', ')"
}

$runAll = $Step -eq 'All'

if ($runAll -or $Step -eq 'CustomerNetwork') {
    Invoke-BicepStage `
        -Name 'zava-00-customer-network' `
        -ResourceGroup $NetworkResourceGroupName `
        -Template '00-simulate-customer-network.bicep' `
        -Parameters @("location=$Location", "vnetName=$VnetName")
}

if ($runAll -or $Step -eq 'CustomerDns') {
    Invoke-BicepStage `
        -Name 'zava-00b-customer-dns' `
        -ResourceGroup $PrivateDnsResourceGroupName `
        -Template '00b-simulate-customer-dns.bicep' `
        -Parameters @()
}

if ($runAll -or $Step -eq 'Subnets') {
    # This stage deploys at the network RG scope because it creates child subnets there.
    Invoke-BicepStage `
        -Name 'zava-01-foundry-subnets' `
        -ResourceGroup $NetworkResourceGroupName `
        -Template '01-create-foundry-subnets.bicep' `
        -Parameters @(
            "vnetName=$VnetName",
            "agentSubnetName=$AgentSubnetName",
            "agentSubnetPrefix=$AgentSubnetPrefix",
            "privateEndpointSubnetName=$PrivateEndpointSubnetName",
            "privateEndpointSubnetPrefix=$PrivateEndpointSubnetPrefix"
        )
}

if ($runAll -or $Step -eq 'DnsLinks') {
    Invoke-BicepStage `
        -Name 'zava-02-private-dns-links' `
        -ResourceGroup $PrivateDnsResourceGroupName `
        -Template '02-link-customer-private-dns.bicep' `
        -Parameters @(
            "networkResourceGroupName=$NetworkResourceGroupName",
            "vnetName=$VnetName"
        )
}

$workloadParameters = @(
    "location=$Location",
    "workloadName=$WorkloadName",
    "environment=$Environment",
    "networkResourceGroupName=$NetworkResourceGroupName",
    "vnetName=$VnetName",
    "privateEndpointSubnetName=$PrivateEndpointSubnetName",
    "privateDnsResourceGroupName=$PrivateDnsResourceGroupName",
    "createPrivateEndpointDnsZoneGroups=$($CreatePrivateEndpointDnsZoneGroups.ToString().ToLowerInvariant())",
    "foundryUserPrincipalId=$FoundryUserObjectId"
)

if ($runAll -or $Step -eq 'Chapter01') {
    Invoke-BicepStage `
        -Name "zava-03-chapter-01-$Environment" `
        -ResourceGroup $WorkloadResourceGroupName `
        -Template '03-chapter-01-foundation.bicep' `
        -Parameters $workloadParameters
}

if ($runAll -or $Step -eq 'Chapter01aCore') {
    Invoke-BicepStage `
        -Name "zava-04-chapter-01a-core-$Environment" `
        -ResourceGroup $WorkloadResourceGroupName `
        -Template '04-chapter-01a-standard-core.bicep' `
        -Parameters ($workloadParameters + @("searchLocation=$SearchLocation", "agentSubnetName=$AgentSubnetName"))
}

if ($runAll -or $Step -eq 'CapabilityHosts') {
    # Guard against accidental reruns. Existing capability hosts must be inspected and recovered
    # individually rather than resubmitting both resources.
    $coreDeployment = "zava-04-chapter-01a-core-$Environment"
    $accountName = az deployment group show -g $WorkloadResourceGroupName -n $coreDeployment --query properties.outputs.foundryAccountName.value -o tsv
    $projectName = az deployment group show -g $WorkloadResourceGroupName -n $coreDeployment --query properties.outputs.foundryProjectName.value -o tsv
    if (-not $accountName -or -not $projectName) {
        throw 'Step 04 outputs were not found. Complete Chapter01aCore first.'
    }

    $accountId = "/subscriptions/$($account.id)/resourceGroups/$WorkloadResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$accountName"
    $accountHosts = az rest --method GET --url "https://management.azure.com$accountId/capabilityHosts?api-version=2025-06-01" --query 'length(value)' -o tsv
    $projectHosts = az rest --method GET --url "https://management.azure.com$accountId/projects/$projectName/capabilityHosts?api-version=2025-06-01" --query 'length(value)' -o tsv
    if ([int]$accountHosts -gt 0 -or [int]$projectHosts -gt 0) {
        throw "Capability host already exists (account=$accountHosts, project=$projectHosts). Do not rerun; inspect README recovery steps."
    }

    Invoke-BicepStage `
        -Name "zava-05-capability-hosts-$Environment" `
        -ResourceGroup $WorkloadResourceGroupName `
        -Template '05-chapter-01a-capability-hosts.bicep' `
        -Parameters @(
            "workloadName=$WorkloadName",
            "environment=$Environment",
            "networkResourceGroupName=$NetworkResourceGroupName",
            "vnetName=$VnetName",
            "agentSubnetName=$AgentSubnetName"
        )
}

if ($runAll -or $Step -eq 'Model') {
    $coreDeployment = "zava-04-chapter-01a-core-$Environment"
    $accountName = az deployment group show -g $WorkloadResourceGroupName -n $coreDeployment --query properties.outputs.foundryAccountName.value -o tsv
    if (-not $accountName) { throw 'Step 04 output was not found. Complete Chapter01aCore first.' }

    Write-Host "`n=== Zava model deployment ===" -ForegroundColor Cyan
    Write-Host "Account:  $accountName"
    Write-Host "Model:    $ModelName $ModelVersion"
    Write-Host "SKU:      GlobalStandard"
    Write-Host "Capacity: $ModelCapacity"
    if ($Execute) {
        Invoke-Az @(
            'cognitiveservices', 'account', 'deployment', 'create',
            '--resource-group', $WorkloadResourceGroupName,
            '--name', $accountName,
            '--deployment-name', $ModelDeploymentName,
            '--model-name', $ModelName,
            '--model-version', $ModelVersion,
            '--model-format', 'OpenAI',
            '--sku-name', 'GlobalStandard',
            '--sku-capacity', "$ModelCapacity",
            '--output', 'none'
        )
        Write-Host 'Model deployment completed.' -ForegroundColor Green
    }
    else {
        Write-Host 'Preview only; no model deployment was created.' -ForegroundColor Yellow
    }
}
