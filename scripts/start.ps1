# 前台启动网关。要常驻用 install-service.ps1。
param(
    [string]$Config = "$HOME\.litellm\config.yaml",
    [int]$Port = 4000
)

$ErrorActionPreference = "Stop"
$envFile = Join-Path $HOME ".litellm\env.ps1"

if (Test-Path $envFile) {
    . $envFile
} else {
    Write-Warning "找不到 $envFile，先复制 scripts\env.example.ps1 并填 key"
}

if (-not $env:LITELLM_MASTER_KEY) { throw "LITELLM_MASTER_KEY 未设置" }
if (-not (Test-Path $Config))     { throw "找不到配置：$Config" }

$busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($busy) { throw "端口 $Port 已被占用（PID $($busy.OwningProcess)）" }

Write-Host "gateway -> http://127.0.0.1:$Port" -ForegroundColor Cyan
Write-Host "config  -> $Config" -ForegroundColor Cyan

litellm --config $Config --host 127.0.0.1 --port $Port