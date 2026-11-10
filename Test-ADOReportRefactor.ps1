# Offline smoke test for the refactored ADO report.
# Does not ask for a PAT or connect to Azure DevOps.
# Requires the ImportExcel module to validate the generated workbook.
$ErrorActionPreference = 'Stop'

function Assert-ReportTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
}

# Parse both scripts using the native PowerShell parser (PowerShell 5.1 or newer).
foreach ($file in @(
    (Join-Path $PSScriptRoot 'Shared\SharedAdoFunctions.ps1'),
    (Join-Path $PSScriptRoot 'Export-TestReport.ps1')
)) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $file, [ref]$tokens, [ref]$parseErrors
    )
    if (@($parseErrors).Count -gt 0) {
        $parseErrors | Format-Table -AutoSize | Out-Host
        throw "PowerShell syntax errors in $file"
    }
}
Write-Host 'PASS: Both scripts parse successfully.'

. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"
Import-Module ImportExcel -ErrorAction Stop

$script:ResultLookupCount = 0
$script:WorkItemLookupCount = 0

function New-MockTestPoint {
    param([int]$PointId, [int]$CaseId, [string]$Title,
          [string]$Outcome, [int]$RunId, [int]$ResultId)

    [PSCustomObject]@{
        id = $PointId
        testCase = [PSCustomObject]@{ id = [string]$CaseId }
        outcome = $Outcome
        state = $(if ($Outcome -eq 'Failed') { 'NotReady' } else { 'Completed' })
        lastTestRun = [PSCustomObject]@{ id = [string]$RunId }
        lastResult = [PSCustomObject]@{ id = [string]$ResultId }
        configuration = [PSCustomObject]@{ name = 'Windows 10' }
        assignedTo = [PSCustomObject]@{ displayName = 'Mock Tester' }
        workItemProperties = @(
            [PSCustomObject]@{
                workItem = [PSCustomObject]@{ key = 'System.Title'; value = $Title }
            }
        )
    }
}

$script:MockPoints = @(
    (New-MockTestPoint 169783 76387 'First failed test' 'Failed' 26826 100001),
    (New-MockTestPoint 169782 76386 'Passed test' 'Passed' 26827 100002),
    (New-MockTestPoint 169784 76388 'Multiple linked bugs' 'Failed' 26828 100003)
)

# This mock shadows Invoke-RestMethod for report functions in this test only.
function Invoke-RestMethod {
    [CmdletBinding()]
    param([string]$Uri, [string]$Method, [hashtable]$Headers)

    if ($Uri -match '/_apis/testplan/Plans/1/suites/(\d+)\?') {
        $name = switch ($Matches[1]) {
            '76361' { 'All Passed' }
            '76362' { 'Missing Result Metadata' }
            default { 'Regression other' }
        }
        return [PSCustomObject]@{ id = $Matches[1]; name = $name }
    }
    if ($Uri -match '/_apis/test/Plans/1/Suites/(\d+)/points\?') {
        $requestedSuiteId = $Matches[1]
        Assert-ReportTest ($Uri -match 'witFields=System.Title') 'Test point request must include System.Title'
        if ($requestedSuiteId -eq '76361') {
            $value = @($script:MockPoints[1])
        }
        elseif ($requestedSuiteId -eq '76362') {
            $value = @((New-MockTestPoint 999999 80000 'Missing run reference' 'Failed' 0 0))
        }
        else {
            $value = $script:MockPoints
        }
        return [PSCustomObject]@{ value = $value }
    }
    if ($Uri -match '/_apis/test/Runs/26826/results/100001\?') {
        $script:ResultLookupCount++
        return [PSCustomObject]@{ associatedBugs = @([PSCustomObject]@{ id = 77560 }) }
    }
    if ($Uri -match '/_apis/test/Runs/26828/results/100003\?') {
        $script:ResultLookupCount++
        return [PSCustomObject]@{ associatedBugs = @(
            [PSCustomObject]@{ id = 77635 },
            [PSCustomObject]@{ id = 77568 }
        ) }
    }
    if ($Uri -match '/_apis/wit/workitems\?') {
        $script:WorkItemLookupCount++
        Assert-ReportTest ($Uri -match 'Custom.BugPriority') 'Custom Bug Priority field must be requested'
        return [PSCustomObject]@{ value = @(
            [PSCustomObject]@{ id = 77560; fields = [PSCustomObject]@{
                'System.Title' = 'Payment failure'; 'System.State' = 'Active';
                'Custom.BugPriority' = 'Major' } },
            [PSCustomObject]@{ id = 77568; fields = [PSCustomObject]@{
                'System.Title' = 'Porting failure'; 'System.State' = 'Resolved';
                'Custom.BugPriority' = 'Minor' } },
            [PSCustomObject]@{ id = 77635; fields = [PSCustomObject]@{
                'System.Title' = 'Customer error'; 'System.State' = 'New';
                'Custom.BugPriority' = 'Showstopper' } }
        ) }
    }
    throw "Unexpected ADO request: $Uri"
}

$firstFile = Join-Path ([IO.Path]::GetTempPath()) ("ADO_TestReport_{0}.xlsx" -f [guid]::NewGuid().ToString('N'))

try {
    $params = @{
        Organization = 'TelenorDenmark-Prod'
        Project = 'Telenor Denmark'
        Headers = @{ Authorization = 'mock-only' }
        PlanId = 1
        OutputPath = $firstFile
    }

    Export-TestReport @params -SuiteId 76360
    Assert-ReportTest ($script:ResultLookupCount -eq 2) 'Only failed test points should be queried for bugs'
    Assert-ReportTest ($script:WorkItemLookupCount -eq 1) 'Three defects should be enriched with one work item request'

    $package = Open-ExcelPackage -Path $firstFile
    try {
        $summary = $package.Workbook.Worksheets['Summary']
        $results = $package.Workbook.Worksheets['Test Results']
        $defects = $package.Workbook.Worksheets['Defects']
        Assert-ReportTest ($package.Workbook.Worksheets.Count -eq 3) 'Report must have three sheets'
        Assert-ReportTest ($summary.Cells[2,2].Value -eq 'Regression other') 'Summary suite name'
        Assert-ReportTest ($summary.Cells[7,2].Value -eq 2) 'Summary failed count'
        $passRateCell = $summary.Cells[11,2]
        $actualPassRate = [double]$passRateCell.Value
        Assert-ReportTest ([math]::Abs($actualPassRate - 33.3) -lt 0.01) 'Summary pass rate'
        Assert-ReportTest ($results.Cells[2,4].Value -eq '77560') 'Single defect ID retained in results'
        Assert-ReportTest ($null -ne $results.Cells[2,4].Hyperlink) 'Single defect is clickable'
        Assert-ReportTest ($results.Cells[4,4].Value -eq '77568; 77635') 'Multiple defects retained in results'
        Assert-ReportTest ($null -eq $results.Cells[4,4].Hyperlink) 'Multiple IDs must not link misleadingly to one defect'
        Assert-ReportTest ($defects.Cells[1,3].Value -eq 'State') 'State column follows Title'
        Assert-ReportTest ($defects.Cells[1,4].Value -eq 'Bug Priority') 'Custom priority column'
        $ids = @($defects.Cells[2,1].Value, $defects.Cells[3,1].Value, $defects.Cells[4,1].Value)
        Assert-ReportTest (($ids | Sort-Object) -join ',' -eq '77560,77568,77635') 'Three defect IDs in defect sheet'
        Assert-ReportTest ($null -ne $defects.Cells[2,1].Hyperlink) 'Defect ID is clickable'
    }
    finally { Close-ExcelPackage $package }
    Write-Host 'PASS: Linked defects, custom priority, state, summary and hyperlinks.'

    # Rebuild the SAME file with an all-passed suite, testing clean replacement.
    Export-TestReport @params -SuiteId 76361
    Assert-ReportTest ($script:ResultLookupCount -eq 2) 'All-passed suite must not trigger bug lookups'
    $package = Open-ExcelPackage -Path $firstFile
    try {
        $ws = $package.Workbook.Worksheets['Defects']
        Assert-ReportTest ($null -ne $ws) 'Empty defects sheet must exist'
        Assert-ReportTest ($ws.Cells[1,1].Value -eq 'Defect ID') 'Empty defects sheet must have headers'
        Assert-ReportTest ($null -eq $ws.Cells[2,1].Value) 'No stale defect entries after replacement'
        Assert-ReportTest ($package.Workbook.Worksheets['Summary'].Cells[2,2].Value -eq 'All Passed') 'Suite metadata refreshed on replacement'
    }
    finally { Close-ExcelPackage $package }
    Write-Host 'PASS: Existing report replaced cleanly by all-passed suite.'

    # An incomplete ADO test result must not overwrite a previously good report.
    $failedSafely = $false
    try {
        Export-TestReport @params -SuiteId 76362
    }
    catch {
        $failedSafely = $_.Exception.Message -match 'missing lastTestRun.id or lastResult.id'
    }
    Assert-ReportTest $failedSafely 'Missing result IDs must fail before report generation'
    $package = Open-ExcelPackage -Path $firstFile
    try {
        Assert-ReportTest ($package.Workbook.Worksheets['Summary'].Cells[2,2].Value -eq 'All Passed') 'Previous report must remain intact on ADO failure'
    }
    finally { Close-ExcelPackage $package }
    Write-Host 'PASS: Failed retrieval leaves existing report unchanged.'
}
finally {
    if (Test-Path -LiteralPath $firstFile) { Remove-Item -LiteralPath $firstFile -Force }
}

Write-Host 'ALL OFFLINE REPORT TESTS PASSED.' -ForegroundColor Green
