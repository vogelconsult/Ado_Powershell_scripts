
# CloneSingleTestCase.ps1

. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"

$config = Get-OrgAndProjectConfiguration
$Organization = $config.Organization
$Project = $config.Project

# --------------------------------------------------
# Configuration
# --------------------------------------------------

$SourcePlanId = 1
$SourceSuiteId = 30476

$DestinationPlanId = 1
$DestinationSuiteId = 73110

$LogicalId = 'CHANGE-TS51'

# --------------------------------------------------
# Execution
# --------------------------------------------------

try {
    $Headers = Get-AdoAuthenticationHeaders

    # Retrieve test cases from source hierarchy
    $testCases = @(
        Get-TestCasesInSuite `
            -Organization $Organization `
            -Project $Project `
            -PlanId $SourcePlanId `
            -SuiteId $SourceSuiteId `
            -Headers $Headers `
            -IncludeSubSuites
    )

    # Find matching logical ID
    $matches = @(
        $testCases |
            Get-TestCaseLogicalId |
            Where-Object { $_.LogicalId -eq $LogicalId }
    )

    if ($matches.Count -ne 1) {
        throw "Expected exactly one '$LogicalId', found $($matches.Count)."
    }

    $source = $matches[0].TestCase

    Write-Host "Found test case:"
    Write-Host "  ID    : $($source.TestCaseId)"
    Write-Host "  Title : $($source.Title)"
    Write-Host "  Suite : $($source.SuiteId)"

    # Resolve destination folder using the source suite structure
$pathParts = @(
    $source.SuitePath -split '\s*>\s*'
)

# Remove source root suite from path
$relativePath = @(
    $pathParts | Select-Object -Skip 1
)

$targetSuiteId = Get-OrCreateTestSuitePath `
    -Organization $Organization `
    -Project $Project `
    -PlanId $DestinationPlanId `
    -ParentSuiteId $DestinationSuiteId `
    -SuitePath $relativePath `
    -Headers $Headers

	if ($targetSuiteId -le 0) {
		throw "Could not resolve destination suite for '$LogicalId'."
	}

	Write-Host "Source path : $($source.SuitePath)"
	Write-Host "Target suite: $targetSuiteId"

	# Clone test case into corresponding destination folder
	$result = @(
		Clone-TestCasesToSuite `
			-Organization $Organization `
			-Project $Project `
			-SourcePlanId $SourcePlanId `
			-SourceSuiteId $source.SuiteId `
			-TargetPlanId $DestinationPlanId `
			-TargetSuiteId $targetSuiteId `
			-TestCaseIds @($source.TestCaseId) `
			-Headers $Headers
	)

	Write-Host "Cloning completed."
	$result | Format-Table -AutoSize
}
catch {
    Write-Error "Cloning failed: $($_.Exception.Message)"
}
