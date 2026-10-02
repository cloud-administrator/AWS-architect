```powershell
reg.exe add 'HKLM\SOFTWARE\Policies\Claude' /v secureVmFeaturesEnabled /t REG_DWORD /d 1 /f /reg:64
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'allowedWorkspaceFolders' -PropertyType String -Value '["C:\\Users\\alice\\claude_work"]' -Force
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'isLocalDevMcpEnabled' -PropertyType DWord -Value 0 -Force
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'isDesktopExtensionEnabled' -PropertyType DWord -Value 0 -Force
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'isDesktopExtensionDirectoryEnabled' -PropertyType DWord -Value 0 -Force
```
