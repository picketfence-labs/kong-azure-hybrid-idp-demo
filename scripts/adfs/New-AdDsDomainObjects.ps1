# フォレスト昇格後のAD DS上に、ADFSドメイン管理者アカウントとGroup 2の5テストユーザーを作成する。
# terraform/adfs_domain_controller.tf のCustomScriptExtensionから、実引数付きの
# `New-InsuranceDemoAccounts ...` 呼び出し行を末尾に追記した状態で、フォレスト昇格済みの
# ドメインコントローラー上で実行される。ドメインコントローラー上の`NT AUTHORITY\SYSTEM`は
# AD DSオブジェクト操作についてDomain Admin相当の権限を持つため、追加の資格情報は不要。
#
# 冪等性: 各アカウントは`SamAccountName`の存在チェックを行い、既に存在する場合は作成をスキップする。

function New-InsuranceDemoAccounts {
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
            Write-Output "$DomainAdminUsername は既に存在します。作成をスキップします。"
        }
        else {
            Write-Output "ドメイン管理者アカウント $DomainAdminUsername を作成します。"
            New-ADUser -Name $DomainAdminUsername `
                -SamAccountName $DomainAdminUsername `
                -UserPrincipalName "$DomainAdminUsername@$DomainDnsName" `
                -AccountPassword (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force) `
                -Enabled $true -PasswordNeverExpires $true -ChangePasswordAtLogon $false
            Add-ADGroupMember -Identity "Domain Admins" -Members $DomainAdminUsername
        }

        $TestUsers = $TestUsersJson | ConvertFrom-Json
        foreach ($Department in $TestUsers.PSObject.Properties.Name) {
            $SamAccountName = "demo-$Department"

            if (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue) {
                Write-Output "$SamAccountName は既に存在します。作成をスキップします。"
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
        Stop-Transcript
    }
}
