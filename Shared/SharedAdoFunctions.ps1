# ADO shared library entry point.
# Loads supporting functions and defines only complete workflow orchestrators.
# Callers can continue dot-sourcing this file as before.
# The function implementations below are unchanged from the source library.

$__adoSupportFiles = @(
    'AdoConfiguration.ps1'
    'AdoUtilities.ps1'
    'AdoSuites.ps1'
    'AdoTestCases.ps1'
    'AdoCloning.ps1'
    'AdoImport.ps1'
    'AdoTestExecution.ps1'
    'AdoReporting.ps1'
)

# Validate all dependencies before loading any of them.
foreach ($__adoSupportFile in $__adoSupportFiles) {
    $__adoSupportPath = Join-Path -Path $PSScriptRoot -ChildPath $__adoSupportFile
    if (-not (Test-Path -LiteralPath $__adoSupportPath -PathType Leaf)) {
        throw "Missing ADO support library file: $__adoSupportPath"
    }
}

foreach ($__adoSupportFile in $__adoSupportFiles) {
    $__adoSupportPath = Join-Path -Path $PSScriptRoot -ChildPath $__adoSupportFile
    . $__adoSupportPath
}

Remove-Variable -Name __adoSupportFiles, __adoSupportFile, __adoSupportPath -ErrorAction SilentlyContinue

# Complete, externally callable workflows: definitions are preserved verbatim.

function Clone-TestCases {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [int]$SourcePlanId,

        [int]$DestinationPlanId,

        [Parameter(Mandatory)]
        [int]$SourceSuiteId,

        [Parameter(Mandatory)]
        [int]$DestinationSuiteId,

        [ValidateRange(1, 4)]
        [int]$Priority,

        [string]$Outcome,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$ExcludeTSInSuite,
        
        [string[]]$ExcludeLogicalIds,

        [switch]$SkipExisting,

        [int]$ExcludePlanId,

        [switch]$PreserveStructure,

        [switch]$IncludeAttachments,

        [switch]$IncludeLinks,

        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    if (-not $PSBoundParameters.ContainsKey('DestinationPlanId')) {
        $DestinationPlanId = $SourcePlanId
    }

    if (-not $PSBoundParameters.ContainsKey('ExcludePlanId')) {
        $ExcludePlanId = $SourcePlanId
    }

    try {

        # Retrieve test cases
        Write-Host "Retrieving test cases..."

        $testCases = @(
            Get-TestCasesInSuite `
                -Organization $Organization `
                -Project $Project `
                -PlanId $SourcePlanId `
                -SuiteId $SourceSuiteId `
                -Headers $Headers `
                -IncludeSubSuites
        )

        Write-Host "Retrieved $($testCases.Count) test cases."

        # Retrieve execution results only when filtering by outcome
        if ($PSBoundParameters.ContainsKey('Outcome')) {

            Write-Host "Retrieving latest execution results..."

            $testPoints = @(
                foreach ($suiteId in ($testCases.SuiteId | Sort-Object -Unique)) {
                    Get-SuiteTestPointOutcomes `
                        -Organization $Organization `
                        -Project $Project `
                        -PlanId $SourcePlanId `
                        -SuiteId $suiteId `
                        -Headers $Headers `
                        -ErrorAction Stop
                }
            )

            $testCases = @(
                Add-TestCaseOutcomes `
                    -TestCases $testCases `
                    -TestPoints $testPoints
            )

            Write-Host "Execution results retrieved."
        }

        $allExcludedLogicalIds = @($ExcludeLogicalIds)

        # 1. Existing optional exclusion suite
        if ($PSBoundParameters.ContainsKey('ExcludeTSInSuite')) {

            Write-Host "Retrieving exclusion suite $ExcludeTSInSuite from plan $ExcludePlanId..."

            $excludeTestCases = @(
                Get-TestCasesInSuite `
                    -Organization $Organization `
                    -Project $Project `
                    -PlanId $ExcludePlanId `
                    -SuiteId $ExcludeTSInSuite `
                    -Headers $Headers `
                    -IncludeSubSuites
            )

            $allExcludedLogicalIds += @(
                $excludeTestCases |
                    Get-TestCaseLogicalId |
                    Select-Object -ExpandProperty LogicalId -Unique
            )
        }

        # 2. Existing test cases in destination hierarchy
        if ($SkipExisting) {

            Write-Host "Retrieving existing test cases from destination suite $DestinationSuiteId..."

            $existingTestCases = @(
                Get-TestCasesInSuite `
                    -Organization $Organization `
                    -Project $Project `
                    -PlanId $DestinationPlanId `
                    -SuiteId $DestinationSuiteId `
                    -Headers $Headers `
                    -IncludeSubSuites
            )

            $allExcludedLogicalIds += @(
                $existingTestCases |
                    Get-TestCaseLogicalId |
                    Select-Object -ExpandProperty LogicalId -Unique
            )
        }

        # 3. Remove empty values and duplicate IDs
        $allExcludedLogicalIds = @(
            $allExcludedLogicalIds |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )

        Write-Host "Found $($allExcludedLogicalIds.Count) distinct logical test case IDs to exclude."

        # Apply optional filters
        Write-Host "Selecting test cases..."

        $filters = @{}

        if ($PSBoundParameters.ContainsKey('Priority')) {
            $filters.Priority = $Priority
        }

        if ($PSBoundParameters.ContainsKey('Outcome')) {
            $filters.Outcome = $Outcome
        }

        if ($allExcludedLogicalIds.Count -gt 0) {
            $filters.ExcludeLogicalIds = $allExcludedLogicalIds
        }

        $selected = @(
            $testCases | Select-TestCases @filters
        )

        Write-Host "Selected $($selected.Count) test cases."

        if ($selected.Count -eq 0) {
            Write-Warning "No matching test cases found. Nothing to clone."
        }

        $cloneResults = @()

        # Clone by source suite
        foreach ($group in ($selected | Group-Object SuiteId)) {

            $sourceId = [int]$group.Name
            $targetId = $DestinationSuiteId
            $groupTestCases = @($group.Group)

            # Resolve destination when preserving structure
            if ($PreserveStructure) {

                $pathParts = @(
                    $groupTestCases[0].SuitePath -split '\s*>\s*'
                )

                $relativePath = @(
                    $pathParts | Select-Object -Skip 1
                )

                $targetId = Get-OrCreateTestSuitePath `
                    -Organization $Organization `
                    -Project $Project `
                    -PlanId $DestinationPlanId `
                    -ParentSuiteId $DestinationSuiteId `
                    -SuitePath $relativePath `
                    -Headers $Headers

                if ($targetId -le 0) {
                    throw "Could not resolve destination for source suite $sourceId."
                }
            }

            $ids = @(
                $groupTestCases |
                    Select-Object -ExpandProperty TestCaseId
            )

            Write-Host "Cloning $($ids.Count) test cases from suite $sourceId to $targetId..."

            Write-Host "DEBUG SourcePlanId      : $SourcePlanId"
            Write-Host "DEBUG DestinationPlanId : $DestinationPlanId"
            Write-Host "DEBUG SourceSuiteId     : $sourceId"
            Write-Host "DEBUG TargetSuiteId     : $targetId"

            $batchResults = @(
                Clone-TestCasesToSuite `
                    -Organization $Organization `
                    -Project $Project `
                    -SourcePlanId $SourcePlanId `
                    -SourceSuiteId $sourceId `
                    -TargetPlanId $DestinationPlanId `
                    -TargetSuiteId $targetId `
                    -TestCaseIds $ids `
                    -IncludeAttachments:$IncludeAttachments `
                    -IncludeLinks:$IncludeLinks `
                    -Headers $Headers
            )

            $cloneResults += $batchResults

            Write-Host "Completed suite $sourceId."
        }

        Write-Host "Cloning completed: $($cloneResults.Count) test cases."

        return [PSCustomObject]@{
            SourceCount   = $testCases.Count
            SelectedCount = $selected.Count
            ClonedCount   = $cloneResults.Count
            ClonedCases   = $cloneResults
        }
    }
    catch {
        Write-Host ""
        Write-Host "CLONE FAILURE DIAGNOSTICS" -ForegroundColor Red
        Write-Host "Exception: $($_.Exception.Message)"

        Write-Host ""
        Write-Host "Script stack trace:"
        Write-Host $_.ScriptStackTrace

        Write-Host ""
        Write-Host "Error location:"
        Write-Host $_.InvocationInfo.PositionMessage

        if ($_.ErrorDetails.Message) {
            Write-Host "ADO response:"
            Write-Host $_.ErrorDetails.Message
        }

        throw
    }
}

function Import-TestCasesFromFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [int]$PlanId,

        [Parameter(Mandatory)]
        [string]$FolderPath,

        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    try {
        # Find input files
        $files = @(
            Get-ChildItem `
                -Path $FolderPath `
                -Filter "*.txt" `
                -File `
                -ErrorAction Stop
        )

        Write-Host "Found $($files.Count) test case files."

        $results = @()

        $encodedProject = [uri]::EscapeDataString($Project)
        $createUrl = "https://dev.azure.com/$Organization/$encodedProject/_apis/wit/workitems/`$Test%20Case?api-version=7.1"

        foreach ($file in $files) {
            try {
                Write-Host ""
                Write-Host "Processing: $($file.Name)"

                # Read and validate test case data
                $data = Read-TestCaseTextFile `
                    -Path $file.FullName

                $validated = Validate-TestCaseData `
                    -Data $data `
                    -Organization $Organization `
                    -Project $Project `
                    -PlanId $PlanId `
                    -Headers $Headers

                $suiteId = $validated.SuiteId

                # Prepare test case information
                $externalReferenceId = $data["ExternalReferenceID"].Trim()
                $name = $data["Name"].Trim()
                $title = "$externalReferenceId - $name"

                $stepsXml = Convert-StepsToAdoXml `
                    -StepsText $data["Steps"]

                $descriptionHtml = "<pre>$([System.Security.SecurityElement]::Escape($data["Description"].Trim()))</pre>"

                $json = CreateAdoJson `
                    -Data $data `
                    -Title $title `
                    -ExternalReferenceId $externalReferenceId `
                    -DescriptionHtml $descriptionHtml `
                    -StepsXml $stepsXml

                # Find or create test case
                $testCaseId = Get-OrCreateTestCase `
                    -ExternalReferenceId $externalReferenceId `
                    -Json $json `
                    -CreateUrl $createUrl `
                    -Headers $Headers `
                    -Organization $Organization `
                    -Project $Project

                Write-Host "Using Test Case ID: $testCaseId"

                # Add test case to destination suite
                Add-TestCaseToSuite `
                    -Organization $Organization `
                    -Project $Project `
                    -PlanId $PlanId `
                    -SuiteId $suiteId `
                    -TestCaseId $testCaseId `
                    -Headers $Headers | Out-Null

                $results += [PSCustomObject]@{
                    FileName            = $file.Name
                    ExternalReferenceId = $externalReferenceId
                    TestCaseId          = $testCaseId
                    SuiteId             = $suiteId
                }

                Write-Host "Completed: $($file.Name)"
            }
            catch {
                throw "Failed processing '$($file.Name)': $($_.Exception.Message)"
            }
        }

        Write-Host ""
        Write-Host "Import completed: $($results.Count) test cases."

        return $results
    }
    catch {
        throw "Import-TestCasesFromFolder failed: $($_.Exception.Message)"
    }
}

function Export-TestReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int]$PlanId,

        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int]$SuiteId,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    # All ADO calls happen before Excel generation.
    $suite = Get-TestSuite -Organization $Organization -Project $Project `
        -PlanId $PlanId -SuiteId $SuiteId -Headers $Headers
    if ($null -eq $suite -or [string]::IsNullOrWhiteSpace($suite.name)) {
        throw "Suite $SuiteId was not returned with a valid name by ADO."
    }

    $points = @(Get-SuiteTestPointOutcomes -Organization $Organization `
        -Project $Project -PlanId $PlanId -SuiteId $SuiteId -Headers $Headers)
    if ($points.Count -eq 0) {
        throw "Suite $SuiteId ('$($suite.name)') contains no directly assigned test points. No report was written."
    }

    $links = @(Get-TestResultDefects -Organization $Organization `
        -Project $Project -TestPoints $points -Headers $Headers)

    $results = @(ConvertTo-TestResultReport -TestPoints $points -LinkedDefects $links)
    $defectDetails = @(Get-TestDefectDetails -TestResults $results `
        -Organization $Organization -Project $Project -Headers $Headers)
    $summary = Get-TestResultSummary -TestResults $results

    Export-TestExecutionReport -TestResults $results -Summary $summary `
        -DefectDetails $defectDetails -SuiteName ([string]$suite.name) `
        -SuiteId $SuiteId -Organization $Organization -Project $Project `
        -OutputPath $OutputPath

    Write-Host "Report created: $OutputPath"
    Write-Host "Test points: $($results.Count); linked defect records: $($defectDetails.Count)"
}
