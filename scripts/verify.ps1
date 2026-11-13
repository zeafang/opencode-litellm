# 验收：存活 -> 别名清单 -> 一次真实文本调用（可选）。
param(
    [int]$Port = 4000,
    [string]$Model = ""
)

$ErrorActionPreference = "Stop"
$envFile = Join-Path $HOME ".litellm\env.ps1"
if (Test-Path $envFile) { . $envFile }
if (-not $env:LITELLM_MASTER_KEY) { throw "LITELLM_MASTER_KEY 未设置" }

$base = "http://127.0.0.1:$Port"
$headers = @{ Authorization = "Bearer $env:LITELLM_MASTER_KEY" }
$failed = 0

function Check($name, $ok, $detail = "") {
    if ($ok) { Write-Host "[PASS] $name" -ForegroundColor Green }
    else     { Write-Host "[FAIL] $name $detail" -ForegroundColor Red; $script:failed++ }
}

# 1. 存活
try {
    $r = Invoke-WebRequest "$base/health/liveliness" -Headers $headers -TimeoutSec 10
    Check "liveliness" ($r.StatusCode -eq 200) "status=$($r.StatusCode)"
} catch {
    Check "liveliness" $false $_.Exception.Message
}

# 2. 别名
$aliases = @()
try {
    $models = Invoke-RestMethod "$base/v1/models" -Headers $headers -TimeoutSec 10
    $aliases = @($models.data | ForEach-Object { $_.id })
    Check "models ($($aliases.Count))" ($aliases.Count -gt 0)
    $aliases | ForEach-Object { Write-Host "       - $_" }
} catch {
    Check "models" $false $_.Exception.Message
}

# 3. 文本调用（给了 Model 才跑）
if ($Model) {
    if ($aliases -notcontains $Model) { Check "chat $Model" $false "别名不存在" }
    else {
        try {
            $body = @{
                model    = $Model
                messages = @(@{ role = "user"; content = "只回复两个字：通了" })
                max_tokens = 256
            } | ConvertTo-Json -Depth 5
            $r = Invoke-RestMethod "$base/v1/chat/completions" -Method Post `
                 -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 120
            $text = $r.choices[0].message.content
            Check "chat $Model" ([bool]$text) "-> $text"
        } catch {
            Check "chat $Model" $false $_.Exception.Message
        }
    }
}

if ($failed -gt 0) { Write-Host "`n$failed 项失败" -ForegroundColor Red; exit 1 }
Write-Host "`n全部通过" -ForegroundColor Green