[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Configuration,

    [Parameter(Mandatory)]
    [ValidateSet('Subnets', 'DnsLinks', 'Chapter01', 'Chapter01aCore', 'CapabilityHosts', 'Model')]
    [string] $Stage,

    [ValidateSet('Preview', 'Deploy')]
    [string] $Action = 'Preview',

    [switch] $ConfirmDeployment
)

$ErrorActionPreference = 'Stop'
$configPath = (Resolve-Path $Configuration).Path
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$deployScript = Join-Path $PSScriptRoot 'deploy.ps1'

$required = @(
    'tenantId', 'subscription', 'workloadResourceGroupName',
    'networkResourceGroupName', 'privateDnsResourceGroupName',
    'location', 'searchLocation', 'vnetName', 'agentSubnetName',
    'agentSubnetPrefix', 'privateEndpointSubnetName',
    'privateEndpointSubnetPrefix', 'workloadName', 'environment'
)
foreach ($property in $required) {
    $value = $config.$property
    if ([string]::IsNullOrWhiteSpace("$value") -or "$value" -match '^<.*>$') {
        throw "Configuration property '$property' is missing or still a placeholder."
    }
}

if ($Action -eq 'Deploy' -and -not $ConfirmDeployment) {
    throw 'Deployment blocked. Review Preview first, then add -ConfirmDeployment.'
}

$arguments = @{
    Subscription                         = $config.subscription
    TenantId                             = $config.tenantId
    WorkloadResourceGroupName            = $config.workloadResourceGroupName
    NetworkResourceGroupName             = $config.networkResourceGroupName
    PrivateDnsResourceGroupName          = $config.privateDnsResourceGroupName
    Location                             = $config.location
    SearchLocation                       = $config.searchLocation
    VnetName                             = $config.vnetName
    AgentSubnetName                      = $config.agentSubnetName
    AgentSubnetPrefix                    = $config.agentSubnetPrefix
    PrivateEndpointSubnetName            = $config.privateEndpointSubnetName
    PrivateEndpointSubnetPrefix          = $config.privateEndpointSubnetPrefix
    CreatePrivateEndpointDnsZoneGroups   = [bool]$config.createPrivateEndpointDnsZoneGroups
    WorkloadName                         = $config.workloadName
    Environment                          = $config.environment
    FoundryUserObjectId                  = "$($config.foundryUserObjectId)"
    Step                                 = $Stage
}

if ($Stage -eq 'Model') {
    foreach ($property in 'modelDeploymentName', 'modelName', 'modelVersion', 'modelCapacity') {
        if (-not $config.$property -or "$($config.$property)" -match '^<.*>$') {
            throw "Model configuration property '$property' is missing or still a placeholder."
        }
    }
    $arguments.ModelDeploymentName = $config.modelDeploymentName
    $arguments.ModelName = $config.modelName
    $arguments.ModelVersion = $config.modelVersion
    $arguments.ModelCapacity = [int]$config.modelCapacity
}

Write-Host "Configuration: $configPath"
Write-Host "Stage:         $Stage"
Write-Host "Action:        $Action"
Write-Host "Subscription:  $($config.subscription)"
Write-Host "Tenant:        $($config.tenantId)"
Write-Host "Workload RG:   $($config.workloadResourceGroupName)"
Write-Host "Network:       $($config.networkResourceGroupName)/$($config.vnetName)"
Write-Host "DNS RG:        $($config.privateDnsResourceGroupName)"

if ($Action -eq 'Deploy') {
    $arguments.Execute = $true
}

& $deployScript @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Zava stage '$Stage' action '$Action' failed with exit code $LASTEXITCODE."
}
