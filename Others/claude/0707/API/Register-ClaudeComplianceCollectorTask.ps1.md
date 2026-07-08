<#
.SYNOPSIS
  Registers a Windows Task Scheduler task for ClaudeComplianceCollector.ps1.

.DESCRIPTION
  Run from an elevated PowerShell session after copying ClaudeComplianceCollector.ps1
  to C:\ProgramData\ClaudeComplianceCollector\ClaudeComplianceCollector.ps1.
#>

[CmdletBinding()]
param(
    [string]$TaskName = 'ClaudeComplianceCollector-Daily',
    [string]$CollectorScriptPath = 'C:\ProgramData\ClaudeComplianceCollector\ClaudeComplianceCollector.ps1',
    [ValidateSet('ActivityTail','ContentTail','AllTail')]
    [string]$Mode = 'AllTail',
    [string]$At = '02:00',
    [string]$RunAsUser = $null
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $CollectorScriptPath)) {
    throw "Collector script not found: $CollectorScriptPath"
}

$execute = 'powershell.exe'
$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$CollectorScriptPath`" -Mode $Mode"
$action = New-ScheduledTaskAction -Execute $execute -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Days 3) `
    -AllowStartIfOnBatteries:$false `
    -DisallowStartIfOnBatteries

if ([string]::IsNullOrWhiteSpace($RunAsUser)) {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -RunLevel Highest `
        -Description 'Daily Claude Enterprise Compliance API collector. MultipleInstances=IgnoreNew prevents overlap.' `
        -Force | Out-Null
}
else {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -RunLevel Highest `
        -User $RunAsUser `
        -Description 'Daily Claude Enterprise Compliance API collector. MultipleInstances=IgnoreNew prevents overlap.' `
        -Force | Out-Null
}

Write-Host "Registered task: $TaskName"
Write-Host "Action: $execute $arguments"
Write-Host "Schedule: Daily at $At"
Write-Host "Multiple instances: IgnoreNew"
