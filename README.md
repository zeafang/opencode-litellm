# local-ai-gateway

一台机器、一个端口、一个 key：把手上的所有模型收成一个 OpenAI 兼容接口。

- **网关**：LiteLLM Proxy，只绑 `127.0.0.1`。
- **别名**：按**能力**命名（`code-fast`、`vision-pro`），不按厂商。
- **前端**：opencode、Continue、Cline、脚本，全部指同一个 `baseURL`。
- **边界**：公司通道与个人通道靠独立虚拟 key 分开，不靠记性。

完整设计见 [`docs/gateway-plan.md`](docs/gateway-plan.md)。

---

## 现状（2026-11-13）

| 项 | 状态 |
|---|---|
| LiteLLM | `1.109.1` |
| 网关 | `http://127.0.0.1:4000` |
| 常驻方式 | 任务计划程序 `LiteLLM Gateway`，登录自启 |
| 上游通道 | 公司 LiteLLM `https://<company-gateway>` |
| 在线别名 | `code-fast` -> `<company-model>` |
| 前端 | opencode `1.19.5` |
| 花费记录 | 未开：LiteLLM 1.109.1 不接受 SQLite，需 Postgres |

公司网关目前只开了 DeepSeek 一个模型。视觉链路要另接一个上游 key。

---

## 快速开始

```powershell
# 1. 依赖
pip install "litellm[proxy]"

# 2. 配置（只改这一份，不要提交）
Copy-Item config\config.example.yaml "$HOME\.litellm\config.yaml"
Copy-Item scripts\env.example.ps1      "$HOME\.litellm\env.ps1"
notepad "$HOME\.litellm\env.ps1"       # 填 LITELLM_MASTER_KEY 和上游 key

# 3. 启动
.\scripts\start.ps1

# 4. 验收
curl.exe -s http://127.0.0.1:4000/health/liveliness
.\scripts\verify.ps1
```

健康检查返回 `"I'm alive!"`，配置自检全过，网关就活了。

若 PowerShell 拒绝执行 `.ps1`：

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## 常驻运行

### 普通用户（推荐，不需要管理员）

```powershell
$a = New-ScheduledTaskAction -Execute "powershell.exe" `
     -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\muti-agent\local-ai-gateway\scripts\start.ps1"'
$t = New-ScheduledTaskTrigger -AtLogOn
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
     -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "LiteLLM Gateway" -Action $a -Trigger $t -Settings $s -Force
```

日常操作：

```powershell
Start-ScheduledTask  -TaskName "LiteLLM Gateway"
Stop-ScheduledTask   -TaskName "LiteLLM Gateway"
Unregister-ScheduledTask -TaskName "LiteLLM Gateway" -Confirm:$false
```

### 管理员方式

`scripts\install-service.ps1` 会带 `-RunLevel Highest`，必须管理员 PowerShell。
不需要提权时用上面那段。

### 注意

- 触发条件是**登录**，不是开机。重启后未登录，网关不在。
- 隐藏窗口运行，日志不落盘。排错时手动跑 `scripts\start.ps1` 看输出。

---

## 前端接入

统一填三样：`baseURL = http://127.0.0.1:4000/v1`、`apiKey = <master key 或虚拟 key>`、`model = <别名>`。

| 前端 | 样例 |
|---|---|
| opencode | `frontends/opencode.config.example.json` |
| Continue | `frontends/continue.config.example.yaml` |
| Cline / Roo Code | `frontends/README.md` |
| Claude Code | `frontends/claude-code.ps1` |

### opencode

配置文件在 `~/.config/opencode/opencode.json`：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "local-gateway": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local LiteLLM Gateway",
      "options": {
        "baseURL": "http://127.0.0.1:4000/v1",
        "apiKey": "sk-<master key>"
      },
      "models": { "code-fast": { "name": "Code Fast" } }
    }
  },
  "model": "local-gateway/code-fast"
}
```

这个文件含明文 key，不要提交、不要截图。

VS Code 终端里运行 `opencode`。用 `opencode.cmd` 可绕开 PowerShell 执行策略。

---

## 加一个模型

只改 `config.yaml` 的 `model_list`，前端不动。

```yaml
  - model_name: vision-pro            # 别名，前端只认这个
    litellm_params:
      model: gemini/<型号>            # 上游真实型号
      api_key: os.environ/GEMINI_API_KEY
    model_info:
      supports_vision: true
```

规矩三条：

1. 一个别名只表达一种能力。
2. key 只写 `os.environ/XXX`，不写明文。
3. 加完跑 `python tests/test_config.py`。

改完必须重启网关，任务计划程序方式见上。

---

## Gemini

个人版 Gemini Code Assist 与 Gemini CLI 已停用，登录时报：

```text
This client is no longer supported for Gemini Code Assist for individuals.
Please migrate to the Antigravity suite of products: https://antigravity.google
```

现状与对策：

| 路 | 说明 |
|---|---|
| Antigravity | 官方替代品，独立 IDE，不是 VS Code 插件 |
| OpenRouter | 把 Gemini 接进本网关，别名 `vision-pro` |
| AI Studio key | 个人 Gmail 可申请，公司 Workspace 通常被策略拦住 |

---

## 安全

- 网关只绑 `127.0.0.1`，不要 `0.0.0.0`。
- `~/.litellm/env.ps1` 不进 git。
- 每个前端发一个独立虚拟 key，限制可用别名。
- 含公司数据的请求，降级目标也必须是公司批准的通道。
- 上游审核拒绝默认直接返回，不跨提供方重试。

---

## 排查

| 现象 | 原因 / 处理 |
|---|---|
| `ECONNREFUSED 127.0.0.1:4000` | 网关没起。`Start-ScheduledTask -TaskName "LiteLLM Gateway"` |
| 启动即退，端口占用 | `netstat -ano \| findstr :4000`，先停旧进程 |
| `opencode.ps1 cannot be loaded` | 执行策略。改 RemoteSigned，或改用 `opencode.cmd` |
| 401 | `LITELLM_MASTER_KEY` 没加载，检查 `env.ps1` |
| `400 ... inappropriate content` | 上游内容审核拒绝，不是配置错。换通道或改写输入 |
| 图片报错 | 发给了非视觉模型，换 `vision-pro` |
| 没有花费记录 | 需要 Postgres，SQLite 不被 1.109.1 接受 |
| 502 / 超时 | 代理拦了 localhost，设 `NO_PROXY=127.0.0.1` |

---

## 目录

```text
config/config.example.yaml    网关配置模板（复制到 ~/.litellm/config.yaml）
scripts/env.example.ps1       环境变量模板（复制到 ~/.litellm/env.ps1）
scripts/start.ps1             前台启动
scripts/verify.ps1            健康检查 + 别名清单 + 一次文本调用
scripts/smoke_test.py         文本 / 图片 / embedding 三条链路自测
scripts/install-service.ps1   注册开机自启（需管理员）
frontends/                    各前端的最小接入样例
tests/test_config.py          配置自检（别名、降级链、明文 key）
docs/gateway-plan.md          完整方案
```

## License

MIT