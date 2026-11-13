# 复制到 %USERPROFILE%\.litellm\env.ps1，填真值，不要提交。
# 用法：. $HOME\.litellm\env.ps1

# ---- 上游 key ----
$env:COMPANY_LITELLM_KEY = "<公司虚拟key>"
$env:GEMINI_API_KEY      = "<google key>"
$env:ANTHROPIC_API_KEY   = "<anthropic key>"

# ---- 网关自身 ----
# 随机串，前端用它当 apiKey
$env:LITELLM_MASTER_KEY = "sk-local-" + (-join ((48..57) + (97..122) | Get-Random -Count 24 | % { [char]$_ }))

# 花费日志 / 虚拟 key：只支持 Postgres。实测 SQLite 会让网关拒绝启动。
# 没有 Postgres 就留空，网关照常工作，只是不记录。
$env:LITELLM_DATABASE_URL = ""

# ---- 本机代理会拦掉 localhost，必须排除 ----
$env:NO_PROXY = "127.0.0.1,localhost"
$env:no_proxy = "127.0.0.1,localhost"

Write-Host "env loaded: master key ${env:LITELLM_MASTER_KEY}" -ForegroundColor Green