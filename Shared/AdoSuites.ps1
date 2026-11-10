function Get-TestSuite {
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

    $url = "https://dev.azure.com/$Organization/$encodedProject" +
           "/_apis/testplan/Plans/$PlanId/suites/$SuiteId" +
           "?api-version=7.1"
		   
	try {
		Invoke-RestMethod `
			-Uri $url `
			-Method Get `
			-Headers $Headers `
			-ErrorAction Stop
	}
	catch {
		Write-Host "REST API request failed" -ForegroundColor Red
		Write-Host "URL: $url"
		Write-Host "HTTP status: $([int]$_.Exception.Response.StatusCode)"
		Write-Host "Error: $($_.Exception.Message)"
		
		if ($_.ErrorDetails.Message) {
			Write-Host "Azure DevOps response:"
			Write-Host $_.ErrorDetails.Message
		}

		if ($_.Exception.Response) {
			$stream = $_.Exception.Response.GetResponseStream()

			if ($stream) {
				$reader = [System.IO.StreamReader]::new($stream)
				Write-Host "Response body:"
				Write-Host $reader.ReadToEnd()
			}
		}

		throw
	}
}

function Add-TestCaseToSuite {
    param(
        [string]$Organization,
        [string]$Project,
        [int]$PlanId,
        [int]$SuiteId,
        [int]$TestCaseId,
        [hashtable]$Headers
    )

    #$addUrl = "https://dev.azure.com/$Organization/$([uri]::EscapeDataString($Project))/_apis/test/Plans/$PlanId/Suites/$SuiteId/testcases/$TestCaseId?api-version=7.1"
	$addUrl = "https://dev.azure.com/$Organization/$([uri]::EscapeDataString($Project))/_apis/test/Plans/$PlanId/Suites/$SuiteId/testcases/$($TestCaseId)?api-version=7.1"

    Write-Host ""
    Write-Host "=== ADD TESTCASE TO SUITE ==="
    Write-Host "Plan ID   : $PlanId"
    Write-Host "Suite ID  : $SuiteId"
    Write-Host "TestCaseID: $TestCaseId"
    Write-Host "URL       : $addUrl"
    Write-Host ""

    Invoke-RestMethod `
        -Uri $addUrl `
        -Method Post `
        -Headers $Headers `
        -ContentType "application/json" `
        -Body "{}"
}

function Remove-TestCaseFromSuite {

    param(
        [string]$Organization,
        [string]$Project,
        [int]$PlanId,
        [int]$SuiteId,
        [int]$TestCaseId,
        [hashtable]$Headers
    )

    $removeUrl = "https://dev.azure.com/$Organization/$([uri]::EscapeDataString($Project))/_apis/test/Plans/$PlanId/Suites/$SuiteId/testcases/$($TestCaseId)?api-version=7.1"

    Write-Host ""
    Write-Host "=== REMOVE TESTCASE FROM SUITE ==="
    Write-Host "Plan ID   : $PlanId"
    Write-Host "Suite ID  : $SuiteId"
    Write-Host "TestCaseID: $TestCaseId"
    Write-Host "URL       : $removeUrl"
    Write-Host ""

    Invoke-RestMethod `
        -Uri $removeUrl `
        -Method Delete `
        -Headers $Headers

    Write-Host "Removed testcase $TestCaseId from suite $SuiteId"
}

function Resolve-SuiteIdByPath {
    param(
        [string]$Organization,
        [string]$Project,
        [int]$PlanId,
        [string]$SuitePath,
        [hashtable]$Headers
    )

    $encodedProject = [uri]::EscapeDataString($Project)

    $planUrl = "https://dev.azure.com/$Organization/$encodedProject/_apis/testplan/Plans/$($PlanId)?api-version=7.1"

    $plan = Invoke-RestMethod `
        -Uri $planUrl `
        -Method Get `
        -Headers $Headers

    $currentSuiteId = [int]$plan.rootSuite.id
    $currentPath = ""

    $pathParts = $SuitePath.Split("\") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

    foreach ($part in $pathParts) {

        $suiteUrl = "https://dev.azure.com/$Organization/$encodedProject/_apis/testplan/Plans/$PlanId/suites/$currentSuiteId`?expand=Children&api-version=7.1"

        $currentSuite = Invoke-RestMethod `
            -Uri $suiteUrl `
            -Method Get `
            -Headers $Headers

        Write-Host ""
        Write-Host "Resolving suite path part: $part"
        Write-Host "Current suite: $($currentSuite.name) [$currentSuiteId]"
        Write-Host "Current path : $currentPath"
        Write-Host "Children     : $($currentSuite.children.Count)"

        $matchingChild = $currentSuite.children | Where-Object {
            $_.name -eq $part
        }

        if (-not $matchingChild) {
            Write-Host ""
            Write-Host "Available children:"
            $currentSuite.children | ForEach-Object {
                Write-Host " - $($_.name) [$($_.id)]"
            }

            throw "Could not resolve SuitePath '$SuitePath'. Missing part '$part' under '$($currentSuite.name)'."
        }

        if ($matchingChild.Count -gt 1) {
            throw "SuitePath '$SuitePath' is ambiguous. More than one child named '$part' under '$($currentSuite.name)'."
        }

        $currentSuiteId = [int]$matchingChild.id

        if ([string]::IsNullOrWhiteSpace($currentPath)) {
            $currentPath = $part
        }
        else {
            $currentPath = "$currentPath\$part"
        }

        Write-Host "Resolved to : $currentPath [$currentSuiteId]"
    }

    return $currentSuiteId
}

function Get-ChildTestSuites {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$PlanId,

        [Parameter(Mandatory = $true)]
        [int]$SuiteId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    $encodedProject = [uri]::EscapeDataString($Project)

    $uri =
        "https://dev.azure.com/$Organization/$encodedProject/_apis/testplan/Plans/$PlanId/suites/$SuiteId`?expand=Children&api-version=7.1"

    $suite = Invoke-RestMethod `
        -Method Get `
        -Uri $uri `
        -Headers $Headers `
        -ErrorAction Stop

    if ($null -eq $suite.children) {
        return @()
    }

    return @($suite.children)
}

function CreateStaticTestSuite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$PlanId,

        [Parameter(Mandatory = $true)]
        [int]$ParentSuiteId,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    $encodedProject = [uri]::EscapeDataString($Project)

    $url = "https://dev.azure.com/$Organization/$encodedProject/_apis/testplan/Plans/$PlanId/suites?api-version=7.1"

    $body = @{
        suiteType = "staticTestSuite"
        name      = $Name

        parentSuite = @{
            id = $ParentSuiteId
        }
    } | ConvertTo-Json -Depth 10

    Write-Host ""
    Write-Host "Creating static test suite"
    Write-Host "Name      : $Name"
    Write-Host "Parent ID : $ParentSuiteId"
    Write-Host "Plan ID   : $PlanId"
    Write-Host ""

    $newSuite = Invoke-RestMethod `
        -Uri $url `
        -Method Post `
        -Headers $Headers `
        -ContentType "application/json" `
        -Body $body `
        -ErrorAction Stop

    Write-Host "Created suite:"
    Write-Host "ID   : $($newSuite.id)"
    Write-Host "Name : $($newSuite.name)"

    return $newSuite
}

function RecursiveRenameTestCasesInSuite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$PlanId,

        [Parameter(Mandatory = $true)]
        [int]$SuiteId,

        [Parameter(Mandatory = $true)]
        [string]$SuiteName,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string[]]$OldPrefixes,

        [Parameter(Mandatory = $true)]
        [string]$NewPrefix
    )

    Write-Host ""
    Write-Host "============================================"
    Write-Host "Processing suite: $SuiteName"
    Write-Host "Plan   : $PlanId"
    Write-Host "Suite  : $SuiteId"
    Write-Host "Rename : $($OldPrefixes -join ', ') -> $NewPrefix"
    Write-Host "============================================"
    Write-Host ""

    $encodedProject = [uri]::EscapeDataString($Project)

    # Get test cases directly in this suite
    $url = "https://dev.azure.com/$Organization/$encodedProject/_apis/test/Plans/$PlanId/suites/$SuiteId/testcases?api-version=7.1"

    $response = Invoke-RestMethod `
        -Uri $url `
        -Method Get `
        -Headers $Headers

    foreach ($item in $response.value) {

        $testCaseId = [int]$item.testCase.id

        $workItemUrl = "https://dev.azure.com/$Organization/$encodedProject/_apis/wit/workitems/${testCaseId}?api-version=7.1"

        $workItem = Invoke-RestMethod `
            -Uri $workItemUrl `
            -Method Get `
            -Headers $Headers

        $oldTitle = $workItem.fields.'System.Title'

        foreach ($oldPrefix in $OldPrefixes) {

            if ($oldTitle.StartsWith($oldPrefix)) {

                $newTitle = $NewPrefix + $oldTitle.Substring($oldPrefix.Length)

                Write-Host "$testCaseId : $oldTitle"
                Write-Host "         -> $newTitle"

                $patchDocument = @(
					@{
						op    = "replace"
						path  = "/fields/System.Title"
						value = $newTitle
					}
				)

				$body = ConvertTo-Json -InputObject $patchDocument

                Invoke-RestMethod `
                    -Uri $workItemUrl `
                    -Method Patch `
                    -Headers $Headers `
                    -ContentType "application/json-patch+json" `
                    -Body $body | Out-Null

                break
            }
        }
    }

    # Get direct child suites
    $children = @(Get-ChildTestSuites `
        -Organization $Organization `
        -Project $Project `
        -PlanId $PlanId `
        -SuiteId $SuiteId `
        -Headers $Headers)

    Write-Host ""
    Write-Host "Child suites found: $($children.Count)"
    Write-Host ""

    foreach ($child in $children) {

        RecursiveRenameTestCasesInSuite `
            -Organization $Organization `
            -Project $Project `
            -PlanId $PlanId `
            -SuiteId ([int]$child.id) `
            -SuiteName $child.name `
            -Headers $Headers `
            -OldPrefixes $OldPrefixes `
            -NewPrefix $NewPrefix
    }
}

function RecursiveGetTestCasesInSuite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$PlanId,

        [Parameter(Mandatory = $true)]
        [int]$SuiteId,

        [Parameter(Mandatory = $true)]
        [string]$SuiteName,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [string]$SuitePath = ""
    )

    $encodedProject = [uri]::EscapeDataString($Project)

    # Build full suite path
    if ([string]::IsNullOrWhiteSpace($SuitePath)) {
        $currentSuitePath = $SuiteName
    }
    else {
        $currentSuitePath = "$SuitePath > $SuiteName"
    }

    Write-Host ""
    Write-Host "============================================"
    Write-Host "Processing suite: $SuiteName"
    Write-Host "Suite path      : $currentSuitePath"
    Write-Host "Plan            : $PlanId"
    Write-Host "Suite           : $SuiteId"
    Write-Host "============================================"
    Write-Host ""

    # Get test cases directly in this suite
    $url = "https://dev.azure.com/${Organization}/${encodedProject}/_apis/test/Plans/${PlanId}/suites/${SuiteId}/testcases?api-version=7.1"

    $response = Invoke-RestMethod `
        -Uri $url `
        -Method Get `
        -Headers $Headers

    Write-Host "Test cases found: $($response.value.Count)"

    foreach ($item in $response.value) {

        $testCaseId = [int]$item.testCase.id

        $workItemUrl = "https://dev.azure.com/${Organization}/${encodedProject}/_apis/wit/workitems/${testCaseId}?api-version=7.1"

        $workItem = Invoke-RestMethod `
            -Uri $workItemUrl `
            -Method Get `
            -Headers $Headers

        $assignedTo = ""

        if ($workItem.fields.'System.AssignedTo') {
            $assignedTo = $workItem.fields.'System.AssignedTo'.displayName
        }

        # Return one object for each testcase
        [PSCustomObject]@{
            SuitePath  = $currentSuitePath
            SuiteName  = $SuiteName
            SuiteId    = $SuiteId
            TestCaseId = $testCaseId
            Title      = $workItem.fields.'System.Title'
            State      = $workItem.fields.'System.State'
            AssignedTo = $assignedTo
            Tags = $workItem.fields.'System.Tags' -replace ';', ','
        }
    }


    # Get direct child suites
    $children = @(Get-ChildTestSuites `
        -Organization $Organization `
        -Project $Project `
        -PlanId $PlanId `
        -SuiteId $SuiteId `
        -Headers $Headers)

    Write-Host "Child suites found: $($children.Count)"

    foreach ($child in $children) {

        RecursiveGetTestCasesInSuite `
            -Organization $Organization `
            -Project $Project `
            -PlanId $PlanId `
            -SuiteId ([int]$child.id) `
            -SuiteName $child.name `
            -Headers $Headers `
            -SuitePath $currentSuitePath
    }
}

function Get-TestCasesInSuite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$PlanId,

        [Parameter(Mandatory = $true)]
        [int]$SuiteId,

        [Parameter(Mandatory = $false)]
		[string]$SuiteName,
		
		[Parameter(Mandatory = $true)]
		[hashtable]$Headers,

        [switch]$IncludeSubSuites,

        [string]$SuitePath = ""
    )

    $encodedProject = [uri]::EscapeDataString($Project)
    $baseUrl = "https://dev.azure.com/$Organization/$encodedProject"

	# Resolve suite name if not provided
	if ([string]::IsNullOrWhiteSpace($SuiteName)) {
		$suite = Get-TestSuite `
			-Organization $Organization `
			-Project $Project `
			-PlanId $PlanId `
			-SuiteId $SuiteId `
			-Headers $Headers `
			-ErrorAction Stop

		$SuiteName = $suite.name
	}

	if ([string]::IsNullOrWhiteSpace($SuitePath)) {
		$currentSuitePath = $SuiteName
	}
	else {
		$currentSuitePath = "$SuitePath > $SuiteName"
	}

    Write-Host ""
    Write-Host "Processing folder : $SuiteName"
    Write-Host "Folder path       : $currentSuitePath"
    Write-Host "Suite ID          : $SuiteId"

    # Same endpoint as the existing working Copy-TestCasesInSuite
    $testCasesUrl =
        "$baseUrl/_apis/test/Plans/$PlanId/Suites/$SuiteId/testcases?api-version=7.1"

    $response = Invoke-RestMethod `
        -Uri $testCasesUrl `
        -Method Get `
        -Headers $Headers `
        -ErrorAction Stop

    foreach ($item in $response.value) {

        $testCaseId = [int]$item.testCase.id

        $workItemUrl =
            "$baseUrl/_apis/wit/workitems/$testCaseId`?api-version=7.1"

        $workItem = Invoke-RestMethod `
            -Uri $workItemUrl `
            -Method Get `
            -Headers $Headers `
            -ErrorAction Stop

        $assignedTo = ""

        if ($workItem.fields.'System.AssignedTo') {
            $assignedTo = $workItem.fields.'System.AssignedTo'.displayName
        }

		[PSCustomObject]@{
			SuitePath  = $currentSuitePath
			SuiteName  = $SuiteName
			SuiteId    = $SuiteId
			TestCaseId = $testCaseId
			Title      = $workItem.fields.'System.Title'
			State      = $workItem.fields.'System.State'
			AssignedTo = $assignedTo
			Priority   = $workItem.fields.'Microsoft.VSTS.Common.Priority'
			Tags       = $workItem.fields.'System.Tags' -replace ';', ','
		}
    }

    if (-not $IncludeSubSuites) {
        return
    }

    $children = @(
        Get-ChildTestSuites `
            -Organization $Organization `
            -Project $Project `
            -PlanId $PlanId `
            -SuiteId $SuiteId `
            -Headers $Headers
    )

    foreach ($child in $children) {

        Get-TestCasesInSuite `
            -Organization $Organization `
            -Project $Project `
            -PlanId $PlanId `
            -SuiteId ([int]$child.id) `
            -SuiteName $child.name `
            -Headers $Headers `
            -IncludeSubSuites `
            -SuitePath $currentSuitePath
    }
}

function Get-OrCreateTestSuitePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$PlanId,

        [Parameter(Mandatory = $true)]
        [int]$ParentSuiteId,

        [Parameter(Mandatory = $false)]
        [string[]]$SuitePath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    $currentSuiteId = $ParentSuiteId

    foreach ($suiteName in $SuitePath) {

        if ([string]::IsNullOrWhiteSpace($suiteName)) {
            continue
        }

        $children = @(
            Get-ChildTestSuites `
                -Organization $Organization `
                -Project $Project `
                -PlanId $PlanId `
                -SuiteId $currentSuiteId `
                -Headers $Headers
        )

        $existingSuite = $children |
            Where-Object { $_.name -eq $suiteName } |
            Select-Object -First 1

        if ($existingSuite) {

            Write-Host "Using existing folder: $suiteName"

            $currentSuiteId = [int]$existingSuite.id
            continue
        }

        Write-Host "Creating folder: $suiteName"

        $newSuite = CreateStaticTestSuite `
            -Organization $Organization `
            -Project $Project `
            -PlanId $PlanId `
            -ParentSuiteId $currentSuiteId `
            -Name $suiteName `
            -Headers $Headers

        $currentSuiteId = [int]$newSuite.id
    }

    return $currentSuiteId
}

function Clear-TestSuite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$PlanId,

        [Parameter(Mandatory = $true)]
        [int]$SuiteId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [bool]$DeleteSuite = $false
    )

    $encodedProject =
        [uri]::EscapeDataString($Project)


    # Remove all testcases directly from this suite

    $testCases = @(
        Get-TestCasesInSuite `
            -Organization $Organization `
            -Project $Project `
            -PlanId $PlanId `
            -SuiteId $SuiteId `
            -SuiteName "Current" `
            -Headers $Headers
    )

    foreach ($testCase in $testCases) {

        Remove-TestCaseFromSuite `
            -Organization $Organization `
            -Project $Project `
            -PlanId $PlanId `
            -SuiteId $SuiteId `
            -TestCaseId ([int]$testCase.TestCaseId) `
            -Headers $Headers
    }


    # Recursively clear and delete all child suites

    $childSuites = @(
        Get-ChildTestSuites `
            -Organization $Organization `
            -Project $Project `
            -PlanId $PlanId `
            -SuiteId $SuiteId `
            -Headers $Headers
    )

    foreach ($childSuite in $childSuites) {

        Clear-TestSuite `
            -Organization $Organization `
            -Project $Project `
            -PlanId $PlanId `
            -SuiteId ([int]$childSuite.id) `
            -Headers $Headers `
            -DeleteSuite $true
    }


    # Delete this suite if requested

    if ($DeleteSuite) {

        Write-Host "Deleting suite $SuiteId"

        $deleteUrl =
            "https://dev.azure.com/$Organization/$encodedProject/_apis/testplan/Plans/$PlanId/suites/$SuiteId`?api-version=7.1"

        Invoke-RestMethod `
            -Uri $deleteUrl `
            -Method Delete `
            -Headers $Headers `
            -ErrorAction Stop |
            Out-Null
    }
}

function Get-TestCaseIdsInSuite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$PlanId,

        [Parameter(Mandatory = $true)]
        [int]$SuiteId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [switch]$IncludeSubSuites
    )

    try {
        $encodedProject = [uri]::EscapeDataString($Project)
        $baseUrl = "https://dev.azure.com/$Organization/$encodedProject"

        Write-Verbose "Reading test cases from suite $SuiteId..."

        $testCasesUrl =
            "$baseUrl/_apis/test/Plans/$PlanId/Suites/$SuiteId/testcases?api-version=7.1"

        $response = Invoke-RestMethod `
            -Uri $testCasesUrl `
            -Method Get `
            -Headers $Headers `
            -ErrorAction Stop

        foreach ($item in $response.value) {
            [int]$item.testCase.id
        }

        if (-not $IncludeSubSuites) {
            return
        }

        $children = @(
            Get-ChildTestSuites `
                -Organization $Organization `
                -Project $Project `
                -PlanId $PlanId `
                -SuiteId $SuiteId `
                -Headers $Headers
        )

        foreach ($child in $children) {

            Get-TestCaseIdsInSuite `
                -Organization $Organization `
                -Project $Project `
                -PlanId $PlanId `
                -SuiteId ([int]$child.id) `
                -Headers $Headers `
                -IncludeSubSuites
        }
    }
    catch {
        throw "Failed reading test suite $SuiteId. $($_.Exception.Message)"
    }
}

function Get-TestSuiteName {
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

    $url = "$baseUrl/_apis/testplan/Plans/$PlanId/suites/$SuiteId" +
           "?api-version=7.1"

    $response = Invoke-RestMethod `
        -Uri $url `
        -Method Get `
        -Headers $Headers `
        -ErrorAction Stop

    return $response.name
}

