function Select-TestCases {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSObject]$TestCase,

        [ValidateRange(1, 4)]
        [int]$Priority,

        [string]$Outcome,

        [string[]]$ExcludeLogicalIds
    )

    begin {
        $excludedIds = @{}

        foreach ($id in $ExcludeLogicalIds) {
            if (-not [string]::IsNullOrWhiteSpace($id)) {
                $excludedIds[$id] = $true
            }
        }
    }

    process {
        $include = $true

        if ($PSBoundParameters.ContainsKey('Priority')) {
            if ($TestCase.Priority -ne $Priority) {
                $include = $false
            }
        }

        if ($PSBoundParameters.ContainsKey('Outcome')) {
            if (-not $TestCase.PSObject.Properties['Outcome']) {
                throw "Test case $($TestCase.TestCaseId) has no Outcome property."
            }

            if ($TestCase.Outcome -ne $Outcome) {
                $include = $false
            }
        }

        if ($include -and $excludedIds.Count -gt 0) {
            $logicalId = Get-TestCaseLogicalId -TestCase $TestCase

            if ($logicalId -and
                $excludedIds.ContainsKey($logicalId.LogicalId)) {
                $include = $false
            }
        }

        if ($include) {
            $TestCase
        }
    }
}

function Get-OrCreateTestCase {

    param(
        [string]$ExternalReferenceId,
        [string]$Json,
        [string]$CreateUrl,
        [hashtable]$Headers,
        [string]$Organization,
        [string]$Project
    )

    $wiql = @{
        query = @"
SELECT
    [System.Id],
    [System.State],
    [System.Title]
FROM WorkItems
WHERE
    [System.WorkItemType] = 'Test Case'
    AND [Custom.ExternalReferenceID] = '$ExternalReferenceId'
"@
    } | ConvertTo-Json

    $wiqlUrl = "https://dev.azure.com/$Organization/$([uri]::EscapeDataString($Project))/_apis/wit/wiql?api-version=7.1"

    $wiqlResult = Invoke-RestMethod `
        -Uri $wiqlUrl `
        -Method Post `
        -Headers $Headers `
        -ContentType "application/json" `
        -Body $wiql

    if ($wiqlResult.workItems.Count -gt 0) {

        $ids = ($wiqlResult.workItems | ForEach-Object { $_.id }) -join ","

        $detailsUrl = "https://dev.azure.com/$Organization/$([uri]::EscapeDataString($Project))/_apis/wit/workitems?ids=$ids&fields=System.Id,System.State,System.Title&api-version=7.1"

        $details = Invoke-RestMethod `
            -Uri $detailsUrl `
            -Method Get `
            -Headers $Headers

        $active = $details.value | Where-Object {
            $_.fields.'System.State' -ne "Removed"
        } | Select-Object -First 1

        if ($active) {

            Write-Host ""
            Write-Host "Existing ACTIVE testcase found"
            Write-Host "ID    : $($active.id)"
            Write-Host "State : $($active.fields.'System.State')"
            Write-Host "Title : $($active.fields.'System.Title')"
            Write-Host ""

            return $active.id
        }
    }

    Write-Host ""
    Write-Host "Creating new testcase..."
    Write-Host ""

	$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Json)

	$createdTestCase = Invoke-RestMethod `
    -Uri $CreateUrl `
    -Method Post `
    -Headers $Headers `
    -ContentType "application/json-patch+json" `
    -Body $bodyBytes

    Write-Host "Created Test Case ID: $($createdTestCase.id)"

    return $createdTestCase.id
}

function Set-TestCaseState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$TestCase,

        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$State
    )

    process {

        # Skip test cases already in the requested state
        if ($TestCase.State -eq $State) {
            Write-Host "Skipping $($TestCase.TestCaseId) - already '$State'"
            return
        }

        $encodedProject = [uri]::EscapeDataString($Project)

        $url = "https://dev.azure.com/${Organization}/${encodedProject}/_apis/wit/workitems/$($TestCase.TestCaseId)?api-version=7.1"

        $body = ConvertTo-Json -InputObject @(
            @{
                op    = "replace"
                path  = "/fields/System.State"
                value = $State
            }
        )

        $description = "$($TestCase.TestCaseId) - $($TestCase.Title)"

        if ($PSCmdlet.ShouldProcess($description, "Change state from '$($TestCase.State)' to '$State'")) {

            try {
                Invoke-RestMethod `
                    -Uri $url `
                    -Method Patch `
                    -Headers $Headers `
                    -ContentType "application/json-patch+json" `
                    -Body $body | Out-Null

                Write-Host "Updated: $($TestCase.TestCaseId) - $($TestCase.Title)"
            }
            catch {
                Write-Warning "FAILED: $($TestCase.TestCaseId) - $($TestCase.Title)"
                Write-Warning $_.Exception.Message

                if ($_.ErrorDetails.Message) {
                    Write-Warning $_.ErrorDetails.Message
                }
            }
        }
    }
}

function RecursiveSetTestCaseState {
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
        [string]$State
    )

    RecursiveGetTestCasesInSuite `
        -Organization $Organization `
        -Project $Project `
        -PlanId $PlanId `
        -SuiteId $SuiteId `
        -SuiteName $SuiteName `
        -Headers $Headers |
    Set-TestCaseState `
        -Organization $Organization `
        -Project $Project `
        -Headers $Headers `
        -State $State
}

function ConvertFrom-AdoTestSteps {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepsXml
    )

    if ([string]::IsNullOrWhiteSpace($StepsXml)) {
        return ""
    }

    [xml]$xml = $StepsXml

    $result = @()
    $stepNumber = 1

    foreach ($step in $xml.steps.step) {

        $strings = @($step.parameterizedString)

        $action = ""
        $expected = ""

        if ($strings.Count -ge 1) {
            $action = $strings[0].InnerText
        }

        if ($strings.Count -ge 2) {
            $expected = $strings[1].InnerText
        }

        $action = $action `
            -replace '(?i)<br\s*/?>', ' ' `
            -replace '(?i)</div>', ' ' `
            -replace '(?i)</p>', ' ' `
            -replace '<[^>]+>', ''

        $expected = $expected `
            -replace '(?i)<br\s*/?>', ' ' `
            -replace '(?i)</div>', ' ' `
            -replace '(?i)</p>', ' ' `
            -replace '<[^>]+>', ''

        $action = [System.Net.WebUtility]::HtmlDecode($action).Trim()
        $expected = [System.Net.WebUtility]::HtmlDecode($expected).Trim()

        $result += "$stepNumber | $action | $expected"

        $stepNumber++
    }

    return ($result -join "`r`n")
}

function ConvertTo-AdoTestSteps {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepsText
    )

    $lines = $StepsText -split "`r?`n"

    $xmlDoc = New-Object System.Xml.XmlDocument

    $stepsElement = $xmlDoc.CreateElement("steps")
    $stepsElement.SetAttribute("id", "0")

    $xmlDoc.AppendChild($stepsElement) | Out-Null

    $stepId = 0

    foreach ($line in $lines) {

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $parts = $line -split '\|', 3

        if ($parts.Count -lt 2) {
            continue
        }

        $stepId++

        $action = $parts[1].Trim()

        $expected = ""
        if ($parts.Count -ge 3) {
            $expected = $parts[2].Trim()
        }

        $stepElement = $xmlDoc.CreateElement("step")
        $stepElement.SetAttribute("id", [string]$stepId)
        $stepElement.SetAttribute("type", "ActionStep")

        $actionElement = $xmlDoc.CreateElement("parameterizedString")
        $actionElement.SetAttribute("isformatted", "true")
        $actionElement.InnerText = "<DIV>$([System.Net.WebUtility]::HtmlEncode($action))</DIV>"

        $expectedElement = $xmlDoc.CreateElement("parameterizedString")
        $expectedElement.SetAttribute("isformatted", "true")
        $expectedElement.InnerText = "<DIV>$([System.Net.WebUtility]::HtmlEncode($expected))</DIV>"

        $descriptionElement = $xmlDoc.CreateElement("description")

        $stepElement.AppendChild($actionElement) | Out-Null
        $stepElement.AppendChild($expectedElement) | Out-Null
        $stepElement.AppendChild($descriptionElement) | Out-Null

        $stepsElement.AppendChild($stepElement) | Out-Null
    }

    $stepsElement.SetAttribute("last", [string]$stepId)

    return $xmlDoc.OuterXml
}

function Get-TestCaseNumber {
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        [object[]]$InputObject
    )

    process {

        foreach ($item in $InputObject) {

            if ($item -is [string]) {
                $title = $item
            }
            elseif ($item.PSObject.Properties.Name -contains "Title") {
                $title = $item.Title
            }
            else {
                Write-Warning "Input does not contain a Title: $item"
                continue
            }

            $testCaseNumber = $null

            # Standard TS numbering
            #
            # FUT-Buy-TS09      -> TS09
            # FUT-Change-TS01a  -> TS01
            # FUT-Change-TS01b  -> TS01

            if ($title -match '(?i)(?:^|[^A-Z0-9])TS0*(?<Number>\d+)[a-z]?(?=[^A-Z0-9]|$)') {

                $number = [int]$Matches.Number

                if ($number -lt 100) {
                    $testCaseNumber = "TS{0:D2}" -f $number
                }
                else {
                    $testCaseNumber = "TS$number"
                }
            }

            # EXP numbering
            elseif ($title -match '(?i)(?:^|[^A-Z0-9])EXP0*(?<Number>\d+)[a-z]?(?=[^A-Z0-9]|$)') {

                $number = [int]$Matches.Number
                $testCaseNumber = "EXP$number"
            }

            # DV numbering
            elseif ($title -match '(?i)(?:^|[^A-Z0-9])DV0*(?<Number>\d+)[a-z]?(?=[^A-Z0-9]|$)') {

                $number = [int]$Matches.Number
                $testCaseNumber = "DV{0:D2}" -f $number
            }

            # Older identifiers without TS
            #
            # FUT-GET_HELP-11  -> 11
            # BAT-GET_HELP-11  -> 11
            # BAT - Leave - 05 -> 05

            elseif ($title -match '(?i)[-_]\s*0*(?<Number>\d{1,3})[a-z]?\s*(?=[-_]|$)') {

                $number = [int]$Matches.Number

                if ($number -lt 100) {
                    $testCaseNumber = "{0:D2}" -f $number
                }
                else {
                    $testCaseNumber = "$number"
                }
            }

            if (-not $testCaseNumber) {
                Write-Warning "Could not determine testcase number from: $title"
                continue
            }

            $testCaseNumber
        }
    }
}

function Set-TestCaseTitle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$TestCaseId,

        [Parameter(Mandatory = $true)]
        [string]$LogicalId,

        [Parameter(Mandatory = $true)]
        [string]$SourceTitle,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    $encodedProject = [uri]::EscapeDataString($Project)

    $workItemUrl =
        "https://dev.azure.com/$Organization/$encodedProject/_apis/wit/workitems/$TestCaseId`?api-version=7.1"


    # --------------------------------------------------------
    # Determine target testcase prefix from the source testcase
    #
    # BAT   -> FUT
    # M-BAT -> M-FUT
    # --------------------------------------------------------

    if ($SourceTitle -match '(?i)^\s*M\s*-\s*BAT\b') {

        $targetPrefix = "M-FUT"
    }
    elseif ($SourceTitle -match '(?i)^\s*BAT\b') {

        $targetPrefix = "FUT"
    }
    else {

        throw "Unsupported source testcase prefix: $SourceTitle"
    }


    # --------------------------------------------------------
    # Extract the descriptive part of the source title
    #
    # Examples:
    #
    # BAT - Change - TS53 - Description
    # M-BAT - Change - TS53 - Description
    #
    # both result in:
    #
    # Description
    # --------------------------------------------------------

    $description = ""

	if (
		$SourceTitle -match `
			'(?i)^\s*(?:M\s*-\s*BAT|BAT).*?(?:TS\d+[a-z]?|\d{1,3})(?:\s*\([^)]*\))?\s*-\s*(?<Description>.*)$'
	) {
		$description =
			$Matches.Description.Trim()

		if ([string]::IsNullOrWhiteSpace($description)) {
			Write-Warning `
				"Description is empty in source title: $SourceTitle"
		}
	}
	else {
		Write-Warning `
			"Could not determine description from source title: $SourceTitle"
	}

    # --------------------------------------------------------
    # Construct the new title
    # --------------------------------------------------------

    $newTitle =
        "$targetPrefix-$LogicalId"

    if (-not [string]::IsNullOrWhiteSpace($description)) {

        $newTitle +=
            " - $description"
    }


    # --------------------------------------------------------
    # Update the cloned testcase
    # --------------------------------------------------------

    $patchDocument = @(
        @{
            op    = "replace"
            path  = "/fields/System.Title"
            value = $newTitle
        }
    )

    $body =
        ConvertTo-Json -InputObject $patchDocument

    Invoke-RestMethod `
        -Uri $workItemUrl `
        -Method Patch `
        -Headers $Headers `
        -ContentType "application/json-patch+json" `
        -Body $body `
        -ErrorAction Stop |
        Out-Null

    Write-Host "Renamed clone $TestCaseId"
    Write-Host "  $SourceTitle"
    Write-Host "  -> $newTitle"
}

function Get-TestCaseLogicalId {
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        [object[]]$TestCase
    )

    process {

        foreach ($item in $TestCase) {

            if (-not ($item.PSObject.Properties.Name -contains "Title")) {
                Write-Warning "Input does not contain a Title: $item"
                continue
            }

            if (-not ($item.PSObject.Properties.Name -contains "SuitePath")) {
                Write-Warning "Input does not contain a SuitePath: $item"
                continue
            }

            $number = Get-TestCaseNumber -InputObject $item.Title

            if (-not $number) {
                continue
            }

            $area = Get-TestCaseArea -InputObject $item

            $logicalId = "$area-$number"

            [PSCustomObject]@{
                Area      = $area
                Number    = $number
                LogicalId = $logicalId
                TestCase  = $item
            }
        }
    }
}

function Get-TestCaseArea {
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        [object[]]$InputObject
    )

    process {

        foreach ($item in $InputObject) {

            $title = $null
            $suitePath = $null

            if ($item -is [string]) {
                $title = $item
            }
            else {

                if ($item.PSObject.Properties.Name -contains "Title") {
                    $title = $item.Title
                }

                if ($item.PSObject.Properties.Name -contains "SuitePath") {
                    $suitePath = $item.SuitePath
                }
            }

            $area = $null

            if (-not [string]::IsNullOrWhiteSpace($title)) {

                # Remove execution prefix
                #
                # FUT-Buy-TS09        -> Buy-TS09
                # BAT - Change - TS05 -> Change - TS05
                # M-BAT-Pay-TS01      -> Pay-TS01
                # FUT-GET_HELP-11     -> GET_HELP-11

                $workingTitle = $title.Trim()

                $workingTitle = $workingTitle -replace `
					'(?i)^\s*(?:M\s*-\s*BAT|M\s*-\s*FUT|BAT|FUT)\s*[-_ ]+\s*', ''

                # Standard TS identifiers
                if ($workingTitle -match `
                    '(?i)^(?<Area>.+?)[\s_-]+TS0*\d+[a-z]?(?=[\s_-]|$)') {

                    $area = $Matches.Area
                }

                # Older identifiers without TS
				elseif ($workingTitle -match `
					'(?i)^(?<Area>.+?)[\s_-]+0*\d{1,3}[a-z]?\s*(?=[\s_-]|$)') {

                    $area = $Matches.Area
                }

                # Migration cases should have one canonical area
                if ($area -match '(?i)MIGRATION') {
                    $area = 'MIGRATION'
                }
            }

            # Fallback to suite hierarchy when title does not contain
            # enough information, for example EXP testcases.
            if ([string]::IsNullOrWhiteSpace($area) -and
                -not [string]::IsNullOrWhiteSpace($suitePath)) {

                $pathParts = @(
                    $suitePath -split '\s*>\s*' |
                        Where-Object {
                            -not [string]::IsNullOrWhiteSpace($_)
                        }
                )

                if ($pathParts.Count -ge 2) {
                    $area = $pathParts[1]
                }
                else {
                    $area = 'ROOT'
                }

                $area = $area -replace '(?i)\s*-\s*CFIT\s*$', ''
                $area = $area -replace '(?i)\s*-\s*migrated data\s*$', ''
            }

            if ([string]::IsNullOrWhiteSpace($area)) {
                $area = 'ROOT'
            }

            # Normalise spelling/formatting differences
            #
            # GetHelp / Get Help / GET_HELP -> GET_HELP
            # DoNotPay / Do Not Pay         -> DO_NOT_PAY

            $compactArea =
                ($area -replace '[^A-Za-z0-9]', '').ToUpperInvariant()

            switch ($compactArea) {

                'GETHELP' {
                    $area = 'GET_HELP'
                }

                'DONOTPAY' {
                    $area = 'DO_NOT_PAY'
                }

                default {
                    $area = (
                        $area.Trim() `
                            -replace '[\s-]+', '_' `
                            -replace '_+', '_'
                    ).ToUpperInvariant()
                }
            }

            $area
        }
    }
}

function Reset-TestCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$TestCaseId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    $encodedProject = [uri]::EscapeDataString($Project)

    $url =
        "https://dev.azure.com/$Organization/$encodedProject/_apis/wit/workitems/$TestCaseId`?api-version=7.1"

    $body = @(
        @{
            op    = "replace"
            path  = "/fields/System.State"
            value = "Design"
        },
        @{
            op   = "remove"
            path = "/fields/System.AssignedTo"
        }
    ) | ConvertTo-Json -Depth 5

    Invoke-RestMethod `
        -Uri $url `
        -Method Patch `
        -Headers $Headers `
        -ContentType "application/json-patch+json" `
        -Body $body `
        -ErrorAction Stop |
        Out-Null

    Write-Host "Reset testcase $TestCaseId to Design and cleared Assigned To"
}

function Reset-TestProgress {
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
        [int]$TestCaseId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    $encodedProject =
        [uri]::EscapeDataString($Project)

    # Get all test points for this testcase in this suite
    $getPointsUrl =
        "https://dev.azure.com/$Organization/$encodedProject/_apis/test/Plans/$PlanId/Suites/$SuiteId/points?testCaseId=$TestCaseId&api-version=7.1"

    $response = Invoke-RestMethod `
        -Uri $getPointsUrl `
        -Method Get `
        -Headers $Headers `
        -ErrorAction Stop

    $testPoints =
        @($response.value)

    foreach ($testPoint in $testPoints) {

        $pointId =
            [int]$testPoint.id

        $updateUrl =
            "https://dev.azure.com/$Organization/$encodedProject/_apis/test/Plans/$PlanId/Suites/$SuiteId/points/$pointId`?api-version=7.1"

        $body = @{
            resetToActive = $true
            outcome       = "None"
        } | ConvertTo-Json

        Invoke-RestMethod `
            -Uri $updateUrl `
            -Method Patch `
            -Headers $Headers `
            -ContentType "application/json" `
            -Body $body `
            -ErrorAction Stop |
            Out-Null

        Write-Host `
            "Reset test point $pointId for testcase $TestCaseId"
    }
}

