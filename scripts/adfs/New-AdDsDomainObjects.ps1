# フォレスト昇格後のAD DS上に、ADFSドメイン管理者アカウントとGroup 2の5テストユーザーを作成する。
# scripts/adfs/Install-AdDsForest.ps1がフォレスト昇格前にこのファイルを安定したローカルパスへ
# コピーし、再起動後に1回だけ実行するスケジュールタスクとして登録する（既にドメインコントローラー
# の場合は、再起動を経由せずその場で直接実行される）。ドメインコントローラー上の
# `NT AUTHORITY\SYSTEM`はAD DSオブジェクト操作についてDomain Admin相当の権限を持つため、
# 追加の資格情報は不要。
#
# 冪等性: 各アカウントは`SamAccountName`の存在チェックを行い、既に存在する場合は作成をスキップするが、
# パスワードはTerraformが管理する値（引数で渡された値）へ常に同期する。random_password.*が
# 再採番されて再applyされた場合に、AD側の実パスワードとTerraform state/outputの値がずれたまま
# 放置される問題が実機で発生したため（docs/troubleshooting-log.md参照）。
# 実行後、自身を起動時に実行するスケジュールタスク（存在する場合）を登録解除する。

param(
    [Parameter(Mandatory = $true)][string]$DomainDnsName,
    [Parameter(Mandatory = $true)][string]$DomainAdminUsername,
    [Parameter(Mandatory = $true)][string]$DomainAdminPassword,
    # {"<department>": "<password>", ...} 形式のJSON文字列（terraform/insurance_users.tfの
    # insurance_test_groups × random_password.insurance_test_userから生成）
    [Parameter(Mandatory = $true)][string]$TestUsersJson
)

$LogDir = "C:\KongDemo\dc"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir "New-AdDsDomainObjects.log") -Append

try {
    Import-Module ActiveDirectory

    if (Get-ADUser -Filter "SamAccountName -eq '$DomainAdminUsername'" -ErrorAction SilentlyContinue) {
        Write-Output "$DomainAdminUsername は既に存在します。パスワードをTerraform管理値へ同期します。"
        Set-ADAccountPassword -Identity $DomainAdminUsername -Reset `
            -NewPassword (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force)
        Set-ADUser -Identity $DomainAdminUsername -Enabled $true -PasswordNeverExpires $true -ChangePasswordAtLogon $false
    }
    else {
        Write-Output "ドメイン管理者アカウント $DomainAdminUsername を作成します。"
        New-ADUser -Name $DomainAdminUsername `
            -SamAccountName $DomainAdminUsername `
            -UserPrincipalName "$DomainAdminUsername@$DomainDnsName" `
            -AccountPassword (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force) `
            -Enabled $true -PasswordNeverExpires $true -ChangePasswordAtLogon $false
    }
    Add-ADGroupMember -Identity "Domain Admins" -Members $DomainAdminUsername

    $TestUsers = $TestUsersJson | ConvertFrom-Json
    foreach ($Department in $TestUsers.PSObject.Properties.Name) {
        $SamAccountName = "demo-$Department"

        if (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue) {
            Write-Output "$SamAccountName は既に存在します。パスワードをTerraform管理値へ同期します。"
            Set-ADAccountPassword -Identity $SamAccountName -Reset `
                -NewPassword (ConvertTo-SecureString $TestUsers.$Department -AsPlainText -Force)
            continue
        }

        Write-Output "テストユーザー $SamAccountName (department=$Department) を作成します。"
        New-ADUser -Name "Demo User - $Department" `
            -SamAccountName $SamAccountName `
            -UserPrincipalName "$SamAccountName@$DomainDnsName" `
            -Department $Department `
            -AccountPassword (ConvertTo-SecureString $TestUsers.$Department -AsPlainText -Force) `
            -Enabled $true -PasswordNeverExpires $true -ChangePasswordAtLogon $false
    }
}
finally {
    # scripts/adfs/Install-AdDsForest.ps1が登録した起動時スケジュールタスク（存在する場合）を
    # 自身の実行完了後に登録解除する。タスク名はInstall-AdDsForest.ps1と一致させること。
    Unregister-ScheduledTask -TaskName "KongDemoPhase2CreateDomainObjects" -Confirm:$false -ErrorAction SilentlyContinue
    Stop-Transcript
}
