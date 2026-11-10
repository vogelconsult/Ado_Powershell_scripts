function Get-SuiteTestPointOutcomes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [int]$PlanId,

        [Parameter(Mandatory)]
        [int]$SuiteId,

        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    $encodedProject = [uri]::EscapeDataString($Project)
    $baseUrl = "https://dev.azure.com/$Organization/$encodedProject"

    $points = @()
    $skip = 0
    $pageSize = 1000

    do {
        $url = "$baseUrl/_apis/test/Plans/$PlanId/Suites/$SuiteId/points?witFields=System.Title&includePointDetails=true&`$skip=$skip&`$top=$pageSize&api-version=7.1"

        $response = Invoke-RestMethod `
            -Uri $url `
            -Method Get `
            -Headers $Headers `
            -ErrorAction Stop

        $batch = @($response.value | Where-Object { $null -ne $_ })
        $points += $batch
        $skip += $batch.Count

    } while ($batch.Count -eq $pageSize)

    return $points
}

function Add-TestCaseOutcomes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$TestCases,

        [Parameter(Mandatory)]
        [array]$TestPoints
    )

    # Group test points by suite and test case
    $pointsByTestCase = @{}

    foreach ($point in $TestPoints) {
        $key = "$($point.suite.id):$($point.testCase.id)"

        if (-not $pointsByTestCase.ContainsKey($key)) {
            $pointsByTestCase[$key] = @()
        }

        $pointsByTestCase[$key] += $point
    }

    foreach ($testCase in $TestCases) {
        $key = "$($testCase.SuiteId):$($testCase.TestCaseId)"

        $outcome = $null
        $completedDate = $null

        if ($pointsByTestCase.ContainsKey($key)) {

            $latestPoint = $pointsByTestCase[$key] |
                Where-Object {
                    $_.lastResultDetails.dateCompleted
                } |
                Sort-Object -Property @{
                    Expression = {
                        [datetimeoffset]$_.lastResultDetails.dateCompleted
                    }
                    Descending = $true
                } |
                Select-Object -First 1

            if ($null -ne $latestPoint) {
                $outcome = $latestPoint.outcome
                $completedDate = $latestPoint.lastResultDetails.dateCompleted
            }
        }

        # Return a new object, preserving existing properties
        $testCase |
            Select-Object *,
                @{Name='Outcome'; Expression={$outcome}},
                @{Name='LastCompleted'; Expression={$completedDate}}
    }
}

function Get-TestResultDefects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [object[]]$TestPoints,

        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    $encodedProject = [uri]::EscapeDataString($Project)
    $baseUrl = "https://dev.azure.com/$Organization/$encodedProject"

    foreach ($point in $TestPoints) {
        $ids = @()

        # Only failed test points require another ADO API call.
        if ($point.outcome -eq 'Failed') {
            $runId = $point.lastTestRun.id
            $resultId = $point.lastResult.id

            if (-not $runId -or -not $resultId -or [int]$runId -le 0 -or [int]$resultId -le 0) {
                throw "Failed test point $($point.id) (testcase $($point.testCase.id)) is missing lastTestRun.id or lastResult.id. Linked defects cannot be verified."
            }

            $url = "$baseUrl/_apis/test/Runs/$runId/results/$resultId" +
                   '?detailsToInclude=WorkItems&api-version=7.1'

            Write-Verbose "Reading bugs for failed testcase $($point.testCase.id), run $runId, result $resultId."
            $result = Invoke-RestMethod -Uri $url -Method Get -Headers $Headers -ErrorAction Stop

            $ids = @($result.associatedBugs |
                Where-Object { $null -ne $_ -and $_.id } |
                ForEach-Object { [int]$_.id } |
                Sort-Object -Unique)

            Write-Verbose "Test point $($point.id): $($ids.Count) linked defects."
        }

        [PSCustomObject]@{
            TestPointId = [int]$point.id
            DefectIds   = [int[]]$ids
        }
    }
}

