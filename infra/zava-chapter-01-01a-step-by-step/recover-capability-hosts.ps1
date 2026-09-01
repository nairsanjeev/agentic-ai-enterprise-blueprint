[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $Subscription,

    [Parameter(Mandatory)]
    [string] $TenantId,

    [Parameter(Mandatory)]
    [string] $WorkloadResourceGroupName,

    [Parameter(Mandatory)]
    [string] $FoundryAccountName,

    [Parameter(Mandatory)]
    [string] $FoundryProjectName,

    [Parameter(Mandatory)]
    [string] $AgentSubnetResourceId
)

$ErrorActionPreference = 'Stop'

az account set --subscription $Subscription
if ($LASTEXITCODE -ne 0) { throw 'Unable to select the requested subscription.' }

$account = az account show --output json | ConvertFrom-Json
if ($account.tenantId -ne $TenantId) {
    throw "Tenant safety check failed. Active tenant is '$($account.tenantId)', expected '$TenantId'."
}

$accountId = "/subscriptions/$($account.id)/resourceGroups/$WorkloadResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryAccountName"
$accountHostName = "$FoundryAccountName-cap"
$projectHostName = "$FoundryProjectName-cap"
$apiVersion = '2025-06-01'

function Get-HostCollection {
    param([Parameter(Mandatory)][string] $Url)
    $json = az rest --method GET --url $Url --output json
    if ($LASTEXITCODE -ne 0) { throw "Unable to query capability hosts at $Url" }
    return $json | ConvertFrom-Json
}

function Invoke-HostPut {
    param(
        [Parameter(Mandatory)][string] $Url,
        [Parameter(Mandatory)][hashtable] $Body
    )

    $tempFile = New-TemporaryFile
    try {
        [System.IO.File]::WriteAllText($tempFile.FullName, ($Body | ConvertTo-Json -Depth 10 -Compress))
        az rest --method PUT --url $Url --headers 'Content-Type=application/json' --body "@$($tempFile.FullName)" --output json
        if ($LASTEXITCODE -ne 0) { throw "Capability-host PUT failed at $Url" }
    }
    finally {
        Remove-Item $tempFile.FullName -Force -ErrorAction SilentlyContinue
    }
}

$accountCollectionUrl = "https://management.azure.com$accountId/capabilityHosts?api-version=$apiVersion"
$projectCollectionUrl = "https://management.azure.com$accountId/projects/$FoundryProjectName/capabilityHosts?api-version=$apiVersion"

$accountHosts = Get-HostCollection -Url $accountCollectionUrl
$projectHosts = Get-HostCollection -Url $projectCollectionUrl

Write-Host "Account capability hosts found: $(@($accountHosts.value).Count)"
Write-Host "Project capability hosts found: $(@($projectHosts.value).Count)"

if (@($accountHosts.value).Count -eq 0) {
    $url = "https://management.azure.com$accountId/capabilityHosts/$accountHostName?api-version=$apiVersion"
    $body = @{
        properties = @{
            capabilityHostKind = 'Agents'
            customerSubnet = $AgentSubnetResourceId
        }
    }
    if ($PSCmdlet.ShouldProcess($accountHostName, 'Create missing account capability host')) {
        Invoke-HostPut -Url $url -Body $body
    }
}
else {
    $accountHosts.value | Select-Object name, @{Name='state'; Expression={$_.properties.provisioningState}} | Format-Table
    Write-Host 'The account capability host already exists; it was not resubmitted.'
}

# Refresh before deciding whether the project host can be created.
$accountHosts = Get-HostCollection -Url $accountCollectionUrl
$accountHost = @($accountHosts.value) | Where-Object name -eq $accountHostName | Select-Object -First 1
if (-not $accountHost) {
    throw 'The account capability host is still missing. Wait for its creation or investigate the preceding error before creating the project host.'
}
if ($accountHost.properties.provisioningState -eq 'Failed') {
    throw 'The account capability host exists in Failed state. Do not overwrite it; collect its error details and open a Microsoft support case if remediation is not explicit.'
}

$projectHosts = Get-HostCollection -Url $projectCollectionUrl
if (@($projectHosts.value).Count -eq 0) {
    $url = "https://management.azure.com$accountId/projects/$FoundryProjectName/capabilityHosts/$projectHostName?api-version=$apiVersion"
    $body = @{
        properties = @{
            capabilityHostKind = 'Agents'
            storageConnections = @('agent-storage')
            threadStorageConnections = @('agent-thread-storage')
            vectorStoreConnections = @('agent-vector-store')
        }
    }
    if ($PSCmdlet.ShouldProcess($projectHostName, 'Create missing project capability host')) {
        Invoke-HostPut -Url $url -Body $body
    }
}
else {
    $projectHosts.value | Select-Object name, @{Name='state'; Expression={$_.properties.provisioningState}} | Format-Table
    Write-Host 'The project capability host already exists; it was not resubmitted.'
}

Write-Host 'Final capability-host state:'
Get-HostCollection -Url $accountCollectionUrl | Select-Object -ExpandProperty value | Select-Object name, @{Name='state'; Expression={$_.properties.provisioningState}} | Format-Table
Get-HostCollection -Url $projectCollectionUrl | Select-Object -ExpandProperty value | Select-Object name, @{Name='state'; Expression={$_.properties.provisioningState}} | Format-Table
