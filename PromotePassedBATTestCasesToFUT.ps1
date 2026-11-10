
# Promote passed BAT test cases to FUT regression.
# Excludes test cases that cannot run in production.
# Skips logical IDs already present in FUT regression.

# Load shared functions
. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"

# Organization and project
$config = Get-OrgAndProjectConfiguration
$Organization = $config.Organization
$Project = $config.Project

# --------------------------------------------------
# Configuration
# --------------------------------------------------

# BAT source
$SourcePlanId = 1      # Set BAT Test Plan ID
$SourceSuiteId = 30476     # Set BAT root Suite ID
#$SourceSuiteId = 29632

# FUT regression destination
$DestinationPlanId = 1  # Set FUT Test Plan ID
#$DestinationSuiteId = 73110 # Set FUT regression Suite ID
$DestinationSuiteId = 73187

# Priorities to promote
# Start with @(1), expand to @(1, 2), etc.
$Priorities = @(1)

# CSV file containing test cases excluded from FUT regression
$csv_filename = 'Excluded BAT testcases.csv'


# Maintain original suite hierarchy
$PreserveStructure = $true


# --------------------------------------------------
# Execution
# --------------------------------------------------

try {
    if ($SourcePlanId -le 0 -or
        $SourceSuiteId -le 0 -or
        $DestinationPlanId -le 0 -or
        $DestinationSuiteId -le 0) {
        throw "Configure valid source and destination Plan/Suite IDs."
    }

    # Load exclusions from CSV
    $ExclusionFile = Join-Path $PSScriptRoot $csv_filename

    $ExcludeLogicalIds = @(
        Get-ExcludedTestCaseIds -Path $ExclusionFile -ErrorAction Stop
    )

    Write-Host "Loaded $($ExcludeLogicalIds.Count) excluded logical IDs."

    $Headers = Get-AdoAuthenticationHeaders


    $totalCloned = 0

    foreach ($Priority in ($Priorities | Sort-Object -Unique)) {

        Write-Host ""
        Write-Host "Promoting passed BAT Priority $Priority test cases..."

        $cloneParams = @{
            Organization       = $Organization
            Project            = $Project
            SourcePlanId       = $SourcePlanId
            SourceSuiteId      = $SourceSuiteId
            DestinationPlanId  = $DestinationPlanId
            DestinationSuiteId = $DestinationSuiteId

            Priority           = $Priority
            Outcome            = 'Passed'

            ExcludeLogicalIds  = $ExcludeLogicalIds
            SkipExisting       = $true
            PreserveStructure  = $PreserveStructure

            Headers            = $Headers
            ErrorAction        = 'Stop'
        }

        $result = Clone-TestCases @cloneParams

        Write-Host ""
        Write-Host "Priority $Priority summary"
        Write-Host "Source   : $($result.SourceCount)"
        Write-Host "Selected : $($result.SelectedCount)"
        Write-Host "Cloned   : $($result.ClonedCount)"

        $totalCloned += $result.ClonedCount
    }

    Write-Host ""
    Write-Host "BAT to FUT regression promotion completed."
    Write-Host "Total cloned: $totalCloned"
}
catch {
    Write-Error "BAT to FUT promotion failed: $($_.Exception.Message)"
    exit 1
}
