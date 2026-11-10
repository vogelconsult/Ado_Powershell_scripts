function Get-AdoAuthenticationHeaders {
    [CmdletBinding()]
    param()

    $securePat = Read-Host "Enter Azure DevOps PAT" -AsSecureString

    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        $securePat
    )

    try {
        $pat = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }

    try {
        $base64AuthInfo = [Convert]::ToBase64String(
            [Text.Encoding]::ASCII.GetBytes(":$pat")
        )
    }
    finally {
        $pat = $null
    }

    return @{
        Authorization = "Basic $base64AuthInfo"
        Accept        = "application/json"
    }
}

function Get-OrgAndProjectConfiguration {
    [CmdletBinding()]
    param()

    return @{
        Organization = "TelenorDenmark-Prod"
        Project      = "Telenor Denmark"
    }
}

