$organization = "TelenorDenmark-Prod"
$project      = "Telenor Denmark"

$planId  = 1
$suiteId = [int](Read-Host "Enter Suite ID")
$suiteName = (Read-Host "Enter Suite Name")
$outputFile = (Read-Host "Enter outputfilename")


if ($outputFile -notmatch '^(?:\.\\|[A-Za-z]:\\|\\\\)') {
    $outputFile = ".\$outputFile"
}
if ($outputFile -notmatch '(?i)\.csv$') {
    $outputFile += ".csv"
}


. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"


# Authentication
$securePat = Read-Host "Enter Azure DevOps PAT" -AsSecureString

$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePat)

try {
    $pat = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

$base64AuthInfo = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":$pat")
)

$headers = @{
    Authorization = "Basic $base64AuthInfo"
    Accept        = "application/json"
}


try {

    Write-Host ""
    Write-Host "Exporting test cases"
    Write-Host "Plan  : $planId"
    Write-Host "Suite : $suiteName [$suiteId]"
    Write-Host ""

    $testCases = @(RecursiveGetTestCasesInSuite `
        -Organization $organization `
        -Project $project `
        -PlanId $planId `
        -SuiteId $suiteId `
        -SuiteName $suiteName `
        -Headers $headers)

    Write-Host ""
    Write-Host "Total test cases found: $($testCases.Count)"
    Write-Host ""

    $testCases | Export-Csv `
		-Path $outputFile `
		-NoTypeInformation `
		-Delimiter ";" `
		-Encoding UTF8

    Write-Host "Export completed:"
    Write-Host $outputFile
}
catch {

    Write-Host ""
    Write-Host "ERROR"
    Write-Host $_.Exception.Message

    if ($_.ErrorDetails.Message) {
        Write-Host $_.ErrorDetails.Message
    }
}

Write-Host ""
Read-Host "Press ENTER to close"