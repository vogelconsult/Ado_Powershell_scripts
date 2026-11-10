# Load shared functions
. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"

# Configuration
$config = Get-OrgAndProjectConfiguration
$Organization = $config.Organization
$Project = $config.Project

$PlanId = [int](Read-Host "Enter Test Plan ID")
$SourceSuiteId = [int](Read-Host "Enter source Suite ID")
$DestinationSuiteId = [int](Read-Host "Enter destination Suite ID")

$PreserveStructure = (
    Read-Host "Preserve source folder structure? (Y/N, default N)"
) -match '^(?i)y(es)?$'

try {
    $Headers = Get-AdoAuthenticationHeaders

    $result = Clone-TestCases `
        -Organization $Organization `
        -Project $Project `
        -SourcePlanId  $PlanId `
        -SourceSuiteId $SourceSuiteId `
        -DestinationSuiteId $DestinationSuiteId `
        -Priority 1 `
        -PreserveStructure:$PreserveStructure `
        -Headers $Headers `
        -ErrorAction Stop

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