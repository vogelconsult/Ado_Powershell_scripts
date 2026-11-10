$organization = "TelenorDenmark-Prod"
$project      = "Telenor Denmark"

$planId  = 1

$suiteId = [int](Read-Host "Enter Suite ID")
$suiteName = Read-Host "Enter Suite name"
$State = Read-Host "enter state you want to put ALL testcases in suite in"

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
	
	RecursiveSetTestCaseState `
		-Organization $Organization `
		-Project $Project `
		-PlanId $PlanId `
		-SuiteId $SuiteId `
		-SuiteName $SuiteName `
		-Headers $Headers `
		-State $State

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