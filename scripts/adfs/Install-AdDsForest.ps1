# 自己管理AD DSフォレストを作成する（ADR-0005 Option A）。
# terraform/adfs_domain_controller.tf のCustomScriptExtensionから、実引数付きの
# `Install-AdDsForestIfNeeded ...` 呼び出し行を末尾に追記した状態で実行される。
#
# 冪等性: 既にドメインコントローラーの場合（再apply等）はフォレスト作成をスキップする。
# `Install-ADDSForest` は完了時にVMを自動再起動するため、この関数を呼び出したプロセス
# （CustomScriptExtension）は再起動前にreturnし、拡張機能としては正常終了として扱われる。

function Install-AdDsForestIfNeeded {
    param(
        [Parameter(Mandatory = $true)][string]$DomainName,
        [Parameter(Mandatory = $true)][string]$DomainNetbiosName,
        [Parameter(Mandatory = $true)][string]$SafeModeAdministratorPasswordPlainText
    )

    $LogDir = "C:\KongDemo\dc"
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    Start-Transcript -Path (Join-Path $LogDir "Install-AdDsForest.log") -Append

    try {
        $DomainRole = (Get-CimInstance -ClassName Win32_ComputerSystem).DomainRole
        # DomainRole: 4 = Backup Domain Controller, 5 = Primary Domain Controller
        if ($DomainRole -ge 4) {
            Write-Output "既にドメインコントローラーです（DomainRole=$DomainRole）。フォレスト作成をスキップします。"
            return
        }

        Write-Output "AD-Domain-Servicesロールを導入します。"
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

        $SecurePassword = ConvertTo-SecureString $SafeModeAdministratorPasswordPlainText -AsPlainText -Force

        Write-Output "フォレスト $DomainName ($DomainNetbiosName) を作成します。完了後にVMが自動再起動します。"
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
}
