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

function Get-CertificateDnsNames {
    param([object]$Certificate)

    $dnsNameListProperty = $Certificate.PSObject.Properties["DnsNameList"]
    if ($null -eq $dnsNameListProperty -or $null -eq $dnsNameListProperty.Value) {
        return
    }

    foreach ($dnsName in @($dnsNameListProperty.Value)) {
        if ($null -eq $dnsName) {
            continue
        }
        if ($dnsName -is [string]) {
            $dnsName
            continue
        }

        $unicodeProperty = $dnsName.PSObject.Properties["Unicode"]
        if ($null -ne $unicodeProperty) {
            [string]$unicodeProperty.Value
        } else {
            [string]$dnsName
        }
    }
}

function Test-CertificateServerAuthentication {
    param([object]$Certificate)

    $serverAuthenticationOid = "1.3.6.1.5.5.7.3.1"
    foreach ($extension in @($Certificate.Extensions)) {
        if ($null -eq $extension.Oid -or $extension.Oid.Value -ne "2.5.29.37") {
            continue
        }

        $ekuExtension = if ($extension -is [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
            $extension
        } else {
            [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new(
                $extension,
                $extension.Critical
            )
        }
        foreach ($usage in $ekuExtension.EnhancedKeyUsages) {
            if ($usage.Value -eq $serverAuthenticationOid) {
                return $true
            }
        }
    }
    return $false
}

function Test-AdfsDemoCertificate {
    param(
        [object]$Certificate,
        [string]$FederationServiceName
    )

    $dnsNames = @(Get-CertificateDnsNames -Certificate $Certificate)
    return (
        $Certificate.NotAfter -gt (Get-Date).AddDays(7) -and
        $FederationServiceName -in $dnsNames -and
        (Test-CertificateServerAuthentication -Certificate $Certificate) -and
        $Certificate.HasPrivateKey
    )
}

function Assert-AdfsDeploymentResults {
    param(
        [object[]]$Results,
        [string]$Operation
    )

    if ($Results.Count -eq 0) {
        throw "$Operation returned no result."
    }

    $failures = @(
        foreach ($result in $Results) {
            if ($null -eq $result) {
                [pscustomobject]@{ Status = "Error"; Message = "Null result" }
                continue
            }
            $statusProperty = $result.PSObject.Properties["Status"]
            if ($null -eq $statusProperty -or "$($statusProperty.Value)" -ne "Success") {
                $result
            }
        }
    )
    if ($failures.Count -eq 0) {
        return
    }

    $messages = @(
        foreach ($failure in $failures) {
            $messageProperty = $failure.PSObject.Properties["Message"]
            if ($null -ne $messageProperty -and -not [string]::IsNullOrWhiteSpace("$($messageProperty.Value)")) {
                "$($messageProperty.Value)"
            } else {
                $statusProperty = $failure.PSObject.Properties["Status"]
                if ($null -eq $statusProperty) { "Unknown status" } else { "$($statusProperty.Value)" }
            }
        }
    )
    throw "$Operation failed: $($messages -join ' | ')"
}

function Wait-AdfsDiscovery {
    param(
        [uri]$DiscoveryUri,
        [string]$ExpectedIssuer
    )

    $lastError = "No response"
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        try {
            $discovery = Invoke-RestMethod -Uri $DiscoveryUri -UseBasicParsing -TimeoutSec 10
            if ($discovery.issuer -eq $ExpectedIssuer) {
                return $discovery
            }
            $lastError = "Unexpected issuer: $($discovery.issuer)"
        } catch {
            $lastError = $_.Exception.Message
        }

        if ($attempt -lt 12) {
            Start-Sleep -Seconds 5
        }
    }
    throw "AD FS discovery did not become ready within 60 seconds. Last error: $lastError"
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

if ($missingFeatures.Count -gt 0) {
    if (-not $Apply) {
        Write-Host "Feature preflight only. Rerun with -Apply to install the missing features."
        return
    }

    $installResult = Install-WindowsFeature -Name $missingFeatures.Name -IncludeManagementTools
    $installResult | Format-Table Success, RestartNeeded, ExitCode, FeatureResult
    if (-not $installResult.Success) {
        throw "A required Windows feature failed to install."
    }
    if ($installResult.RestartNeeded -eq "Yes") {
        throw "Restart the VM, sign in again, and rerun this script with -Apply."
    }
    Write-Host "Required Windows features were installed. Rerun without -Apply for the deep preflight."
    return
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

if (-not $FederationServiceName.EndsWith(".$DomainName", [StringComparison]::OrdinalIgnoreCase)) {
    throw "The Federation Service name must be a child name of $DomainName."
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

if ($existingRecords.Count -gt 0) {
    $recordAddresses = @($existingRecords.RecordData.IPv4Address.IPAddressToString | Select-Object -Unique)
    if ($recordAddresses.Count -ne 1 -or $recordAddresses[0] -ne $serverIpv4) {
        throw "$FederationServiceName already resolves to an unexpected address."
    }
}

$serviceOuName = "Kong Demo Service Accounts"
$serviceOuDn = "OU=$serviceOuName,$($domain.DistinguishedName)"
$serviceOus = @(
    Get-ADOrganizationalUnit `
        -Filter { Name -eq $serviceOuName } `
        -SearchBase $domain.DistinguishedName `
        -SearchScope OneLevel
)
if ($serviceOus.Count -gt 1) {
    throw "Multiple service account OUs named $serviceOuName were found directly under the domain root."
}

$gmsaName = "adfssvc"
$gmsaDnsHostName = "$gmsaName.$DomainName"
$gmsaSamAccountName = "$gmsaName`$"
$gmsaMatches = @(
    Get-ADServiceAccount `
        -Filter { SamAccountName -eq $gmsaSamAccountName } `
        -SearchBase $domain.DistinguishedName `
        -SearchScope Subtree `
        -Properties DNSHostName, ServicePrincipalNames
)
if ($gmsaMatches.Count -gt 1) {
    throw "Multiple gMSAs with SAM account name $gmsaSamAccountName were found."
}
$gmsa = $gmsaMatches | Select-Object -First 1
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

$certificateFriendlyName = "Kong ADFS demo TLS"
$certificate = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object {
        $_.FriendlyName -eq $certificateFriendlyName -and
        $_.Subject -eq "CN=$FederationServiceName" -and
        (Test-AdfsDemoCertificate -Certificate $_ -FederationServiceName $FederationServiceName)
    } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

$dnsPlan = if ($existingRecords.Count -eq 0) { "Create" } else { "Reuse" }
$ouPlan = if ($serviceOus.Count -eq 0) { "Create" } else { "Reuse" }
$gmsaPlan = if ($null -eq $gmsa) { "Create" } else { "Reuse" }
$certificatePlan = if ($null -eq $certificate) { "Create" } else { "Reuse" }
Write-Host "AD FS farm state: $adfsFarmState"
Write-Host "DNS A record: $dnsPlan"
Write-Host "Service account OU: $ouPlan"
Write-Host "gMSA: $gmsaPlan"
Write-Host "TLS certificate: $certificatePlan"

if (-not $Apply) {
    Write-Host "Deep preflight only. No DNS, directory, certificate, or AD FS changes were made."
    Write-Host "Rerun with -Apply after reviewing these values."
    return
}

if ($existingRecords.Count -eq 0) {
    Add-DnsServerResourceRecordA `
        -ComputerName $dnsServer `
        -ZoneName $DomainName `
        -Name $recordName `
        -IPv4Address $serverIpv4 `
        -TimeToLive ([TimeSpan]::FromMinutes(5))
}

$resolvedFederationAddresses = @(
    Resolve-DnsName -Name $FederationServiceName -Type A |
        Where-Object { $_.IPAddress } |
        Select-Object -ExpandProperty IPAddress -Unique
)
if ($serverIpv4 -notin $resolvedFederationAddresses) {
    throw "$FederationServiceName does not resolve to $serverIpv4."
}

if ($serviceOus.Count -eq 0) {
    New-ADOrganizationalUnit `
        -Name $serviceOuName `
        -Path $domain.DistinguishedName `
        -ProtectedFromAccidentalDeletion $true
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

$gmsaReady = $false
try {
    $gmsaReady = [bool](Test-ADServiceAccount -Identity $gmsaName -ErrorAction Stop)
} catch {
    $gmsaReady = $false
}
if (-not $gmsaReady) {
    Install-ADServiceAccount -Identity $gmsaName
}
if (-not (Test-ADServiceAccount -Identity $gmsaName)) {
    throw "The VM cannot retrieve the gMSA password."
}

if ($null -eq $certificate) {
    $certificate = New-SelfSignedCertificate `
        -Type SSLServerAuthentication `
        -Subject "CN=$FederationServiceName" `
        -DnsName $FederationServiceName `
        -CertStoreLocation Cert:\LocalMachine\My `
        -FriendlyName $certificateFriendlyName `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256 `
        -KeyExportPolicy NonExportable `
        -NotAfter (Get-Date).AddMonths(2)
}
if (-not (Test-AdfsDemoCertificate -Certificate $certificate -FederationServiceName $FederationServiceName)) {
    throw "The selected TLS certificate does not meet the Federation Service name, server authentication, private key, and validity requirements."
}

$artifactDirectory = "C:\ProgramData\KongDemo"
New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
$publicCertificatePath = Join-Path $artifactDirectory "adfs-demo-root.cer"
Export-Certificate -Cert $certificate -FilePath $publicCertificatePath -Force | Out-Null

$trustedCertificates = @(
    Get-ChildItem Cert:\LocalMachine\Root |
        Where-Object Thumbprint -eq $certificate.Thumbprint
)
if ($trustedCertificates.Count -eq 0) {
    Import-Certificate `
        -FilePath $publicCertificatePath `
        -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
}

$gmsaIdentifier = "$($domain.NetBIOSName)\$gmsaName`$"
$prerequisiteResults = @(
    Test-AdfsFarmInstallation `
        -CertificateThumbprint $certificate.Thumbprint `
        -FederationServiceName $FederationServiceName `
        -GroupServiceAccountIdentifier $gmsaIdentifier `
        -ErrorAction SilentlyContinue
)
Assert-AdfsDeploymentResults `
    -Results $prerequisiteResults `
    -Operation "AD FS farm prerequisite check"

$installationResults = @(
    Install-AdfsFarm `
        -CertificateThumbprint $certificate.Thumbprint `
        -FederationServiceName $FederationServiceName `
        -FederationServiceDisplayName "Picketfence Labs ADFS Demo" `
        -GroupServiceAccountIdentifier $gmsaIdentifier `
        -Confirm:$false `
        -ErrorAction SilentlyContinue
)
Assert-AdfsDeploymentResults `
    -Results $installationResults `
    -Operation "AD FS farm installation"

$service = Get-Service adfssrv
if ($service.Status -ne "Running") {
    Start-Service adfssrv
    $service = Get-Service adfssrv
}

$discoveryUri = "https://$FederationServiceName/adfs/.well-known/openid-configuration"
$expectedIssuer = "https://$FederationServiceName/adfs"
$discovery = Wait-AdfsDiscovery `
    -DiscoveryUri $discoveryUri `
    -ExpectedIssuer $expectedIssuer

Write-Host "AD FS farm created."
Write-Host "Issuer: $($discovery.issuer)"
Write-Host "Service state: $($service.Status)"
Write-Host "Public trust certificate: $publicCertificatePath"
