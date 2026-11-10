function Read-TestCaseTextFile {
    param([string]$Path)

    $data = @{}
    $currentSection = $null

    foreach ($line in Get-Content $Path) {
        if ($line -match '^\[(.+)\]$') {
            $currentSection = $matches[1]
            $data[$currentSection] = ""
        }
        elseif ($currentSection) {
            $data[$currentSection] += $line + "`n"
        }
    }

    return $data
}

function Convert-StepsToAdoXml {
    param([string]$StepsText)

    $stepLines = $StepsText -split "`n" | Where-Object { $_.Trim() -ne "" }
    $xml = "<steps id=`"0`" last=`"$($stepLines.Count)`">"

    $id = 1
    foreach ($line in $stepLines) {
        $parts = $line -split '\|', 3

        if ($parts.Count -ne 3) {
            throw "Invalid step format: $line"
        }
		if ($parts[0].Trim() -notmatch '^\d+$') {
			throw "Invalid step format: $line"
		}

        $action = [System.Security.SecurityElement]::Escape($parts[1].Trim())
        $expected = [System.Security.SecurityElement]::Escape($parts[2].Trim())

        $xml += "<step id=`"$id`" type=`"ActionStep`">"
        $xml += "<parameterizedString isformatted=`"true`">$action</parameterizedString>"
        $xml += "<parameterizedString isformatted=`"true`">$expected</parameterizedString>"
        $xml += "</step>"

        $id++
    }

    $xml += "</steps>"
    return $xml
}

function Validate-TestCaseData {
    param(
        [hashtable]$Data,
        [string]$Organization,
        [string]$Project,
        [int]$PlanId,
        [hashtable]$Headers
    )

    $requiredFields = @(
        "ExternalReferenceID",
        "SuitePath",
        "Name",
        "Tags",
        "Description",
        "Steps"
    )

    foreach ($field in $requiredFields) {

        if (-not $Data.ContainsKey($field)) {
            throw "Missing required section [$field]"
        }

        if ([string]::IsNullOrWhiteSpace($Data[$field])) {
            throw "Section [$field] is empty"
        }
    }

    $suitePath = $Data["SuitePath"].Trim()

    $suiteId = Resolve-SuiteIdByPath `
        -Organization $Organization `
        -Project $Project `
        -PlanId $PlanId `
        -SuitePath $suitePath `
        -Headers $Headers

  
    $steps = $Data["Steps"] -split "`n" |
        Where-Object { $_.Trim() -ne "" }

    if ($steps.Count -eq 0) {
        throw "No test steps found"
    }

    foreach ($step in $steps) {

        $parts = $step -split '\|', 3

        if ($parts.Count -ne 3) {
            throw "Invalid step format: $step"
        }

        if ($parts[1].Trim() -eq "") {
            throw "Step action is empty: $step"
        }

        if ($parts[2].Trim() -eq "") {
            throw "Step expected result is empty: $step"
        }
    }

    if ($Data.ContainsKey("Channel")) {

        $channel = $Data["Channel"].Trim()

        if ($channel -ne "") {

            $channels = $channel -split '[;,]' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -ne "" }

            foreach ($c in $channels) {
                if ($c.Length -gt 50) {
                    throw "Channel value too long: $c"
                }
            }
        }
    }

    if ($Data.ContainsKey("Product")) {

        $product = $Data["Product"].Trim()

        if ($product -ne "") {

            $products = $product -split '[;,]' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -ne "" }

            foreach ($p in $products) {
                if ($p.Length -gt 50) {
                    throw "Product value too long: $p"
                }
            }
        }
    }

    return @{
        Data      = $Data
        SuitePath = $suitePath
        SuiteId   = $suiteId
        Journey   = $journey
    }
}

function CreateAdoJson {
    param(
        [hashtable]$Data,
        [string]$Title,
        [string]$ExternalReferenceId,
        [string]$DescriptionHtml,
        [string]$StepsXml
    )

    $patch = @()

    $patch += @{
        op = "add"
        path = "/fields/System.Title"
        value = $Title
    }

    $patch += @{
        op = "add"
        path = "/fields/Custom.ExternalReferenceID"
        value = $ExternalReferenceId
    }

    $patch += @{
        op = "add"
        path = "/fields/Custom.CustomerJourney"
        value = $Data["CustomerJourney"].Trim()
    }

    foreach ($field in @("Channel", "Product")) {
        if ($Data.ContainsKey($field)) {
            $value = $Data[$field].Trim()

            if ($value -ne "") {
                $value = ($value -split '[;,]' |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ -ne "" }) -join "; "

                $patch += @{
                    op = "add"
                    path = "/fields/Custom.$field"
                    value = $value
                }
            }
        }
    }

    $patch += @{
        op = "add"
        path = "/fields/System.Tags"
        value = $Data["Tags"].Trim()
    }

    $patch += @{
        op = "add"
        path = "/fields/System.Description"
        value = $DescriptionHtml
    }

    $patch += @{
        op = "add"
        path = "/fields/Microsoft.VSTS.TCM.Steps"
        value = $StepsXml
    }

    return ([array]$patch | ConvertTo-Json -Depth 10)
}

