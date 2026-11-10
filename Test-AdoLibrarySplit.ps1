# Offline structural validation of the split ADO library (Windows PowerShell 5.1).
# No ADO calls or write operations to the user's Azure DevOps project are made.
[CmdletBinding()]
param(
    [string]$LibraryPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Shared')
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PSScriptRoot 'FunctionInventory.csv'
$manifest = @(Import-Csv -LiteralPath $manifestPath)
$expectedFiles = @(
    'SharedAdoFunctions.ps1', 'AdoConfiguration.ps1', 'AdoUtilities.ps1',
    'AdoSuites.ps1', 'AdoTestCases.ps1', 'AdoCloning.ps1', 'AdoImport.ps1',
    'AdoTestExecution.ps1', 'AdoReporting.ps1'
)

function Get-StringSha256 {
    param([Parameter(Mandatory)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

if ($manifest.Count -ne 52) {
    throw "Expected 52 manifest entries; found $($manifest.Count)."
}

$found = @()
foreach ($file in $expectedFiles) {
    $path = Join-Path -Path $LibraryPath -ChildPath $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing file: $path"
    }
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        foreach ($errorItem in $errors) { Write-Error "$($errorItem.Extent): $($errorItem.Message)" }
        throw "PowerShell parsing failed: $file"
    }
    $definitions = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true))
    foreach ($definition in $definitions) {
        $found += [PSCustomObject]@{
            File     = $file
            Function = $definition.Name
            SHA256   = Get-StringSha256 -Text $definition.Extent.Text
        }
    }
    Write-Host "PASS: $file parses ($($definitions.Count) functions)"
}

if ($found.Count -ne 52) {
    throw "Expected 52 functions, found $($found.Count)."
}
if (@($found | Group-Object Function | Where-Object Count -gt 1).Count -gt 0) {
    throw 'Duplicate function names detected.'
}

foreach ($expected in $manifest) {
    $match = @($found | Where-Object { $_.Function -eq $expected.Function })
    if ($match.Count -ne 1) { throw "Function missing or duplicated: $($expected.Function)" }
    if ($match[0].File -ne $expected.File) {
        throw "Incorrect file assignment: $($expected.Function) expected in $($expected.File)"
    }
    if ($match[0].SHA256 -ne $expected.SHA256) {
        throw "Function implementation differs from source: $($expected.Function)"
    }
}
Write-Host 'PASS: All 52 function bodies and file assignments match the source.' -ForegroundColor Green

# Dot-source inside a child scope so this validation does not leave library functions in the caller.
& {
    . (Join-Path -Path $LibraryPath -ChildPath 'SharedAdoFunctions.ps1')
    foreach ($entry in $manifest) {
        if (-not (Get-Command -Name $entry.Function -CommandType Function -ErrorAction SilentlyContinue)) {
            throw "Loader did not make function available: $($entry.Function)"
        }
    }
}
Write-Host 'PASS: Loader exposes all 52 functions.' -ForegroundColor Green
Write-Host 'PASS: Structural validation completed. API behavior and Excel export still require regression testing.' -ForegroundColor Green
