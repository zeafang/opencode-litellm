# Claude Code 指向本地网关。点运行或 `. .\frontends\claude-code.ps1`
# 注意：Claude Code 说 Anthropic 协议，网关必须开 /v1/messages 兼容端点。

$env:ANTHROPIC_BASE_URL = "http://127.0.0.1:4000"
$env:ANTHROPIC_AUTH_TOKEN = $env:LITELLM_MASTER_KEY   # 或该前端专用的虚拟 key
$env:ANTHROPIC_MODEL = "claude-main"                  # 网关里的别名
$env:NO_PROXY = "127.0.0.1,localhost"

Write-Host "ANTHROPIC_BASE_URL = $env:ANTHROPIC_BASE_URL"
Write-Host "ANTHROPIC_MODEL    = $env:ANTHROPIC_MODEL"
Write-Host "现在运行 claude 即走本地网关。"