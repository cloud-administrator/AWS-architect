[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AuthorizedUserGroupSamAccountName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ReportPath,

    [switch]$OverwriteExisting
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop

$rows = @(Import-Csv -LiteralPath $CsvPath)
if ($rows.Count -eq 0) {
    throw 'CSVにデータ行がありません。'
}
foreach ($column in @('ComputerName', 'SamAccountName')) {
    if (-not ($rows[0].PSObject.Properties.Name -contains $column)) {
        throw "CSV列が不足しています: $column"
    }
}

$duplicates = $rows | Group-Object { $_.ComputerName.Trim().ToUpperInvariant() } | Where-Object Count -gt 1
if ($duplicates) {
    throw "ComputerNameが重複しています: $((($duplicates | Select-Object -ExpandProperty Name) -join ', '))"
}

$group = Get-ADGroup -Identity $AuthorizedUserGroupSamAccountName -ErrorAction Stop
$authorizedSidSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
Get-ADGroupMember -Identity $group -Recursive -ErrorAction Stop |
    Where-Object objectClass -eq 'user' |
    ForEach-Object { [void]$authorizedSidSet.Add($_.SID.Value) }

$report = New-Object System.Collections.Generic.List[object]
foreach ($row in $rows) {
    $computerName = ([string]$row.ComputerName).Trim()
    $samAccountName = ([string]$row.SamAccountName).Trim()
    $status = 'Rejected'
    $message = ''
    $oldManagedBy = ''
    $newManagedBy = ''

    try {
        if ($computerName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$') {
            throw "ComputerNameの形式が不正です: $computerName"
        }
        if ([string]::IsNullOrWhiteSpace($samAccountName)) {
            throw 'SamAccountNameが空です。'
        }

        $computer = Get-ADComputer -Identity $computerName -Properties ManagedBy -ErrorAction Stop
        $user = Get-ADUser -Identity $samAccountName -Properties Enabled, DistinguishedName, SID -ErrorAction Stop
        if (-not $user.Enabled) {
            throw "ユーザーが無効です: $samAccountName"
        }
        if (-not $authorizedSidSet.Contains($user.SID.Value)) {
            throw "認可グループ $AuthorizedUserGroupSamAccountName の実効メンバーではありません: $samAccountName"
        }

        $oldManagedBy = [string]$computer.ManagedBy
        $newManagedBy = [string]$user.DistinguishedName
        if (-not [string]::IsNullOrWhiteSpace($oldManagedBy) -and $oldManagedBy -ine $newManagedBy -and -not $OverwriteExisting) {
            throw "既存managedByが別オブジェクトです。上書きには承認後 -OverwriteExisting が必要です: $oldManagedBy"
        }

        if ($oldManagedBy -ieq $newManagedBy) {
            $status = 'Unchanged'
            $message = '既に一致しています。'
        } elseif ($PSCmdlet.ShouldProcess($computer.DistinguishedName, "managedByを$newManagedByへ設定")) {
            Set-ADComputer -Identity $computer -ManagedBy $newManagedBy -ErrorAction Stop
            $status = 'Updated'
            $message = 'managedByを更新しました。'
        } else {
            $status = 'WhatIf'
            $message = '変更は行っていません。'
        }
    } catch {
        $message = $_.Exception.Message
    }

    $report.Add([pscustomobject]@{
        ComputerName = $computerName
        SamAccountName = $samAccountName
        OldManagedBy = $oldManagedBy
        NewManagedBy = $newManagedBy
        Status = $status
        Message = $message
    })
}

$report | Export-Csv -LiteralPath $ReportPath -NoTypeInformation -Encoding UTF8
$report | Format-Table -AutoSize

if ($report.Status -contains 'Rejected') {
    Write-Error "Rejectedが含まれます。レポートを確認してください: $ReportPath"
    exit 2
}
exit 0
