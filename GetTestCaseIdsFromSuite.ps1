$organization = "TelenorDenmark-Prod"
$project      = "Telenor Denmark"

$planId  = 1

$suiteId = [int](Read-Host "Enter Suite ID")

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
    $testCaseIds = @(
		Get-TestCaseIdsInSuite `
			-Organization $organization `
			-Project $project `
			-PlanId $planId `
			-SuiteId $suiteId `
			-Headers $headers `
			-IncludeSubSuites
	) | Sort-Object -Unique

	Write-Host ""
	Write-Host "Found $($testCaseIds.Count) unique test cases:"
	Write-Host ""

	Write-Host ($testCaseIds -join ", ")
}
catch {
    Write-Host ""
    Write-Host "ERROR retrieving test case IDs" -ForegroundColor Red
    Write-Host ""
    Write-Host "Message:"
    Write-Host $_.Exception.Message -ForegroundColor Red

    if ($_.ErrorDetails.Message) {
        Write-Host ""
        Write-Host "ADO response:"
        Write-Host $_.ErrorDetails.Message -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Location:"
    Write-Host $_.InvocationInfo.PositionMessage
}

Write-Host ""
Read-Host "Press ENTER to close"