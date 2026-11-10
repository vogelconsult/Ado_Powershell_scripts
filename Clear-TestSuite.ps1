
# Load shared functions
. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"

try {
    # Authentication first
    $Headers = Get-AdoAuthenticationHeaders

    # Configuration
    $config = Get-OrgAndProjectConfiguration
    $Organization = $config.Organization
    $Project = $config.Project

    $PlanId = 1
    $SuiteId = [int](Read-Host "Enter Suite ID to clear")

    # Clear suite
    Clear-TestSuite `
        -Organization $Organization `
        -Project $Project `
        -PlanId $PlanId `
        -SuiteId $SuiteId `
        -Headers $Headers `
        -ErrorAction Stop

    Write-Host "Suite $SuiteId cleared successfully."
}
catch {
    Write-Error "Failed to clear test suite: $($_.Exception.Message)"
}
finally {
    Read-Host "Press ENTER to close"
}
