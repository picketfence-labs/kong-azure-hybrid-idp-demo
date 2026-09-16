# 自己管理AD DSフォレストを作成し、フォレスト昇格に伴う再起動をまたいでドメインオブジェクト作成
# （scripts/adfs/New-AdDsDomainObjects.ps1、同じfileUrisでこのファイルと同じフォルダへ
# ダウンロードされる想定）へ処理を引き継ぐ（ADR-0005 Option A）。
#
# AzureのWindows VMはCustomScriptExtensionのhandlerを1台につき1つしか持てない
# （publisher+typeの組で一意、"Multiple VMExtensions per handler not supported"）ため、
# フォレスト昇格（要:再起動）とドメインオブジェクト作成を別々の拡張機能に分割できない。
# 代わりに、フォレスト昇格前にNew-AdDsDomainObjects.ps1を安定したローカルパスへコピーし、
# 「起動時に1回だけ実行するスケジュールタスク」として登録しておくことで、再起動後の
# 続行を実現する（DSCのLCM再起動継続と同じ目的を、素朴なスケジュールタスクで代替）。
#
# 冪等性: 既にドメインコントローラーの場合（再apply等）は、フォレスト作成をスキップし、
# ドメインオブジェクト作成スクリプトをその場で直接実行する（再起動を経由しないため
# スケジュールタスクは使わない）。

param(
    [Parameter(Mandatory = $true)][string]$DomainName,
    [Parameter(Mandatory = $true)][string]$DomainNetbiosName,
    [Parameter(Mandatory = $true)][string]$SafeModeAdministratorPasswordPlainText,
    [Parameter(Mandatory = $true)][string]$DomainAdminUsername,
    [Parameter(Mandatory = $true)][string]$DomainAdminPassword,
    [Parameter(Mandatory = $true)][string]$TestUsersJson
)

$LogDir = "C:\KongDemo\dc"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir "Install-AdDsForest.log") -Append

try {
    # CustomScriptExtensionのfileUrisダウンロード先は実行のたびに変わりうるため、再起動後の
    # スケジュールタスクから参照できるよう、恒久的なローカルパスへコピーしておく。
    $Phase2Path = Join-Path $LogDir "New-AdDsDomainObjects.ps1"
    Copy-Item -Path (Join-Path $PSScriptRoot "New-AdDsDomainObjects.ps1") -Destination $Phase2Path -Force

    $DomainRole = (Get-CimInstance -ClassName Win32_ComputerSystem).DomainRole
    # DomainRole: 4 = Backup Domain Controller, 5 = Primary Domain Controller
    if ($DomainRole -ge 4) {
        Write-Output "既にドメインコントローラーです（DomainRole=$DomainRole）。フォレスト作成をスキップし、ドメインオブジェクト作成を直接実行します。"
        & $Phase2Path -DomainDnsName $DomainName -DomainAdminUsername $DomainAdminUsername -DomainAdminPassword $DomainAdminPassword -TestUsersJson $TestUsersJson
        return
    }

    $TaskName = "KongDemoPhase2CreateDomainObjects"
    Write-Output "フォレスト昇格後の再起動時に $Phase2Path を実行するスケジュールタスク $TaskName を登録します。"
    $Phase2Arguments = "-NonInteractive -ExecutionPolicy Unrestricted -File `"$Phase2Path`" -DomainDnsName `"$DomainName`" -DomainAdminUsername `"$DomainAdminUsername`" -DomainAdminPassword `"$DomainAdminPassword`" -TestUsersJson '$TestUsersJson'"
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $Phase2Arguments
    $Trigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -User "SYSTEM" -RunLevel Highest -Force | Out-Null

    Write-Output "AD-Domain-Servicesロールを導入します。"
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

    $SecurePassword = ConvertTo-SecureString $SafeModeAdministratorPasswordPlainText -AsPlainText -Force

    Write-Output "フォレスト $DomainName ($DomainNetbiosName) を作成します。完了後にVMが自動再起動し、$TaskName が $Phase2Path を実行します。"
    Import-Module ADDSDeployment
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $DomainNetbiosName `
        -SafeModeAdministratorPassword $SecurePassword `
        -InstallDns:$true `
        -DatabasePath "C:\Windows\NTDS" `
        -LogPath "C:\Windows\NTDS" `
        -SysvolPath "C:\Windows\SYSVOL" `
        -NoRebootOnCompletion:$false `
        -Force:$true
}
finally {
    Stop-Transcript
}
