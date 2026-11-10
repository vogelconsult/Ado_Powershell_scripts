function Select-Folder {
    [CmdletBinding()]
    param(
        [string]$Description = "Select a folder",

        [string]$InitialPath = $PWD.Path
    )

    $folderPath = $null

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = $Description
        $dialog.ShowNewFolderButton = $false

        if (Test-Path -LiteralPath $InitialPath -PathType Container) {
            $dialog.SelectedPath = $InitialPath
        }

        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $folderPath = $dialog.SelectedPath
        }
    }
    catch {
        Write-Warning "Folder selection dialog unavailable."
    }
    finally {
        if ($null -ne $dialog) {
            $dialog.Dispose()
        }
    }

    # Manual entry if dialog is unavailable or cancelled
    if ([string]::IsNullOrWhiteSpace($folderPath)) {
        $folderPath = Read-Host "Enter full folder path"
    }

    if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
        throw "Folder does not exist: $folderPath"
    }

    return (Resolve-Path -LiteralPath $folderPath).ProviderPath
}

function Get-ExcludedTestCaseIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Exclusion file not found: $Path"
    }

    $rows = @(
        Import-Csv -LiteralPath $Path `
            -Delimiter ';' `
            -ErrorAction Stop
    )

    if ($rows.Count -eq 0) {
        throw "Exclusion file contains no data: $Path"
    }

    if (-not ($rows[0].PSObject.Properties.Name -contains 'TestCase')) {
        throw "Exclusion file must contain a TestCase column."
    }

    $ids = foreach ($row in $rows) {

        $title = ([string]$row.TestCase).Trim()

        if ([string]::IsNullOrWhiteSpace($title)) {
            continue
        }

        $testCase = [PSCustomObject]@{
            Title     = $title
            SuitePath = ''
        }

        $logicalId = Get-TestCaseLogicalId -TestCase $testCase

        if (-not $logicalId -or
            [string]::IsNullOrWhiteSpace($logicalId.LogicalId)) {
            throw "Could not extract logical ID from '$title'"
        }

        $logicalId.LogicalId
    }

    @($ids | Sort-Object -Unique)
}

