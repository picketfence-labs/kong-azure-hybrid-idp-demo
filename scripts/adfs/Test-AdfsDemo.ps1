[CmdletBinding()]
param(
    [string]$DomainName = "adfsdemo.picketfencelabs.local",
    [string]$FederationServiceName = "adfs.adfsdemo.picketfencelabs.local"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$applicationGroupName = "Kong Insurance ADFS Demo"
$applicationGroupIdentifier = "cb6a5afd-2cbb-4752-8df9-e4ae749973c8"
$clientIdentifier = "5923191c-da9f-4c23-ac6f-dd7be8b5b93a"
$webApiIdentifier = "urn:kong:insurance-api"
$departmentClaim = "https://picketfencelabs.local/claims/department"
$redirectUri = "http://localhost:8000/adfs/auth/callback"
$requiredScopes = @("openid", "profile", "allatclaims", "user_impersonation")

Import-Module ActiveDirectory
Import-Module ADFS

$failures = [Collections.Generic.List[string]]::new()

$feature = Get-WindowsFeature ADFS-Federation
if ($feature.InstallState -ne "Installed") {
    $failures.Add("ADFS-Federation is not installed.")
}

$service = Get-Service adfssrv -ErrorAction SilentlyContinue
if ($null -eq $service -or $service.Status -ne "Running") {
    $failures.Add("The AD FS service is not running.")
}

$properties = Get-AdfsProperties
if ($properties.HostName -ne $FederationServiceName) {
    $failures.Add("The Federation Service name is unexpected.")
}

$resolvedAddresses = @(
    Resolve-DnsName -Name $FederationServiceName -Type A |
        Where-Object { $_.IPAddress } |
        Select-Object -ExpandProperty IPAddress -Unique
)
if ($resolvedAddresses.Count -eq 0) {
    $failures.Add("The Federation Service name has no A record.")
}

if (-not (Test-ADServiceAccount -Identity adfssvc)) {
    $failures.Add("The VM cannot use the adfssvc gMSA.")
}

$spnOwners = @(Get-ADObject -LDAPFilter "(servicePrincipalName=HOST/$FederationServiceName)" -Properties servicePrincipalName)
if ($spnOwners.Count -ne 1 -or $spnOwners[0].Name -ne "adfssvc") {
    $failures.Add("The Federation Service SPN is not owned only by adfssvc.")
}

$sslCertificate = Get-AdfsSslCertificate |
    Where-Object HostName -eq $FederationServiceName |
    Select-Object -First 1
if ($null -eq $sslCertificate) {
    $failures.Add("No AD FS TLS binding exists for the Federation Service name.")
}

$discoveryUri = "https://$FederationServiceName/adfs/.well-known/openid-configuration"
$discovery = Invoke-RestMethod -Uri $discoveryUri -UseBasicParsing
if ($discovery.issuer -ne "https://$FederationServiceName/adfs") {
    $failures.Add("The discovery issuer is unexpected.")
}

$applicationGroup = Get-AdfsApplicationGroup -Name $applicationGroupName -ErrorAction SilentlyContinue
if ($null -eq $applicationGroup) {
    $failures.Add("The Kong application group is missing.")
} elseif ($applicationGroup.ApplicationGroupIdentifier -ne $applicationGroupIdentifier) {
    $failures.Add("The Kong application group identifier is unexpected.")
}

$serverApplication = Get-AdfsServerApplication -Identifier $clientIdentifier -ErrorAction SilentlyContinue
if ($null -eq $serverApplication) {
    $failures.Add("The Kong server application is missing.")
} else {
    $registeredRedirectUris = @($serverApplication.RedirectUri | ForEach-Object { $_.ToString() })
    if ($registeredRedirectUris.Count -ne 1 -or $registeredRedirectUris[0] -ne $redirectUri) {
        $failures.Add("The Kong server application redirect URI is unexpected.")
    }
}

$webApiApplication = Get-AdfsWebApiApplication -Identifier $webApiIdentifier -ErrorAction SilentlyContinue
if ($null -eq $webApiApplication) {
    $failures.Add("The Kong Web API application is missing.")
} elseif ($webApiApplication.IssuanceTransformRules -notmatch [regex]::Escape($departmentClaim)) {
    $failures.Add("The Web API does not issue the configured department claim.")
} elseif ($webApiApplication.IssuanceAuthorizationRules -notmatch [regex]::Escape($departmentClaim)) {
    $failures.Add("The Web API does not authorize with the configured department claim.")
}

$permission = Get-AdfsApplicationPermission -ClientRoleIdentifiers $clientIdentifier |
    Where-Object ServerRoleIdentifier -eq $webApiIdentifier |
    Select-Object -First 1
if ($null -eq $permission) {
    $failures.Add("The Kong client has no permission for the Web API.")
} else {
    $missingScopes = @($requiredScopes | Where-Object { $_ -notin $permission.ScopeNames })
    $unexpectedScopes = @($permission.ScopeNames | Where-Object { $_ -notin $requiredScopes })
    if ($missingScopes.Count -gt 0 -or $unexpectedScopes.Count -gt 0) {
        $failures.Add("The Kong client permission scope set is unexpected.")
    }
}

$demoUsers = @(
    Get-ADUser -LDAPFilter "(displayName=Demo User - *)" -Properties department, userPrincipalName |
        Select-Object userPrincipalName, department |
        Sort-Object userPrincipalName
)
if ($demoUsers.Count -ne 5) {
    $failures.Add("Expected five demo users, found $($demoUsers.Count).")
}

$serviceStatus = if ($null -eq $service) { "Missing" } else { $service.Status }
Write-Host "AD FS service: $serviceStatus"
Write-Host "Issuer: $($discovery.issuer)"
Write-Host "Authorization endpoint: $($discovery.authorization_endpoint)"
Write-Host "Token endpoint: $($discovery.token_endpoint)"
Write-Host "JWKS URI: $($discovery.jwks_uri)"
Write-Host "DNS addresses: $($resolvedAddresses -join ', ')"
$demoUsers | Format-Table userPrincipalName, department

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Warning $_ }
    throw "AD FS verification failed with $($failures.Count) issue(s)."
}

Write-Host "AD FS farm and application registration checks passed."
Write-Host "Interactive sign-in and token claim verification remain separate browser tests."
