[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$DomainName = "adfsdemo.picketfencelabs.local",
    [string]$FederationServiceName = "adfs.adfsdemo.picketfencelabs.local"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-LocalAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated Windows PowerShell session."
    }
}

function Assert-WindowsPowerShell {
    if ($PSVersionTable.PSEdition -ne "Desktop" -or $PSVersionTable.PSVersion.Major -ne 5) {
        throw "Run this script from Windows PowerShell 5.1, not PowerShell 7."
    }
}

function Get-CurrentDomainUserUpn {
    $upn = (& whoami.exe /upn 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($upn)) {
        throw "Sign in to Windows with a domain account, then run this script from an elevated Windows PowerShell 5.1 session."
    }
    return $upn
}

function Get-AdfsFarmConfigurationState {
    $service = Get-CimInstance Win32_Service -Filter "Name = 'adfssrv'"
    if ($null -eq $service) {
        return "RoleNotInstalled"
    }

    $serviceRegistry = Get-ItemProperty `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Services\adfssrv" `
        -ErrorAction Stop
    $configurationCompletedProperty = $serviceRegistry.PSObject.Properties["InitialConfigurationCompleted"]
    $configurationCompleted = if ($null -eq $configurationCompletedProperty) {
        $null
    } else {
        $configurationCompletedProperty.Value
    }
    if ($configurationCompleted -eq 1 -or "$configurationCompleted" -eq "TRUE") {
        return "Configured"
    }

    try {
        $properties = Get-AdfsProperties -ErrorAction Stop
        if ($null -ne $properties) {
            return "Configured"
        }
    } catch {
        if ($service.State -ne "Stopped" -or $service.StartMode -ne "Manual") {
            throw "The AD FS service exists in an ambiguous state ($($service.State), $($service.StartMode)). Inspect the existing AD FS configuration before continuing."
        }
    }

    return "RoleInstalledOnly"
}

function Get-ServerIpv4Address {
    param([string]$ComputerFqdn)

    $addresses = @(
        Resolve-DnsName -Name $ComputerFqdn -Type A |
            Where-Object { $_.IPAddress } |
            Select-Object -ExpandProperty IPAddress -Unique
    )
    if ($addresses.Count -ne 1) {
        throw "Expected one IPv4 address for $ComputerFqdn, found $($addresses.Count)."
    }
    return $addresses[0]
}

Assert-WindowsPowerShell
Assert-LocalAdministrator
$currentUserUpn = Get-CurrentDomainUserUpn

$computer = Get-CimInstance Win32_ComputerSystem
if (-not $computer.PartOfDomain -or $computer.Domain -ne $DomainName) {
    throw "This server must be joined to $DomainName before configuring AD FS."
}

$computerFqdn = "$($env:COMPUTERNAME).$DomainName".ToLowerInvariant()
$serverIpv4 = Get-ServerIpv4Address -ComputerFqdn $computerFqdn
$dnsServer = Get-DnsClientServerAddress -AddressFamily IPv4 |
    Where-Object { $_.ServerAddresses.Count -gt 0 } |
    Select-Object -ExpandProperty ServerAddresses |
    Select-Object -First 1

if (-not $dnsServer) {
    throw "No IPv4 DNS server is configured on this VM."
}

$requiredFeatures = @("ADFS-Federation", "RSAT-AD-PowerShell", "RSAT-DNS-Server")
$featureState = Get-WindowsFeature -Name $requiredFeatures
$missingFeatures = @($featureState | Where-Object InstallState -ne "Installed")

Write-Host "Domain: $DomainName"
Write-Host "Current domain user: $currentUserUpn"
Write-Host "Computer FQDN: $computerFqdn"
Write-Host "Federation Service name: $FederationServiceName"
Write-Host "Server IPv4: $serverIpv4"
Write-Host "Managed domain DNS server: $dnsServer"
$featureState | Format-Table Name, InstallState

if (-not $Apply) {
    Write-Host "Preflight only. Rerun with -Apply after reviewing these values."
    return
}

if ($missingFeatures.Count -gt 0) {
    $installResult = Install-WindowsFeature -Name $missingFeatures.Name -IncludeManagementTools
    $installResult | Format-Table Success, RestartNeeded, ExitCode, FeatureResult
    if (-not $installResult.Success) {
        throw "A required Windows feature failed to install."
    }
    if ($installResult.RestartNeeded -eq "Yes") {
        throw "Restart the VM, sign in again, and rerun this script with -Apply."
    }
}

Import-Module ActiveDirectory
Import-Module DnsServer
Import-Module ADFS

$domain = Get-ADDomain -Identity $DomainName

$adfsFarmState = Get-AdfsFarmConfigurationState
if ($adfsFarmState -eq "Configured") {
    throw "An AD FS farm is already configured. This script does not overwrite an existing farm."
}
if ($adfsFarmState -eq "RoleInstalledOnly") {
    Write-Host "The AD FS role is installed, but no configured farm was detected. Continuing."
}

$recordName = $FederationServiceName.Substring(0, $FederationServiceName.Length - $DomainName.Length - 1)
$existingRecords = @(
    Get-DnsServerResourceRecord `
        -ComputerName $dnsServer `
        -ZoneName $DomainName `
        -Name $recordName `
        -RRType A `
        -ErrorAction SilentlyContinue
)

if ($existingRecords.Count -eq 0) {
    Add-DnsServerResourceRecordA `
        -ComputerName $dnsServer `
        -ZoneName $DomainName `
        -Name $recordName `
        -IPv4Address $serverIpv4 `
        -TimeToLive ([TimeSpan]::FromMinutes(5))
} else {
    $recordAddresses = @($existingRecords.RecordData.IPv4Address.IPAddressToString | Select-Object -Unique)
    if ($recordAddresses.Count -ne 1 -or $recordAddresses[0] -ne $serverIpv4) {
        throw "$FederationServiceName already resolves to an unexpected address."
    }
}

$resolvedFederationAddresses = @(
    Resolve-DnsName -Name $FederationServiceName -Type A |
        Where-Object { $_.IPAddress } |
        Select-Object -ExpandProperty IPAddress -Unique
)
if ($serverIpv4 -notin $resolvedFederationAddresses) {
    throw "$FederationServiceName does not resolve to $serverIpv4."
}

$serviceOuName = "Kong Demo Service Accounts"
$serviceOuDn = "OU=$serviceOuName,$($domain.DistinguishedName)"
if (-not (Get-ADOrganizationalUnit -Identity $serviceOuDn -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit `
        -Name $serviceOuName `
        -Path $domain.DistinguishedName `
        -ProtectedFromAccidentalDeletion $true
}

$gmsaName = "adfssvc"
$gmsaDnsHostName = "$gmsaName.$DomainName"
$gmsa = Get-ADServiceAccount -Identity $gmsaName -Properties DNSHostName, ServicePrincipalNames -ErrorAction SilentlyContinue
$computerAccount = Get-ADComputer -Identity $env:COMPUTERNAME
$requiredSpns = @("HOST/$FederationServiceName", "HOST/$recordName")

if ($null -ne $gmsa -and $gmsa.DNSHostName -ne $gmsaDnsHostName) {
    throw "The existing $gmsaName gMSA has an unexpected DNS host name."
}

foreach ($spn in $requiredSpns) {
    $owners = @(Get-ADObject -LDAPFilter "(servicePrincipalName=$spn)" -Properties servicePrincipalName)
    if ($owners.Count -gt 0 -and ($null -eq $gmsa -or $gmsa.DistinguishedName -notin $owners.DistinguishedName)) {
        throw "SPN $spn is already owned by another directory object."
    }
}

if ($null -eq $gmsa) {
    New-ADServiceAccount `
        -Name $gmsaName `
        -DNSHostName $gmsaDnsHostName `
        -Path $serviceOuDn `
        -KerberosEncryptionType AES128, AES256 `
        -ManagedPasswordIntervalInDays 30 `
        -ServicePrincipalNames $requiredSpns `
        -PrincipalsAllowedToRetrieveManagedPassword $computerAccount
} else {
    Set-ADServiceAccount `
        -Identity $gmsaName `
        -PrincipalsAllowedToRetrieveManagedPassword $computerAccount

    foreach ($spn in $requiredSpns) {
        if ($spn -notin $gmsa.ServicePrincipalNames) {
            Set-ADServiceAccount -Identity $gmsaName -ServicePrincipalNames @{ Add = $spn }
        }
    }
}

Install-ADServiceAccount -Identity $gmsaName
if (-not (Test-ADServiceAccount -Identity $gmsaName)) {
    throw "The VM cannot retrieve the gMSA password."
}

$certificate = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object {
        $_.NotAfter -gt (Get-Date).AddDays(7) -and
        $_.DnsNameList.Unicode -contains $FederationServiceName -and
        $_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.5.5.7.3.1" -and
        $_.HasPrivateKey
    } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if ($null -eq $certificate) {
    $certificate = New-SelfSignedCertificate `
        -Type SSLServerAuthentication `
        -Subject "CN=$FederationServiceName" `
        -DnsName $FederationServiceName `
        -CertStoreLocation Cert:\LocalMachine\My `
        -FriendlyName "Kong ADFS demo TLS" `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256 `
        -KeyExportPolicy NonExportable `
        -NotAfter (Get-Date).AddMonths(2)
}

$artifactDirectory = "C:\ProgramData\KongDemo"
New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
$publicCertificatePath = Join-Path $artifactDirectory "adfs-demo-root.cer"
Export-Certificate -Cert $certificate -FilePath $publicCertificatePath -Force | Out-Null

$trustedCertificate = Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object Thumbprint -eq $certificate.Thumbprint
if ($null -eq $trustedCertificate) {
    Import-Certificate `
        -FilePath $publicCertificatePath `
        -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
}

$gmsaIdentifier = "$($domain.NetBIOSName)\$gmsaName`$"
Test-AdfsFarmInstallation `
    -CertificateThumbprint $certificate.Thumbprint `
    -FederationServiceName $FederationServiceName `
    -GroupServiceAccountIdentifier $gmsaIdentifier

Install-AdfsFarm `
    -CertificateThumbprint $certificate.Thumbprint `
    -FederationServiceName $FederationServiceName `
    -FederationServiceDisplayName "Picketfence Labs ADFS Demo" `
    -GroupServiceAccountIdentifier $gmsaIdentifier `
    -Confirm:$false

$service = Get-Service adfssrv
if ($service.Status -ne "Running") {
    Start-Service adfssrv
    $service = Get-Service adfssrv
}

$discoveryUri = "https://$FederationServiceName/adfs/.well-known/openid-configuration"
$discovery = Invoke-RestMethod -Uri $discoveryUri -UseBasicParsing
if ($discovery.issuer -ne "https://$FederationServiceName/adfs") {
    throw "The discovery issuer does not match the expected AD FS issuer."
}

Write-Host "AD FS farm created."
Write-Host "Issuer: $($discovery.issuer)"
Write-Host "Service state: $($service.Status)"
Write-Host "Public trust certificate: $publicCertificatePath"
