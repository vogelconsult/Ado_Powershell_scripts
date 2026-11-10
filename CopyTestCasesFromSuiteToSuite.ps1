
# ============================================================
# Clone all test cases from one suite to another
# Including sub-suites
# ============================================================

# Load shared functions
. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"

# Configuration
$config = Get-OrgAndProjectConfiguration
$Organization = $config.Organization
$Project = $config.Project

$SourcePlanId = [int](Read-Host "Enter source Test Plan ID")
$SourceSuiteId = [int](Read-Host "Enter source Suite ID")

$DestinationPlanInput = Read-Host "Enter destination Test Plan ID (blank = same as source)"
$DestinationPlanId = if ([string]::IsNullOrWhiteSpace($DestinationPlanInput)) {
    $SourcePlanId
} else {
    [int]$DestinationPlanInput
}

$DestinationSuiteId = [int](Read-Host "Enter destination Suite ID")

$IncludeAttachments = (
    Read-Host "Include attachments? (Y/N, default N)"
) -match '^(?i)y(es)?$'

$IncludeLinks = (
    Read-Host "Include links? (Y/N, default N)"
) -match '^(?i)y(es)?$'

try {
    $Headers = Get-AdoAuthenticationHeaders

    Write-Host ""
    Write-Host "Cloning test cases..."
    Write-Host "Source      : Plan $SourcePlanId, Suite $SourceSuiteId"
    Write-Host "Destination : Plan $DestinationPlanId, Suite $DestinationSuiteId"
    Write-Host ""

    $result = Clone-TestCases `
        -Organization $Organization `
        -Project $Project `
        -SourcePlanId $SourcePlanId `
        -SourceSuiteId $SourceSuiteId `
        -DestinationPlanId $DestinationPlanId `
        -DestinationSuiteId $DestinationSuiteId `
        -PreserveStructure `
        -IncludeAttachments:$IncludeAttachments `
        -IncludeLinks:$IncludeLinks `
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

Read-Host "Press ENTER to close"
