
# CopyPassedTestCases.ps1

# Load shared functions
. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"

$config = Get-OrgAndProjectConfiguration
$Organization = $config.Organization
$Project = $config.Project

# Configuration
$PlanId = [int](Read-Host "Enter Test Plan ID")
$SourceSuiteId = [int](Read-Host "Enter source Suite ID")
$DestinationSuiteId = [int](Read-Host "Enter destination Suite ID")
$ExcludeSuiteId = [int](Read-Host "Enter exclusion Suite ID")

$PriorityInput = Read-Host "Enter Priority (1-4, leave blank for all)"

$PreserveStructure = (
    Read-Host "Preserve source folder structure? (Y/N, default N)"
) -match '^(?i)y(es)?$'

try {
    $Headers = Get-AdoAuthenticationHeaders

    $cloneParams = @{
        Organization       = $Organization
        Project            = $Project
        SourcePlanId       = $PlanId
        SourceSuiteId      = $SourceSuiteId
        DestinationSuiteId = $DestinationSuiteId

        Outcome            = 'Passed'
        ExcludeTSInSuite   = $ExcludeSuiteId
        SkipExisting       = $true
        PreserveStructure  = $PreserveStructure

        Headers            = $Headers
        ErrorAction        = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($PriorityInput)) {
        $cloneParams.Priority = [int]$PriorityInput
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
