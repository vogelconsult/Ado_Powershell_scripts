function ConvertTo-TestResultReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$TestPoints,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$LinkedDefects = @()
    )

    $defectsByPointId = @{}
    foreach ($link in $LinkedDefects) {
        $key = [string]$link.TestPointId
        if ($defectsByPointId.ContainsKey($key)) {
            throw "Duplicate defect association for test point $key."
        }
        $defectsByPointId[$key] = @($link.DefectIds)
    }

    foreach ($point in $TestPoints) {
        $titleField = $point.workItemProperties |
            Where-Object { $_.workItem.key -eq 'System.Title' } |
            Select-Object -First 1

        $title = [string]$titleField.workItem.value
        if ([string]::IsNullOrWhiteSpace($title)) {
            throw "System.Title was not returned for test point $($point.id)."
        }

        $pointKey = [string]$point.id
        $ids = @()
        if ($defectsByPointId.ContainsKey($pointKey)) {
            $ids = @($defectsByPointId[$pointKey] |
                Where-Object { $null -ne $_ } |
                ForEach-Object { [int]$_ } |
                Sort-Object -Unique)
        }

        [PSCustomObject]@{
            TestCaseId    = [int]$point.testCase.id
            Title         = $title
            Outcome       = [string]$point.outcome
            Defects       = $ids -join '; '
            DefectIds     = [int[]]$ids  # Internal data; not an Excel column
            State         = [string]$point.state
            Configuration = [string]$point.configuration.name
            Tester        = [string]$point.assignedTo.displayName
            TestPointId   = [int]$point.id
            LastRunId     = $point.lastTestRun.id
        }
    }
}

function Export-TestResultsToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$TestResults,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $TestResults |
        Export-Csv `
            -Path $OutputPath `
            -Delimiter ';' `
            -NoTypeInformation `
            -Encoding UTF8
}

function Get-TestResultSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$TestResults
    )

    $passed = @($TestResults | Where-Object {
        $_.Outcome -eq 'Passed'
    }).Count

    $failed = @($TestResults | Where-Object {
        $_.Outcome -eq 'Failed'
    }).Count

    $notApplicable = @($TestResults | Where-Object {
        $_.Outcome -eq 'NotApplicable'
    }).Count

    $paused = @($TestResults | Where-Object {
        $_.Outcome -eq 'Paused'
    }).Count

    $executed = $passed + $failed

    $passRate = if ($executed -gt 0) {
        [math]::Round(100 * $passed / $executed, 1)
    }
    else {
        $null
    }

    [PSCustomObject]@{
        Total         = $TestResults.Count
        Passed        = $passed
        Failed        = $failed
        NotApplicable = $notApplicable
        Paused        = $paused
        Executed      = $executed
        PassRate      = $passRate
    }
}

function Export-TestSummarySheet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Summary,

        [Parameter(Mandatory)]
        [string]$SuiteName,

        [Parameter(Mandatory)]
        [int]$SuiteId,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $rows = @(
        [PSCustomObject]@{ Metric = 'Suite Name'; Value = $SuiteName }
        [PSCustomObject]@{ Metric = 'Suite ID'; Value = $SuiteId }
        [PSCustomObject]@{ Metric = 'Generated'; Value = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
        [PSCustomObject]@{ Metric = 'Total'; Value = $Summary.Total }
        [PSCustomObject]@{ Metric = 'Passed'; Value = $Summary.Passed }
        [PSCustomObject]@{ Metric = 'Failed'; Value = $Summary.Failed }
        [PSCustomObject]@{ Metric = 'Not Applicable'; Value = $Summary.NotApplicable }
        [PSCustomObject]@{ Metric = 'Paused'; Value = $Summary.Paused }
        [PSCustomObject]@{ Metric = 'Executed'; Value = $Summary.Executed }
        [PSCustomObject]@{ Metric = 'Pass Rate (%)'; Value = $Summary.PassRate }
    )

    $rows | Export-Excel -Path $OutputPath -WorksheetName 'Summary' `
        -AutoSize -BoldTopRow -ErrorAction Stop
}

function Export-TestResultsSheet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$TestResults,

        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    # Explicit columns: the internal DefectIds array must not become an Excel column.
    $rows = @(
        foreach ($test in $TestResults) {
            [PSCustomObject]@{
                TestCaseId    = $test.TestCaseId
                Title         = $test.Title
                Outcome       = $test.Outcome
                Defects       = $test.Defects
                State         = $test.State
                Configuration = $test.Configuration
                Tester        = $test.Tester
                TestPointId   = $test.TestPointId
                LastRunId     = $test.LastRunId
            }
        }
    )

    $rows | Export-Excel -Path $OutputPath -WorksheetName 'Test Results' `
        -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -ErrorAction Stop

    # An Excel cell can have only one hyperlink. Link single-defect cells;
    # leave multi-defect cells as IDs, with separate links in the Defects sheet.
    $encodedProject = [uri]::EscapeDataString($Project)
    $baseUrl = "https://dev.azure.com/$Organization/$encodedProject"
    $package = Open-ExcelPackage -Path $OutputPath
    try {
        $ws = $package.Workbook.Worksheets['Test Results']
        $row = 2
        foreach ($test in $TestResults) {
            $ids = @($test.DefectIds | Where-Object { $null -ne $_ })
            if ($ids.Count -eq 1) {
                $ws.Cells[$row,4].Hyperlink = [uri]"$baseUrl/_workitems/edit/$($ids[0])"
            }
            $row++
        }
    }
    finally {
		Close-ExcelPackage $package -ErrorAction Stop
	}
}

function Export-TestDefectsSheet {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$DefectDetails = @(),

        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $encodedProject = [uri]::EscapeDataString($Project)
    $baseUrl = "https://dev.azure.com/$Organization/$encodedProject"
    $package = Open-ExcelPackage -Path $OutputPath

    try {
        $ws = $package.Workbook.Worksheets.Add('Defects')

        $ws.Cells[1,1].Value = 'Defect ID'
        $ws.Cells[1,2].Value = 'Defect Title'
        $ws.Cells[1,3].Value = 'State'
        $ws.Cells[1,4].Value = 'Bug Priority'
        $ws.Cells[1,5].Value = 'Testcase ID'

        $row = 2
        foreach ($defect in $DefectDetails) {
            $ws.Cells[$row,1].Value = [int]$defect.DefectId
            $ws.Cells[$row,2].Value = [string]$defect.DefectTitle
            $ws.Cells[$row,3].Value = [string]$defect.State
            $ws.Cells[$row,4].Value = [string]$defect.BugPriority
            $ws.Cells[$row,5].Value = [int]$defect.TestCaseId

            $ws.Cells[$row,1].Hyperlink = [uri]"$baseUrl/_workitems/edit/$($defect.DefectId)"
            $row++
        }

        $ws.Cells['A1:E1'].Style.Font.Bold = $true
        $ws.Column(1).Width = 16
        $ws.Column(2).Width = 90
        $ws.Column(3).Width = 20
        $ws.Column(4).Width = 18
        $ws.Column(5).Width = 18
        if ($row -gt 2) {
            $ws.Cells["A1:E$($row - 1)"].AutoFilter = $true
        }
        $ws.View.FreezePanes(2, 1)
    }
    finally {
        Close-ExcelPackage $package
    }
}

function Export-TestExecutionReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$TestResults,

        [Parameter(Mandatory)]
        [object]$Summary,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$DefectDetails = @(),

        [Parameter(Mandatory)]
        [string]$SuiteName,

        [Parameter(Mandatory)]
        [int]$SuiteId,

        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    Import-Module ImportExcel -ErrorAction Stop

    if ([IO.Path]::GetExtension($OutputPath) -ne '.xlsx') {
        throw "OutputPath must be an .xlsx file: $OutputPath"
    }

    $targetPath = [IO.Path]::GetFullPath($OutputPath)
    $directory = [IO.Path]::GetDirectoryName($targetPath)
    if (-not [IO.Directory]::Exists($directory)) {
        throw "Output directory does not exist: $directory"
    }

    # Stage all sheets in a temporary workbook. Keep the previous report
    # intact if an API, Excel or formatting step fails.
    $stem = [IO.Path]::GetFileNameWithoutExtension($targetPath)
    $tempPath = Join-Path $directory ("{0}_{1}.xlsx" -f $stem, [guid]::NewGuid().ToString('N'))

    try {
        Export-TestSummarySheet -Summary $Summary -SuiteName $SuiteName `
            -SuiteId $SuiteId -OutputPath $tempPath

        Export-TestResultsSheet -TestResults $TestResults `
            -Organization $Organization -Project $Project -OutputPath $tempPath

        Export-TestDefectsSheet -DefectDetails $DefectDetails `
            -Organization $Organization -Project $Project -OutputPath $tempPath

        # Atomic replacement on the same volume prevents a failed build
        # from destroying a previously successful report.
        if ([IO.File]::Exists($targetPath)) {

			# Create a temporary backup path for atomic replacement
			$backupPath = Join-Path $directory (
				"{0}_backup_{1}.bak" -f
				$stem,
				[guid]::NewGuid().ToString('N')
			)

			[IO.File]::Replace($tempPath, $targetPath, $backupPath)

			# Remove backup after successful replacement
			if ([IO.File]::Exists($backupPath)) {
				[IO.File]::Delete($backupPath)
			}
		}
		else {
			[IO.File]::Move($tempPath, $targetPath)
		}
    }
    finally {
        if ([IO.File]::Exists($tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-TestDefectDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$TestResults,

        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    # The report objects keep typed defect IDs; never parse Excel formulas.
    $seenLinks = @{}
    $links = @(
        foreach ($test in $TestResults) {
            if ($test.Outcome -ne 'Failed') { continue }
            if ($null -eq $test.PSObject.Properties['DefectIds']) {
                throw "Test result $($test.TestCaseId) has no DefectIds property."
            }

            foreach ($id in @($test.DefectIds)) {
                if ($null -eq $id) { continue }
                $bugId = [int]$id
                $caseId = [int]$test.TestCaseId
                $key = "${bugId}:${caseId}"
                if ($seenLinks.ContainsKey($key)) { continue }
                $seenLinks[$key] = $true
                [PSCustomObject]@{ DefectId = $bugId; TestCaseId = $caseId }
            }
        }
    )

    if ($links.Count -eq 0) {
        Write-Verbose 'No linked defects to enrich.'
        return
    }

    $uniqueIds = @($links | Select-Object -ExpandProperty DefectId | Sort-Object -Unique)
    $encodedProject = [uri]::EscapeDataString($Project)
    $baseUrl = "https://dev.azure.com/$Organization/$encodedProject"
    $byId = @{}

    # Azure DevOps Work Items List API allows at most 200 IDs per request.
    for ($i = 0; $i -lt $uniqueIds.Count; $i += 200) {
        $batch = @($uniqueIds | Select-Object -Skip $i -First 200)
        $idList = $batch -join ','
        $url = "$baseUrl/_apis/wit/workitems?ids=$idList" +
               '&fields=System.Title,System.State,Custom.BugPriority&api-version=7.1'

        Write-Verbose "Retrieving $($batch.Count) defect work items from ADO."
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $Headers -ErrorAction Stop
        foreach ($item in @($response.value)) {
            if ($null -ne $item) {
                $byId[[string]$item.id] = $item
            }
        }
    }

    foreach ($link in $links) {
        $item = $byId[[string]$link.DefectId]
        if ($null -eq $item) {
            throw "Defect $($link.DefectId) was not returned by ADO."
        }

        [PSCustomObject]@{
            DefectId    = [int]$link.DefectId
            DefectTitle = [string]$item.fields.'System.Title'
            State       = [string]$item.fields.'System.State'
            BugPriority = [string]$item.fields.'Custom.BugPriority'
            TestCaseId  = [int]$link.TestCaseId
        }
    }
}

