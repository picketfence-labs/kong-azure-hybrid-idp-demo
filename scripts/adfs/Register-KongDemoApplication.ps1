[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$FederationServiceName = "adfs.adfsdemo.picketfencelabs.local",
    [uri]$RedirectUri = "http://localhost:8000/adfs/auth/callback"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$applicationGroupName = "Kong Insurance ADFS Demo"
$applicationGroupIdentifier = "cb6a5afd-2cbb-4752-8df9-e4ae749973c8"
$clientIdentifier = "5923191c-da9f-4c23-ac6f-dd7be8b5b93a"
$webApiIdentifier = "urn:kong:insurance-api"
$departmentClaim = "https://picketfencelabs.local/claims/department"
$allowedDepartments = @("it", "sales", "new-business", "policy-admin", "claim")
$requiredScopes = @("openid", "profile", "allatclaims", "user_impersonation")

Import-Module ADFS

$service = Get-Service adfssrv -ErrorAction Stop
if ($service.Status -ne "Running") {
    throw "The AD FS service must be running before registering the application."
}

$adfsProperties = Get-AdfsProperties
if ($adfsProperties.HostName -ne $FederationServiceName) {
    throw "The configured Federation Service name does not match $FederationServiceName."
}

Write-Host "Application group: $applicationGroupName"
Write-Host "Client ID: $clientIdentifier"
Write-Host "Web API identifier: $webApiIdentifier"
Write-Host "Redirect URI: $RedirectUri"
Write-Host "Department claim: $departmentClaim"
Write-Host "Scopes: $($requiredScopes -join ', ')"

if (-not $Apply) {
    Write-Host "Preflight only. Rerun with -Apply after reviewing these values."
    return
}

$applicationGroup = Get-AdfsApplicationGroup -Name $applicationGroupName -ErrorAction SilentlyContinue
if ($null -eq $applicationGroup) {
    $applicationGroup = New-AdfsApplicationGroup `
        -Name $applicationGroupName `
        -ApplicationGroupIdentifier $applicationGroupIdentifier `
        -Description "Confidential Kong client and protected insurance Web API" `
        -PassThru
} elseif ($applicationGroup.ApplicationGroupIdentifier -ne $applicationGroupIdentifier) {
    throw "An application group with the same name has an unexpected identifier."
}

$secretDirectory = Join-Path $env:LOCALAPPDATA "KongDemo"
$encryptedSecretPath = Join-Path $secretDirectory "adfs-kong-client-secret.dpapi"
$metadataPath = Join-Path $secretDirectory "adfs-kong-client.json"
New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null

$serverApplication = Get-AdfsServerApplication -Identifier $clientIdentifier -ErrorAction SilentlyContinue
if ($null -eq $serverApplication) {
    $serverApplication = Add-AdfsServerApplication `
        -ApplicationGroupIdentifier $applicationGroupIdentifier `
        -Name "Kong Gateway confidential client" `
        -Identifier $clientIdentifier `
        -RedirectUri @($RedirectUri.AbsoluteUri) `
        -GenerateClientSecret `
        -PassThru

    $secureClientSecret = ConvertTo-SecureString $serverApplication.ClientSecret -AsPlainText -Force
    ConvertFrom-SecureString $secureClientSecret | Set-Content -Path $encryptedSecretPath
} else {
    $registeredRedirectUris = @($serverApplication.RedirectUri | ForEach-Object { $_.ToString() })
    if ($serverApplication.ApplicationGroupIdentifier -ne $applicationGroupIdentifier) {
        throw "The existing server application belongs to an unexpected application group."
    }
    if ($registeredRedirectUris.Count -ne 1 -or $registeredRedirectUris[0] -ne $RedirectUri.AbsoluteUri) {
        throw "The existing server application has an unexpected redirect URI."
    }
    if (-not (Test-Path $encryptedSecretPath)) {
        throw "The client exists but its DPAPI-protected secret file is missing. Do not reset the secret without review."
    }
    $secureClientSecret = Get-Content $encryptedSecretPath | ConvertTo-SecureString
}

$authorizationRules = @"
@RuleName = "Load demo department"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"]
 => add(store = "Active Directory", types = ("$departmentClaim"), query = ";department;{0}", param = c.Value);

@RuleName = "Permit expected demo departments"
c:[Type == "$departmentClaim", Value =~ "^($($allowedDepartments -join '|'))$"]
 => issue(Type = "http://schemas.microsoft.com/authorization/claims/permit", Value = "true");
"@

$transformRules = @"
@RuleName = "Issue department"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"]
 => issue(store = "Active Directory", types = ("$departmentClaim"), query = ";department;{0}", param = c.Value);
"@

$webApiApplication = Get-AdfsWebApiApplication -Identifier $webApiIdentifier -ErrorAction SilentlyContinue
if ($null -eq $webApiApplication) {
    $webApiApplication = Add-AdfsWebApiApplication `
        -ApplicationGroupIdentifier $applicationGroupIdentifier `
        -Name "Kong Insurance Web API" `
        -Identifier @($webApiIdentifier) `
        -IssuanceAuthorizationRules $authorizationRules `
        -IssuanceTransformRules $transformRules `
        -PassThru
} else {
    if ($webApiIdentifier -notin $webApiApplication.Identifier) {
        throw "The existing Web API application has an unexpected identifier."
    }
    if ($webApiApplication.ApplicationGroupIdentifier -ne $applicationGroupIdentifier) {
        throw "The existing Web API application belongs to an unexpected application group."
    }
    if ($webApiApplication.IssuanceAuthorizationRules -notmatch [regex]::Escape($departmentClaim) -or
        $webApiApplication.IssuanceTransformRules -notmatch [regex]::Escape($departmentClaim)) {
        throw "The existing Web API application does not contain the expected department claim rules."
    }
}

$permissions = @(Get-AdfsApplicationPermission -ClientRoleIdentifiers $clientIdentifier)
$permission = $permissions |
    Where-Object ServerRoleIdentifier -eq $webApiIdentifier |
    Select-Object -First 1

if ($null -eq $permission) {
    Grant-AdfsApplicationPermission `
        -ClientRoleIdentifier $clientIdentifier `
        -ServerRoleIdentifier $webApiIdentifier `
        -ScopeNames $requiredScopes | Out-Null
} else {
    $missingScopes = @($requiredScopes | Where-Object { $_ -notin $permission.ScopeNames })
    $unexpectedScopes = @($permission.ScopeNames | Where-Object { $_ -notin $requiredScopes })
    if ($missingScopes.Count -gt 0 -or $unexpectedScopes.Count -gt 0) {
        throw "The existing application permission does not have the expected exact scope set."
    }
}

$metadata = [ordered]@{
    issuer = "https://$FederationServiceName/adfs"
    client_id = $clientIdentifier
    resource = $webApiIdentifier
    claim_name = $departmentClaim
    redirect_uri = $RedirectUri.AbsoluteUri
    scopes = $requiredScopes
    encrypted_secret_path = $encryptedSecretPath
}
$metadata | ConvertTo-Json | Set-Content -Path $metadataPath -Encoding UTF8

$secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureClientSecret)
try {
    $plainClientSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
    Set-Clipboard -Value $plainClientSecret
} finally {
    if ($secretPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
    }
    Remove-Variable plainClientSecret -ErrorAction SilentlyContinue
}

Write-Host "AD FS application registration completed."
Write-Host "Non-secret metadata: $metadataPath"
Write-Host "The client secret is on the clipboard and is not printed. Store it in the local untracked environment file."
