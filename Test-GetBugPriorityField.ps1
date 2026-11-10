
# Test-GetBugPriorityField.ps1
# Find the ADO reference name for the custom "Bug Priority" field.

. "$PSScriptRoot\Shared\SharedAdoFunctions.ps1"

# Authentication and configuration
$config = Get-OrgAndProjectConfiguration
$headers = Get-AdoAuthenticationHeaders

# Build ADO API URL
$organization = $config.Organization
$project = [uri]::EscapeDataString($config.Project)

$baseUrl = "https://dev.azure.com/$organization/$project"
$url = "$baseUrl/_apis/wit/fields?api-version=7.1"

Write-Host ""
Write-Host "Searching for Bug Priority field in ADO..." -ForegroundColor Cyan
Write-Host "Organization: $organization"
Write-Host "Project: $($config.Project)"
Write-Host ""

try {
    # Retrieve field definitions
    $response = Invoke-RestMethod `
        -Uri $url `
        -Headers $headers `
        -Method Get `
        -ErrorAction Stop

    # Find fields containing "Bug Priority"
    $fields = @(
        $response.value |
            Where-Object {
                $_.name -like '*Bug Priority*' -or
                $_.referenceName -like '*BugPriority*'
            }
    )

    if ($fields.Count -eq 0) {
        Write-Warning "No matching fields found."

        Write-Host ""
        Write-Host "Other fields containing 'Priority':"

        $response.value |
            Where-Object {
                $_.name -like '*Priority*'
            } |
            Select-Object name, referenceName, type |
            Format-Table -AutoSize
    }
    else {
        Write-Host "Matching fields:" -ForegroundColor Green

        $fields |
            Select-Object name, referenceName, type |
            Format-Table -AutoSize

        Write-Host ""
        Write-Host "Use the referenceName in Get-TestDefectDetails."
    }
}
catch {
    Write-Host "ADO API request failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    throw
}
