function Clone-AllTestCasesInSuite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$SourcePlanId,

        [Parameter(Mandatory = $true)]
        [int]$SourceSuiteId,

        [Parameter(Mandatory = $true)]
        [int]$TargetPlanId,

        [Parameter(Mandatory = $true)]
        [int]$TargetSuiteId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [switch]$IncludeAttachments,

        [switch]$IncludeLinks
    )

    $encodedProject = [uri]::EscapeDataString($Project)
    $baseUrl = "https://dev.azure.com/$Organization/$encodedProject"

    # Get all test cases directly assigned to source suite
    $testCasesUrl =
        "$baseUrl/_apis/test/Plans/$SourcePlanId/Suites/$SourceSuiteId/testcases?api-version=7.1"

    $testCasesResponse = Invoke-RestMethod `
        -Uri $testCasesUrl `
        -Method Get `
        -Headers $Headers `
        -ErrorAction Stop

    $testCaseIds = @(
        $testCasesResponse.value |
            ForEach-Object { [int]$_.testCase.id }
    )

    Write-Host ""
    Write-Host "Source Plan        : $SourcePlanId"
    Write-Host "Source Suite       : $SourceSuiteId"
    Write-Host "Target Plan        : $TargetPlanId"
    Write-Host "Target Suite       : $TargetSuiteId"
    Write-Host "Test Cases         : $($testCaseIds.Count)"
    Write-Host "Copy Attachments   : $IncludeAttachments"
    Write-Host "Copy Links         : $IncludeLinks"
    Write-Host ""

    if ($testCaseIds.Count -eq 0) {
        Write-Host "No test cases found in source suite."
        return $null
    }

    # Start clone operation
    $cloneUrl =
        "$baseUrl/_apis/testplan/TestCases/CloneTestCaseOperation?api-version=7.1"

    $body = @{
        sourceTestPlan = @{
            id = $SourcePlanId
        }

        sourceTestSuite = @{
            id = $SourceSuiteId
        }

        destinationTestPlan = @{
            id = $TargetPlanId
        }

        destinationTestSuite = @{
            id = $TargetSuiteId
        }

        testCaseIds = $testCaseIds

        cloneOptions = @{
            includeAttachments = [bool]$IncludeAttachments
            includeLinks       = [bool]$IncludeLinks
        }
    } | ConvertTo-Json -Depth 10

    Write-Host "Starting clone operation..."

   try {
		$cloneResponse = Invoke-RestMethod `
			-Uri $cloneUrl `
			-Method Post `
			-Headers $Headers `
			-ContentType "application/json" `
			-Body $body `
			-ErrorAction Stop
	}
	catch {
		Write-Host "Clone API request failed" -ForegroundColor Red
		Write-Host "URL: $cloneUrl"
		Write-Host "Source: Plan $SourcePlanId, Suite $SourceSuiteId"
		Write-Host "Destination: Plan $TargetPlanId, Suite $TargetSuiteId"
		Write-Host "Test case: $sourceTestCaseId"
		Write-Host "Error: $($_.Exception.Message)"

		if ($_.ErrorDetails.Message) {
			Write-Host "Azure DevOps response:"
			Write-Host $_.ErrorDetails.Message
		}

		throw
	}

    return $cloneResponse
}

function Clone-TestCasesToSuite {
    param(
        [Parameter(Mandatory = $true)][string]$Organization,
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][int]$SourcePlanId,
        [Parameter(Mandatory = $true)][int]$SourceSuiteId,
        [Parameter(Mandatory = $true)][int]$TargetPlanId,
        [Parameter(Mandatory = $true)][int]$TargetSuiteId,
        [Parameter(Mandatory = $true)][int[]]$TestCaseIds,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [switch]$IncludeAttachments,
        [switch]$IncludeLinks
    )

    $results = @()
    $completed = 0
    $total = $TestCaseIds.Count

    foreach ($sourceTestCaseId in $TestCaseIds) {

        # Get destination test case IDs before cloning
        $beforeIds = @(
            Get-TestCaseIdsInSuite `
                -Organization $Organization `
                -Project $Project `
                -PlanId $TargetPlanId `
                -SuiteId $TargetSuiteId `
                -Headers $Headers `
                -ErrorAction Stop
        )

        $encodedProject = [uri]::EscapeDataString($Project)
        $baseUrl = "https://dev.azure.com/$Organization/$encodedProject"

        $cloneUrl =
            "$baseUrl/_apis/testplan/TestCases/CloneTestCaseOperation?api-version=7.1"

        $body = @{
            sourceTestPlan = @{
                id = $SourcePlanId
            }

            sourceTestSuite = @{
                id = $SourceSuiteId
            }

            destinationTestPlan = @{
                id = $TargetPlanId
            }

            destinationTestSuite = @{
                id = $TargetSuiteId
            }

            testCaseIds = @($sourceTestCaseId)

            cloneOptions = @{
                includeAttachments = [bool]$IncludeAttachments
                includeLinks       = [bool]$IncludeLinks
            }
        } | ConvertTo-Json -Depth 10

        Write-Progress `
            -Activity "Cloning test cases" `
            -Status "Cloning test case $sourceTestCaseId ($completed of $total completed)" `
            -PercentComplete (100 * $completed / $total)

        $step = "Submitting clone request"

        try {
            # Submit exactly one clone request
            $cloneResponse = Invoke-RestMethod `
                -Uri $cloneUrl `
                -Method Post `
                -Headers $Headers `
                -ContentType "application/json" `
                -Body $body `
                -ErrorAction Stop

            $operationId = [int]$cloneResponse.cloneOperationResponse.opId

            # Wait for the clone operation to complete
            $step = "Waiting for clone operation $operationId"

            Wait-TestCaseCloneOperation `
                -Organization $Organization `
                -Project $Project `
                -OperationId $operationId `
                -Headers $Headers `
                -ErrorAction Stop |
                Out-Null

            # Read destination test case IDs after cloning
            $step = "Reading destination suite after cloning"

            $afterIds = @(
                Get-TestCaseIdsInSuite `
                    -Organization $Organization `
                    -Project $Project `
                    -PlanId $TargetPlanId `
                    -SuiteId $TargetSuiteId `
                    -Headers $Headers `
                    -ErrorAction Stop
            )
        }
        catch {
            Write-Host ""
            Write-Host "Cloning failed during: $step" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)"

            if ($_.ErrorDetails.Message) {
                Write-Host "ADO response:"
                Write-Host $_.ErrorDetails.Message
            }

            throw
        }

        # Identify the newly cloned test case
        $newIds = @(
            $afterIds |
                Where-Object { $_ -notin $beforeIds }
        )

        if ($newIds.Count -ne 1) {
            throw "Expected exactly one clone of testcase $sourceTestCaseId, but found $($newIds.Count) new testcases: $($newIds -join ', ')."
        }

        $results += [PSCustomObject]@{
            SourceTestCaseId = $sourceTestCaseId
            ClonedTestCaseId = [int]$newIds[0]
        }

        $completed++
    }

    Write-Progress -Activity "Cloning test cases" -Completed

    return $results
}

function RecursiveCopyTestCasesInSuite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$SourcePlanId,

        [Parameter(Mandatory = $true)]
        [int]$SourceSuiteId,

        [Parameter(Mandatory = $true)]
        [int]$TargetPlanId,

        [Parameter(Mandatory = $true)]
        [int]$TargetSuiteId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [switch]$IncludeAttachments,

        [switch]$IncludeLinks
    )

    Write-Host ""
    Write-Host "============================================"
    Write-Host "Processing suite"
    Write-Host "Source Plan  : $SourcePlanId"
    Write-Host "Source Suite : $SourceSuiteId"
    Write-Host "Target Plan  : $TargetPlanId"
    Write-Host "Target Suite : $TargetSuiteId"
    Write-Host "============================================"
    Write-Host ""

    # Copy all test cases directly in this suite
	Clone-AllTestCasesInSuite `
		-Organization $Organization `
		-Project $Project `
		-SourcePlanId $SourcePlanId `
		-SourceSuiteId $SourceSuiteId `
		-TargetPlanId $TargetPlanId `
		-TargetSuiteId $TargetSuiteId `
		-Headers $Headers `
		-IncludeAttachments:$IncludeAttachments `
		-IncludeLinks:$IncludeLinks

    # Get direct child suites
    $children = @(Get-ChildTestSuites `
        -Organization $Organization `
        -Project $Project `
        -PlanId $SourcePlanId `
        -SuiteId $SourceSuiteId `
        -Headers $Headers)

    Write-Host ""
    Write-Host "Child suites found: $($children.Count)"
    Write-Host ""

    foreach ($child in $children) {

        Write-Host "Creating target suite for:"
        Write-Host "  $($child.name) [$($child.id)]"
        Write-Host ""

        $newChild = CreateStaticTestSuite `
            -Organization $Organization `
            -Project $Project `
            -PlanId $TargetPlanId `
            -ParentSuiteId $TargetSuiteId `
            -Name $child.name `
            -Headers $Headers

        Write-Host ""
        Write-Host "Created:"
        Write-Host "  $($newChild.name) [$($newChild.id)]"
        Write-Host ""

        RecursiveCopyTestCasesInSuite `
            -Organization $Organization `
            -Project $Project `
            -SourcePlanId $SourcePlanId `
            -SourceSuiteId ([int]$child.id) `
            -TargetPlanId $TargetPlanId `
            -TargetSuiteId ([int]$newChild.id) `
            -Headers $Headers `
            -IncludeAttachments:$IncludeAttachments `
            -IncludeLinks:$IncludeLinks
    }
}

function Wait-TestCaseCloneOperation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$OperationId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [int]$TimeoutSeconds = 120
    )

    $encodedProject = [uri]::EscapeDataString($Project)

    $url =
        "https://dev.azure.com/$Organization/$encodedProject/_apis/testplan/TestCases/CloneTestCaseOperation/$OperationId`?api-version=7.1"

    $startTime = Get-Date

    while ($true) {

        $status = Invoke-RestMethod `
            -Uri $url `
            -Method Get `
            -Headers $Headers `
            -ErrorAction Stop

        $state = $status.cloneOperationResponse.state

        if ($state -eq "succeeded") {
            return $status
        }

        if ($state -eq "failed") {

            throw `
                "Testcase clone operation $OperationId failed: $($status.cloneOperationResponse.message)"
        }

        if (((Get-Date) - $startTime).TotalSeconds -ge $TimeoutSeconds) {

            throw `
                "Timed out waiting for testcase clone operation $OperationId."
        }

        Start-Sleep -Seconds 1
    }
}

function Add-TestCaseCloneLink {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$SourceTestCaseId,

        [Parameter(Mandatory = $true)]
        [int]$ClonedTestCaseId,

        [Parameter(Mandatory = $true)]
        [string]$SourcePrefix,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    $encodedProject =
        [uri]::EscapeDataString($Project)

    $cloneUrl =
        "https://dev.azure.com/$Organization/$encodedProject/_apis/wit/workitems/$ClonedTestCaseId`?api-version=7.1"

    $sourceUrl =
        "https://dev.azure.com/$Organization/$encodedProject/_apis/wit/workItems/$SourceTestCaseId"

    $patchDocument = @(
        @{
            op    = "add"
            path  = "/relations/-"
            value = @{
                rel = "System.LinkTypes.Related"
                url = $sourceUrl
                attributes = @{
                    comment =
                        "Cloned from $SourcePrefix testcase $SourceTestCaseId"
                }
            }
        }
    )

    $body =
        ConvertTo-Json `
            -InputObject $patchDocument `
            -Depth 10

    Invoke-RestMethod `
        -Uri $cloneUrl `
        -Method Patch `
        -Headers $Headers `
        -ContentType "application/json-patch+json" `
        -Body $body `
        -ErrorAction Stop |
        Out-Null

    Write-Host `
        "Linked clone $ClonedTestCaseId to source testcase $SourceTestCaseId"
}

