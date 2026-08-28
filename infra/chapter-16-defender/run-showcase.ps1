[CmdletBinding()]
param(
    [string] $SubscriptionName = 'ME-MngEnvMCAP152025-snair-1',
    [string] $ResourceGroupName = 'rg-agentic-ai-blueprint-dev',
    [string] $ApimName = 'apim-agent-blueprint-dev-a5jiq4re',
    [string] $AppInsightsName = 'agent-blueprint-dev-gateway-appi',
    [string] $AgentName = 'GovernedTravelSecurityDemo',
    [switch] $SkipDependencyInstall,
    [switch] $PauseBetweenSections
)

$ErrorActionPreference = 'Stop'
$demoScript = Join-Path $PSScriptRoot 'create-portal-demo-agent.py'
$deployScript = Join-Path $PSScriptRoot 'deploy.ps1'
$requirementsFile = Join-Path $PSScriptRoot 'requirements.txt'
$reportFile = Join-Path $PSScriptRoot 'showcase-report.json'

function Show-Section {
    param(
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string] $Message
    )
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host $Message
    if ($PauseBetweenSections) {
        Read-Host 'Press Enter to continue' | Out-Null
    }
}

function Assert-LastExitCode {
    param([Parameter(Mandatory)][string] $Operation)
    if ($LASTEXITCODE -ne 0) { throw "$Operation failed with exit code $LASTEXITCODE." }
}

foreach ($path in @($demoScript, $deployScript, $requirementsFile)) {
    if (-not (Test-Path $path)) { throw "Required showcase file not found: $path" }
}

$azCommand = Get-Command az -ErrorAction SilentlyContinue
if (-not $azCommand) { throw 'Azure CLI was not found. Install it and run az login first.' }
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCommand) { throw 'Python was not found. Install Python 3.11 or later.' }

Show-Section -Title '1. GOVERNANCE BASELINE' -Message @'
We begin with the control plane: the expected subscription, Defender for AI,
prompt evidence, Purview sharing, and the Chapter 15 monitoring workspace.
'@

& az account set --subscription $SubscriptionName
Assert-LastExitCode 'Selecting the Azure subscription'
& $deployScript -SubscriptionName $SubscriptionName -ResourceGroupName $ResourceGroupName

$defender = (& az security pricing show --name AI --output json | ConvertFrom-Json)
$evidence = $defender.extensions | Where-Object name -eq 'AIPromptEvidence'
$purview = $defender.extensions | Where-Object name -eq 'AIPromptSharingWithPurview'
Write-Host ("Defender for AI: {0}; prompt evidence: {1}; Purview sharing: {2}" -f `
    $defender.pricingTier, $evidence.isEnabled, $purview.isEnabled) -ForegroundColor Green

Show-Section -Title '2. WIRED AGENT CAPABILITIES' -Message @'
The agent combines policy grounding through Foundry IQ, an APIM-governed MCP
tool, and A2A delegation. The run trace will expose each operation separately.
'@

$apis = @(& az apim api list -g $ResourceGroupName --service-name $ApimName --output json | ConvertFrom-Json)
$weatherMcp = $apis | Where-Object { $_.name -eq 'weather-mcp' -or $_.apiType -eq 'mcp' }
if (-not $weatherMcp) {
    Write-Warning "The APIM weather MCP facade is not deployed. Knowledge IQ and A2A will work, but the weather step is expected to report a governed tool failure."
}
else {
    Write-Host "Weather MCP API: $($weatherMcp.name)" -ForegroundColor Green
}

if (-not $SkipDependencyInstall) {
    Write-Host 'Checking Python dependencies...'
    & python -m pip install --quiet --disable-pip-version-check -r $requirementsFile
    Assert-LastExitCode 'Installing showcase dependencies'
}

$appInsights = (& az resource show -g $ResourceGroupName -n $AppInsightsName `
    --resource-type Microsoft.Insights/components --api-version 2020-02-02 --output json | ConvertFrom-Json)
$env:APPLICATIONINSIGHTS_CONNECTION_STRING = $appInsights.properties.ConnectionString
if ([string]::IsNullOrWhiteSpace($env:APPLICATIONINSIGHTS_CONNECTION_STRING)) {
    throw "Application Insights '$AppInsightsName' did not return a connection string."
}
Write-Host "OpenTelemetry destination: $AppInsightsName" -ForegroundColor Green

Show-Section -Title '3. LIVE AGENT SCENARIOS' -Message @'
The script now creates a persistent Foundry portal agent and runs three cases:
an end-to-end travel request, a grounded policy lookup, and a jailbreak attempt.
'@

& python $demoScript --agent-name $AgentName --run-demo --report $reportFile
Assert-LastExitCode 'Running the governed agent scenarios'
if (-not (Test-Path $reportFile)) { throw "The demo completed without producing $reportFile." }

$report = Get-Content $reportFile -Raw | ConvertFrom-Json
Write-Host ''
Write-Host ("Agent: {0}, version {1}" -f $report.agent.name, $report.agent.version) -ForegroundColor Cyan
foreach ($scenario in $report.scenarios) {
    $displayStatus = $scenario.status
    $color = 'Green'
    if ($scenario.name -eq 'prompt-injection-defense' -and $scenario.status -eq 'blocked_or_failed') {
        $displayStatus = 'blocked as designed'
        $color = 'Green'
    }
    elseif ($scenario.status -ne 'completed') {
        $color = 'Yellow'
    }
    Write-Host ("  {0,-28} {1} ({2} ms)" -f $scenario.name, $displayStatus, $scenario.duration_ms) -ForegroundColor $color
}

Show-Section -Title '4. SHOW THE EVIDENCE IN THE PORTALS' -Message @"
Microsoft Foundry
  1. Open Agents > $AgentName.
  2. Open the latest version and show its two MCP tools and A2A tool.
  3. Open Tracing and expand the knowledge retrieval, MCP, and A2A calls.

Azure Monitor
  1. Open Workbooks > Agent Platform Observability.
  2. Open Application Insights > Logs and query:
     dependencies
     | where timestamp > ago(1h)
     | where operation_Name has "agent-demo-scenario"
     | project timestamp, duration, success, customDimensions

Microsoft Defender for Cloud
  1. Open Workload protections > AI workloads.
  2. Show AI inventory, recommendations, and prompt evidence.
  3. Correlate the blocked jailbreak scenario with the Foundry trace.

Report: $reportFile
"@

Write-Host ''
Write-Host 'Showcase run complete.' -ForegroundColor Green