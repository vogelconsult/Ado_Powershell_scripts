# Load shared functions
. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"

try {
    # Authentication first
    $Headers = Get-AdoAuthenticationHeaders

    # Configuration
    $config = Get-OrgAndProjectConfiguration
    $Organization = $config.Organization
    $Project = $config.Project

    $PlanId = [int](Read-Host "Enter Test Plan ID")

    # Select folder
    $FolderPath = Select-Folder `
		-Description "Select folder containing test case .txt files" `
		-InitialPath "$PSScriptRoot\TestCases"

    # Import
    $results = @(
        Import-TestCasesFromFolder `
            -Organization $Organization `
            -Project $Project `
            -PlanId $PlanId `
            -FolderPath $FolderPath `
            -Headers $Headers `
            -ErrorAction Stop
    )

    Write-Host ""
    Write-Host "Import summary"
    Write-Host "Processed : $($results.Count)"

    $results | Format-Table FileName, ExternalReferenceId, TestCaseId, SuiteId
}
catch {
    Write-Error "Import failed: $($_.Exception.Message)"
    exit 1
}