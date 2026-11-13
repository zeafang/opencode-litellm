# 注册开机自启（任务计划程序，登录时启动，无窗口）。
# 需要管理员 PowerShell。卸载：Unregister-ScheduledTask -TaskName "LiteLLM Gateway"
param(
    [string]$TaskName = "LiteLLM Gateway",
    [string]$Config = "$HOME\.litellm\config.yaml",
    [int]$Port = 4000
)

$ErrorActionPreference = "Stop"
$start = Join-Path $PSScriptRoot "start.ps1"
if (-not (Test-Path $start)) { throw "找不到 $start" }

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$start`" -Config `"$Config`" -Port $Port"

$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -RunLevel Highest -Force | Out-Null

Write-Host "已注册：$TaskName（下次登录自动启动）" -ForegroundColor Green
Write-Host "立即测试：Start-ScheduledTask -TaskName `"$TaskName`""