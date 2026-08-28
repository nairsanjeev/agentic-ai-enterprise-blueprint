# Runs the fully-private Foundry IQ index build (Path 2) with correctly quoted paths.
# Works regardless of the current directory or spaces in the path.
$ErrorActionPreference = 'Stop'

# Locate the Python installed for the current user.
$py = @(
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $py) {
    $py = (Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -Recurse -Filter python.exe -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}
if (-not $py) { throw 'Python not found. Install it: winget install --id Python.Python.3.12' }
Write-Host "Python: $py"

$script = Join-Path $PSScriptRoot 'build-private-index.py'
if (-not (Test-Path $script)) { throw "Script not found: $script" }

# Install deps. pip writes notices to stderr; don't treat those as fatal.
Write-Host 'Installing packages...'
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $py -m pip install --quiet --disable-pip-version-check azure-identity azure-search-documents openai 2>&1 | Out-Null
$ErrorActionPreference = $prev

# Run the build (quote the path so spaces are handled).
Write-Host 'Building the private index...'
& $py "$script"
if ($LASTEXITCODE -ne 0) { throw "build-private-index.py failed with exit code $LASTEXITCODE." }
Write-Host ''
Write-Host 'Done. Index enterprise-policies is built. Attach it to your agent (Knowledge) to test grounding.'
