
# Load shared functions
. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"

# Configuration
$config = Get-OrgAndProjectConfiguration
$Organization = $config.Organization
$Project = $config.Project

$PlanId = [int](Read-Host "Enter Test Plan ID")
$SourceSuiteId = [int](Read-Host "Enter source Suite ID")
$DestinationSuiteId = [int](Read-Host "Enter destination Suite ID")

$ExcludeSuiteInput = Read-Host "Enter Suite ID containing test cases that should NOT be cloned (filtered out) (leave blank to clone all matching test cases)"

$PreserveStructure = (
    Read-Host "Preserve source folder structure? (Y/N, default N)"
) -match '^(?i)y(es)?$'

try {
    $Headers = Get-AdoAuthenticationHeaders

    # Build cloning parameters
    $cloneParams = @{
        Organization       = $Organization
        Project            = $Project
        SourcePlanId       = $PlanId
        SourceSuiteId      = $SourceSuiteId
        DestinationSuiteId = $DestinationSuiteId
        Priority           = 1
        Outcome            = 'Passed'
        PreserveStructure  = $PreserveStructure
        Headers            = $Headers
        ErrorAction        = 'Stop'
    }

    # Optional exclusion suite
    if (-not [string]::IsNullOrWhiteSpace($ExcludeSuiteInput)) {
        $cloneParams.ExcludeTSInSuite = [int]$ExcludeSuiteInput
    }

    $result = Clone-TestCases @cloneParams

    Write-Host ""
    Write-Host "Clone summary"
    Write-Host "Source   : $($result.SourceCount)"
    Write-Host "Selected : $($result.SelectedCount)"
    Write-Host "Cloned   : $($result.ClonedCount)"
}
catch {
    Write-Error "Cloning failed: $($_.Exception.Message)"
    exit 1
}
