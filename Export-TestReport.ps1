param(
    [int]$SuiteId = 0,
    [string]$OutputPath
)

. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"

$config = Get-OrgAndProjectConfiguration
$headers = Get-AdoAuthenticationHeaders
$planId = 1

if ($SuiteId -eq 0) {
    $SuiteId = [int](Read-Host 'Enter Suite ID')
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "TestReport_$SuiteId.xlsx"
}

Export-TestReport `
    -Organization $config.Organization `
    -Project $config.Project `
    -Headers $headers `
    -PlanId $planId `
    -SuiteId $SuiteId `
    -OutputPath $OutputPath
