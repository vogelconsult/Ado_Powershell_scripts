. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"


# ============================================================
# CONFIGURATION
# ============================================================

$Organization = "TelenorDenmark-Prod"
$Project      = "Telenor Denmark"

$PlanId = 1

$DirectingSuiteId   = [int](Read-Host "Enter directing folder Suite ID")
$DirectingSuiteName = "Directing"

$SourceSuiteId      = [int](Read-Host "Enter source folder Suite ID")
$SourceSuiteName    = "Source"

$DestinationSuiteId   = [int](Read-Host "Enter destination folder Suite ID")
$DestinationSuiteName = "Target"


# ============================================================
# AUTHENTICATION
# ============================================================

$securePat =
    Read-Host "Enter Azure DevOps PAT" -AsSecureString

$ptr =
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePat)

try {
    $pat =
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

$base64AuthInfo = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":$pat")
)

$Headers = @{
    Authorization = "Basic $base64AuthInfo"
    Accept        = "application/json"
}


# ============================================================
# STEP 1
# Read the directing tree and determine which logical testcases
# are required.
#
# A logical testcase ID consists of:
#
#   Area + testcase number
#
# Examples:
#
#   FUT-Buy-TS18
#       -> BUY-TS18
#
#   FUT-Change-TS18
#       -> CHANGE-TS18
#
#   FUT-GET_HELP-11
#       -> GET_HELP-11
#
# Variants such as TS01a and TS01b are reduced to their parent
# logical testcase number TS01.
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "READING DIRECTING FOLDER"
Write-Host "============================================================"

$directingTestCases = @(
    Get-TestCasesInSuite `
        -Organization $Organization `
        -Project $Project `
        -PlanId $PlanId `
        -SuiteId $DirectingSuiteId `
        -SuiteName $DirectingSuiteName `
        -Headers $Headers `
        -IncludeSubSuites
)

$directingLogicalIds = @(
    $directingTestCases |
        Get-TestCaseLogicalId
)

$wantedLogicalIds = @(
    $directingLogicalIds |
        Select-Object -ExpandProperty LogicalId -Unique |
        Sort-Object
)

Write-Host ""
Write-Host "Directing testcases read : $($directingTestCases.Count)"
Write-Host "Logical IDs requested    : $($wantedLogicalIds.Count)"
Write-Host ""

foreach ($logicalId in $wantedLogicalIds) {
    Write-Host "  $logicalId"
}


# ============================================================
# STEP 2
# Read the source tree and find all source testcases whose
# logical ID is requested by the directing tree.
#
# More than one source testcase may have the same logical ID.
# This is intentional.
#
# Example:
#
#   BUY-TS68
#
# may exist as separate browser variants for:
#
#   Chrome for Windows
#   Safari on iPhone
#   Edge on Windows
#   Safari on Mac
#   Chrome on Android
#   Chrome on Mac
#
# All matching source testcases must be cloned.
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "READING SOURCE FOLDER"
Write-Host "============================================================"

$sourceTestCases = @(
    Get-TestCasesInSuite `
        -Organization $Organization `
        -Project $Project `
        -PlanId $PlanId `
        -SuiteId $SourceSuiteId `
        -SuiteName $SourceSuiteName `
        -Headers $Headers `
        -IncludeSubSuites
)

$sourceLogicalIds = @(
    $sourceTestCases |
        Get-TestCaseLogicalId
)

$matches = @(
    $sourceLogicalIds |
        Where-Object {
            $_.LogicalId -in $wantedLogicalIds
        } |
        Group-Object {
            $_.TestCase.TestCaseId
        } |
        ForEach-Object {
            $_.Group[0]
        }
)


# ============================================================
# STEP 3
# Report how well the directing logical IDs were found in the
# source tree.
#
# Multiple source testcases for the same logical ID are valid
# and will all be cloned.
#
# Logical IDs that cannot be found are reported but do not stop
# the script.
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "MATCH RESULTS"
Write-Host "============================================================"

$missingLogicalIds = @()

foreach ($logicalId in $wantedLogicalIds) {

    $logicalIdMatches = @(
        $matches |
            Where-Object {
                $_.LogicalId -eq $logicalId
            }
    )

    if ($logicalIdMatches.Count -eq 0) {

        Write-Warning `
            "$logicalId was not found in the source tree."

        $missingLogicalIds +=
            $logicalId

        continue
    }

    Write-Host `
        "$logicalId -> $($logicalIdMatches.Count) source testcase(s)"

    foreach ($match in $logicalIdMatches) {

        Write-Host `
            "  $($match.TestCase.TestCaseId) - $($match.TestCase.Title)"

        Write-Host `
            "  $($match.TestCase.SuitePath)"
    }
}


# ============================================================
# STEP 4
# Recreate the required source hierarchy in the destination and
# clone every matching source testcase.
#
# Testcases are CLONED rather than added to the destination
# suite as references. This ensures that the FUT testcases are
# new, independent ADO Test Case work items.
#
# The source root is synthetic and is not recreated.
#
# Example:
#
#   Source > Buy > Mobile
#
# becomes:
#
#   Destination > Buy > Mobile
#
# Testcases are grouped by source suite because the ADO clone
# operation requires both a source suite and a destination suite.
#
# Clone-TestCasesToSuite returns a mapping between each original
# source testcase ID and the newly created clone ID:
#
#   SourceTestCaseId
#   ClonedTestCaseId
#
# Each cloned testcase is then renamed using the logical ID that
# was already determined from the source testcase.
#
# Example:
#
#   BAT - Buy - TS07 - Description
#
# becomes:
#
#   FUT-BUY-TS07 - Description
#
# The identifying part of the FUT testcase name contains no
# whitespace.
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "CLONING TESTCASES"
Write-Host "============================================================"

$clonedTestCaseIds = @()

$sourceGroups = @(
    $matches |
        Group-Object {
            $_.TestCase.SuiteId
        }
)

foreach ($group in $sourceGroups) {

    $groupMatches =
        @($group.Group)

    $firstMatch =
        $groupMatches[0]

    $currentSourceSuiteId =
		[int]$firstMatch.TestCase.SuiteId


    # --------------------------------------------------------
    # Determine the corresponding destination folder
    # --------------------------------------------------------

    $relativePath = @(
        ($firstMatch.TestCase.SuitePath -split ' > ') |
            Select-Object -Skip 1
    )

    Write-Host ""
    Write-Host `
        "Source folder: $($firstMatch.TestCase.SuitePath)"

    if ($relativePath.Count -gt 0) {

        Write-Host `
            "Target path  : $($relativePath -join ' > ')"
    }
    else {

        Write-Host `
            "Target path  : destination root"
    }

    $currentTargetSuiteId = Get-OrCreateTestSuitePath `
        -Organization $Organization `
        -Project $Project `
        -PlanId $PlanId `
        -ParentSuiteId $DestinationSuiteId `
        -SuitePath $relativePath `
        -Headers $Headers


    # --------------------------------------------------------
    # Collect the source testcase IDs that must be cloned from
    # this source suite
    # --------------------------------------------------------

    $sourceTestCaseIds = @(
        $groupMatches |
            ForEach-Object {
                [int]$_.TestCase.TestCaseId
            } |
            Sort-Object -Unique
    )

    foreach ($match in $groupMatches) {

        Write-Host `
            "  $($match.LogicalId): $($match.TestCase.TestCaseId) - $($match.TestCase.Title)"
    }


    # --------------------------------------------------------
    # Clone the source testcases
    #
    # Clone-TestCasesToSuite clones each testcase as a new,
    # independent ADO Test Case work item and returns the mapping
    # between source ID and clone ID.
    # --------------------------------------------------------

    $cloneResults = @(
        Clone-TestCasesToSuite `
            -Organization $Organization `
            -Project $Project `
            -SourcePlanId $PlanId `
            -SourceSuiteId $currentSourceSuiteId `
            -TargetPlanId $PlanId `
            -TargetSuiteId $currentTargetSuiteId `
            -TestCaseIds $sourceTestCaseIds `
            -Headers $Headers
    )


    # --------------------------------------------------------
    # Rename each newly cloned testcase
    #
    # We deliberately use the logical ID already calculated from
    # the source testcase instead of trying to determine it again
    # from the cloned testcase.
    # --------------------------------------------------------

    foreach ($cloneResult in $cloneResults) {

        $sourceMatch = $groupMatches |
            Where-Object {
                $_.TestCase.TestCaseId -eq
                    $cloneResult.SourceTestCaseId
            } |
            Select-Object -First 1

        if (-not $sourceMatch) {

            throw `
                "Could not find source information for testcase $($cloneResult.SourceTestCaseId)."
        }

        Set-TestCaseTitle `
            -Organization $Organization `
            -Project $Project `
            -TestCaseId $cloneResult.ClonedTestCaseId `
            -LogicalId $sourceMatch.LogicalId `
            -SourceTitle $sourceMatch.TestCase.Title `
            -Headers $Headers

		# Reset the cloned Test Case work item

		Reset-TestCase `
			-Organization $Organization `
			-Project $Project `
			-TestCaseId $cloneResult.ClonedTestCaseId `
			-Headers $Headers


		# Reset test execution progress in the destination suite

		Reset-TestProgress `
			-Organization $Organization `
			-Project $Project `
			-PlanId $PlanId `
			-SuiteId $currentTargetSuiteId `
			-TestCaseId $cloneResult.ClonedTestCaseId `
			-Headers $Headers


		# Add traceability back to the source testcase

		$sourcePrefix =
			if ($sourceMatch.TestCase.Title -match '(?i)^\s*M\s*-\s*BAT\b') {
				"M-BAT"
			}
			else {
				"BAT"
			}

		Add-TestCaseCloneLink `
			-Organization $Organization `
			-Project $Project `
			-SourceTestCaseId $cloneResult.SourceTestCaseId `
			-ClonedTestCaseId $cloneResult.ClonedTestCaseId `
			-SourcePrefix $sourcePrefix `
			-Headers $Headers


        $clonedTestCaseIds +=
            [int]$cloneResult.ClonedTestCaseId
    }
}


# ============================================================
# SUMMARY
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "DONE"
Write-Host "============================================================"

Write-Host `
    "Directing testcases read : $($directingTestCases.Count)"

Write-Host `
    "Logical IDs requested    : $($wantedLogicalIds.Count)"

Write-Host `
    "Source testcases matched : $($matches.Count)"

Write-Host `
    "Testcases cloned         : $($clonedTestCaseIds.Count)"

Write-Host `
    "Logical IDs missing      : $($missingLogicalIds.Count)"

Write-Host "============================================================"
Write-Host ""

Read-Host "Press ENTER to close"