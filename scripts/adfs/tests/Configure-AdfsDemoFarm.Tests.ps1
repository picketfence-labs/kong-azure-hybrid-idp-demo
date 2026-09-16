$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptPath = Join-Path $PSScriptRoot "..\Configure-AdfsDemoFarm.ps1"
$scriptSource = Get-Content -Path $scriptPath -Raw
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw "Configure-AdfsDemoFarm.ps1 has parse errors."
}

$functionNames = @(
    "Get-CertificateDnsNames",
    "Test-CertificateServerAuthentication",
    "Test-AdfsDemoCertificate",
    "Assert-AdfsDeploymentResults",
    "Wait-AdfsDiscovery"
)
foreach ($functionName in $functionNames) {
    $functionAst = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $functionName
    }, $true)
    if ($null -eq $functionAst) {
        throw "Missing function: $functionName"
    }
    Invoke-Expression $functionAst.Extent.Text
}

function Assert-True {
    param([bool]$Value, [string]$Case)
    if (-not $Value) {
        throw "Assertion failed: $Case"
    }
}

function Assert-False {
    param([bool]$Value, [string]$Case)
    if ($Value) {
        throw "Assertion failed: $Case"
    }
}

$serverAuthenticationOids = [Security.Cryptography.OidCollection]::new()
$null = $serverAuthenticationOids.Add(
    [Security.Cryptography.Oid]::new("1.3.6.1.5.5.7.3.1")
)
$serverAuthenticationExtension = [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new(
    $serverAuthenticationOids,
    $false
)

$validCertificate = [pscustomobject]@{
    DnsNameList = @([pscustomobject]@{ Unicode = "adfs.example.test" })
    Extensions = @($serverAuthenticationExtension)
    NotAfter = (Get-Date).AddDays(30)
    HasPrivateKey = $true
}
$nullDnsCertificate = [pscustomobject]@{
    DnsNameList = $null
    Extensions = @($serverAuthenticationExtension)
    NotAfter = (Get-Date).AddDays(30)
    HasPrivateKey = $true
}
$noEkuCertificate = [pscustomobject]@{
    DnsNameList = @([pscustomobject]@{ Unicode = "adfs.example.test" })
    Extensions = @()
    NotAfter = (Get-Date).AddDays(30)
    HasPrivateKey = $true
}
$noPrivateKeyCertificate = [pscustomobject]@{
    DnsNameList = @([pscustomobject]@{ Unicode = "adfs.example.test" })
    Extensions = @($serverAuthenticationExtension)
    NotAfter = (Get-Date).AddDays(30)
    HasPrivateKey = $false
}
$expiringCertificate = [pscustomobject]@{
    DnsNameList = @([pscustomobject]@{ Unicode = "adfs.example.test" })
    Extensions = @($serverAuthenticationExtension)
    NotAfter = (Get-Date).AddDays(2)
    HasPrivateKey = $true
}

Assert-True `
    -Value (Test-AdfsDemoCertificate -Certificate $validCertificate -FederationServiceName "adfs.example.test") `
    -Case "valid certificate"
Assert-False `
    -Value (Test-AdfsDemoCertificate -Certificate $nullDnsCertificate -FederationServiceName "adfs.example.test") `
    -Case "null DNS name list"
Assert-False `
    -Value (Test-AdfsDemoCertificate -Certificate $noEkuCertificate -FederationServiceName "adfs.example.test") `
    -Case "missing server authentication EKU"
Assert-False `
    -Value (Test-AdfsDemoCertificate -Certificate $noPrivateKeyCertificate -FederationServiceName "adfs.example.test") `
    -Case "missing private key"
Assert-False `
    -Value (Test-AdfsDemoCertificate -Certificate $expiringCertificate -FederationServiceName "adfs.example.test") `
    -Case "certificate expires within seven days"
Assert-False `
    -Value (Test-AdfsDemoCertificate -Certificate $validCertificate -FederationServiceName "wrong.example.test") `
    -Case "wrong federation service name"

Assert-AdfsDeploymentResults `
    -Results @([pscustomobject]@{ Status = "Success"; Message = "ok" }) `
    -Operation "success case"

$resultFailureDetected = $false
try {
    Assert-AdfsDeploymentResults `
        -Results @([pscustomobject]@{ Status = "Error"; Message = "expected failure" }) `
        -Operation "failure case"
} catch {
    $resultFailureDetected = $_.Exception.Message -match "expected failure"
}
Assert-True -Value $resultFailureDetected -Case "AD FS error result"

$emptyResultDetected = $false
try {
    Assert-AdfsDeploymentResults -Results @() -Operation "empty case"
} catch {
    $emptyResultDetected = $_.Exception.Message -match "returned no result"
}
Assert-True -Value $emptyResultDetected -Case "empty AD FS result"

$nullResultDetected = $false
try {
    Assert-AdfsDeploymentResults -Results @($null) -Operation "null case"
} catch {
    $nullResultDetected = $_.Exception.Message -match "Null result"
}
Assert-True -Value $nullResultDetected -Case "null AD FS result"

$script:discoveryAttempt = 0
function Invoke-RestMethod {
    $script:discoveryAttempt++
    if ($script:discoveryAttempt -lt 3) {
        throw "not ready"
    }
    return [pscustomobject]@{ issuer = "https://adfs.example.test/adfs" }
}
function Start-Sleep {}

$discovery = Wait-AdfsDiscovery `
    -DiscoveryUri "https://adfs.example.test/adfs/.well-known/openid-configuration" `
    -ExpectedIssuer "https://adfs.example.test/adfs"
Assert-True -Value ($discovery.issuer -eq "https://adfs.example.test/adfs") -Case "discovery retry"
Assert-True -Value ($script:discoveryAttempt -eq 3) -Case "discovery attempt count"

$deepPreflightMarker = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.StringConstantExpressionAst] -and
        $node.Value -like "Deep preflight only.*"
}, $true)
if ($null -eq $deepPreflightMarker) {
    throw "The deep preflight marker is missing."
}
$mutatingCommands = @(
    "Add-DnsServerResourceRecordA",
    "New-ADOrganizationalUnit",
    "New-ADServiceAccount",
    "Set-ADServiceAccount",
    "Install-ADServiceAccount",
    "New-SelfSignedCertificate",
    "New-Item",
    "Export-Certificate",
    "Import-Certificate",
    "Install-AdfsFarm",
    "Start-Service"
)
$earlyMutations = @(
    $ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -in $mutatingCommands -and
            $node.Extent.StartLineNumber -lt $deepPreflightMarker.Extent.StartLineNumber
    }, $true)
)
Assert-True -Value ($earlyMutations.Count -eq 0) -Case "no mutation before deep preflight"
Assert-False -Value ($scriptSource -match "DnsNameList\.Unicode") -Case "no direct DNS child property access"
Assert-False -Value ($scriptSource -match "EnhancedKeyUsageList\.ObjectId") -Case "no direct EKU child property access"
Assert-False -Value ($scriptSource -match "OverwriteConfiguration") -Case "no overwrite configuration"

Write-Output "Configure-AdfsDemoFarm tests: OK"
