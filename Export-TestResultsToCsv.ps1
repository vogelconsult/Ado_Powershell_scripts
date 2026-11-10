
. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"

$config = Get-OrgAndProjectConfiguration
$headers = Get-AdoAuthenticationHeaders

$planId = 1
$suiteId = [int](Read-Host "Enter Suite ID")

# Get test points
$points = @(
    Get-SuiteTestPointOutcomes `
        -Organization $config.Organization `
        -Project $config.Project `
        -PlanId $planId `
        -SuiteId $suiteId `
        -Headers $headers
)

# Get linked defects for failed test points
$defects = @(
    Get-TestResultDefects `
        -Organization $config.Organization `
        -Project $config.Project `
        -TestPoints $points `
        -Headers $headers 
        #-Verbose
)

# Convert test points and defects into report
$results = @(
    ConvertTo-TestResultReport `
        -TestPoints $points `
        -LinkedDefects $defects
)

# Generate summary
$summary = Get-TestResultSummary -TestResults $results

# Define output file
$outputPath = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath "TestReport_$suiteId.xlsx"

# Generate Excel report
Export-TestExecutionReport `
    -TestResults $results `
    -Summary $summary `
    -PlanId $planId `
    -SuiteId $suiteId `
    -Organization $config.Organization `
    -Project $config.Project `
	-Headers $headers `
	-OutputPath $outputPath 

# Display summary
$summary | Format-List

# Export report to CSV
Export-TestResultsToCsv `
    -TestResults $results `
    -OutputPath "$PSScriptRoot\TestResults.csv"

Write-Host "Exported $($results.Count) test results."
