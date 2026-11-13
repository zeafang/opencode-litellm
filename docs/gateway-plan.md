# 本地 AI 统一网关与多智能体生态（完整计划 v2）

> v1 原文已原样保留：`local_ai_gateway_multi_agent_orchestration_guide.v1.md`
> v2 改动：修正 v1 中跑不通/已过期的部分，补齐能力路由、多模态矩阵、前端接入、运维、验收清单。
> 本机实测日期：2026-11-13。

---

## 0. 一句话目标

一台机器上跑一个网关（LiteLLM，`127.0.0.1:4000`），把手上所有模型收成一个 **OpenAI 兼容接口**；所有前端都指它；模型按**能力**取别名，不按厂商。

---

## 1. 做与不做

**做**
- 统一入口：一个 baseURL；按前端/用途发放独立虚拟 key，并限制可调用模型。
- 能力路由：看图找能看图的，长文找长上下文的。
- 自动降级：某条通道挂了或超限，自动换备。
- 花费可见：每次调用有记录。
- 数据边界：公司数据只走公司通道。

**暂不做**
- 自建推理集群、模型微调。
- 多云编排平台。
- 订阅反代接入公司流程（可做，但单独隔离、单独开关）。

---

## 2. 架构（v2 修正）

v1 写“OpenCode 是唯一入口”。改成：**网关是资产，前端随便换**。

```text
前端层（任选，都指同一个 baseURL）
  Claude Code │ Codex │ VS Code 扩展 │ Continue │ Cline │ 脚本 │ curl
                    │
                    v
网关层  LiteLLM  127.0.0.1:4000
  · 别名路由   · 重试/冷却/降级   · 花费日志   · 401 拦截
                    │
                    v
上游层
  公司 LiteLLM ── DeepSeek（合规通道，只出内网）
  Google AI   ── Gemini（视觉 + 长上下文）
  Anthropic   ── Claude（个人，重逻辑）
  Ollama      ── 本地模型 / embedding（完全离线）
  转写/合成   ── STT / TTS（单独挂）
```

三条原则：

1. **别名表达能力，不表达厂商。** 前端只认 `vision-pro`，背后换成谁都无所谓。
2. **网关只绑 `127.0.0.1`。** 不要 `0.0.0.0`。
3. **key 只进环境变量。** yaml 里只写 `os.environ/XXX`。

---

## 3. 能力别名表（核心新增）

v1 的别名是 `company-deepseek-v3` 这种“厂商 + 型号”。改后这样：

| 别名 | 干什么 | 候选上游 | 视觉 | 工具调用 | 上下文 |
|---|---|---|---|---|---|
| `code-fast` | 日常改代码、SQL、单测 | 公司 DeepSeek V3 | 否 | 是 | 中 |
| `reason-deep` | 死锁、算法、长推理 | 公司 DeepSeek R1 | 否 | 是 | 中 |
| `vision-pro` | 看截图、看 UI 稿、长文档 | Gemini Pro | 是 | 是 | 超长 |
| `claude-main` | 复杂重构、写作 | Claude（API/订阅） | 是 | 是 | 长 |
| `local-offline` | 断网、敏感、兜底 | Ollama qwen-coder | 否 | 部分 | 小 |
| `embed-local` | 向量检索、本地 RAG | Ollama nomic-embed | — | — | — |
| `stt-local` | 语音转文字 | faster-whisper / whisper API | — | — | — |
| `tts-local` | 文字转语音 | 本地 TTS | — | — | — |

以后加模型，只改 `model_list`。前端一个字都不用动。

---

## 4. 第一阶段：网关落地

### 4.1 目录

```text
C:\Users\ziyi.fang\.litellm\
  config.yaml
  env.ps1          # key，不进 git
  proxy.log
  litellm.db       # 花费日志（SQLite 起步）
```

### 4.2 安装

```powershell
pip install "litellm[proxy]"
litellm --version
```

### 4.3 `config.yaml`（完整版，v1 的错误已修）

v1 的问题：`fallbacks` 只写一条、没有能力标注、`master_key` 明文、没有花费库、Claude 型号过期、Windows 用了 `nohup`。

```yaml
model_list:
  # ---------- 公司通道（合规，只出内网） ----------
  - model_name: code-fast
    litellm_params:
      model: openai/deepseek-chat          # 与公司网关暴露的名字一致
      api_base: http://<公司网关>:4000/v1
      api_key: os.environ/COMPANY_LITELLM_KEY
    model_info:
      supports_vision: false
      supports_function_calling: true
      max_input_tokens: 64000

  - model_name: reason-deep
    litellm_params:
      model: openai/deepseek-reasoner
      api_base: http://<公司网关>:4000/v1
      api_key: os.environ/COMPANY_LITELLM_KEY
    model_info:
      supports_vision: false
      supports_function_calling: true

  # ---------- 个人云通道 ----------
  - model_name: vision-pro
    litellm_params:
      model: gemini/<当前Gemini型号>        # 以官方文档当前型号为准
      api_key: os.environ/GEMINI_API_KEY
    model_info:
      supports_vision: true
      supports_function_calling: true
      max_input_tokens: 1000000

  - model_name: claude-main
    litellm_params:
      model: anthropic/<当前Claude型号>
      api_key: os.environ/ANTHROPIC_API_KEY
    model_info:
      supports_vision: true
      supports_function_calling: true

  # ---------- 本地 ----------
  - model_name: local-offline
    litellm_params:
      model: ollama/qwen2.5-coder:14b
      api_base: http://127.0.0.1:11434
    model_info:
      supports_vision: false

  - model_name: embed-local
    litellm_params:
      model: ollama/nomic-embed-text
      api_base: http://127.0.0.1:11434

router_settings:
  routing_strategy: simple-shuffle
  num_retries: 2
  timeout: 600
  allowed_fails: 2
  cooldown_time: 30

  fallbacks:                    # 通道故障时降级
    - reason-deep: [code-fast]

  context_window_fallbacks:     # 上下文超长时换大窗口
    - code-fast: [vision-pro]

  # 不配置 content_policy_fallbacks：审核拒绝应返回调用方处理，不能默认换上游重试。

litellm_settings:
  drop_params: true             # 上游不认的参数自动丢弃，避免 400
  request_timeout: 600

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/LITELLM_DATABASE_URL
```

审核类 400 默认直接返回。自动换提供方可能绕过上游内容政策，也可能把请求发送到不同的数据边界；只有明确允许该数据流向目标提供方时才考虑配置。

### 4.4 环境变量

写进 `.litellm\env.ps1`，每次开终端 `.\env.ps1`：

```powershell
$env:COMPANY_LITELLM_KEY = "<公司虚拟key>"
$env:GEMINI_API_KEY      = "<google key>"
$env:ANTHROPIC_API_KEY   = "<anthropic key>"
$env:LITELLM_MASTER_KEY  = "sk-local-<随机串>"
$env:LITELLM_DATABASE_URL = "sqlite:///C:/Users/ziyi.fang/.litellm/litellm.db"

# 关键：本机代理会拦掉 localhost 请求
$env:NO_PROXY = "127.0.0.1,localhost"
$env:no_proxy = "127.0.0.1,localhost"
```

> SQLite 只够记花费。要用**虚拟 key 分权**（公司 key 只能调公司别名），必须换 Postgres。

### 4.5 启动

```powershell
litellm --config "$HOME\.litellm\config.yaml" --host 127.0.0.1 --port 4000
```

> v1 的 `nohup ... &` 在原生 Windows 不存在。要常驻用**任务计划程序**或 **NSSM**，见第 8 节。

### 4.6 验收（一个都不能跳）

```powershell
# 1. 存活
curl.exe -s http://127.0.0.1:4000/health/liveliness `
  -H "Authorization: Bearer $env:LITELLM_MASTER_KEY"

# 2. 模型列表里有全部别名
curl.exe -s http://127.0.0.1:4000/v1/models `
  -H "Authorization: Bearer $env:LITELLM_MASTER_KEY"
```

```python
# 3. 文本链路
from openai import OpenAI
c = OpenAI(base_url="http://127.0.0.1:4000/v1", api_key="sk-local-...")
print(c.chat.completions.create(
    model="code-fast",
    messages=[{"role": "user", "content": "回复 OK"}]
).choices[0].message.content)

# 4. 视觉链路（关键：只有 vision 别名能过）
import base64
b64 = base64.b64encode(open("ui.png", "rb").read()).decode()
print(c.chat.completions.create(
    model="vision-pro",
    messages=[{"role": "user", "content": [
        {"type": "text", "text": "这张图里是什么表？"},
        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
    ]}]
).choices[0].message.content)
```

第 4 步如果报错，说明你在用文本模型发图片。这是最常见的坑，v1 没写。

### 4.7 Windows 特有的坑

| 坑 | 现象 | 处置 |
|---|---|---|
| 全局代理 | 调 localhost 超时或 502 | 设 `NO_PROXY` |
| `nohup` | 命令不存在 | 用任务计划程序 / NSSM |
| 中文乱码 | 日志里中文变问号 | `[Console]::OutputEncoding = [Text.Encoding]::UTF8` |
| 端口占用 | 启动即退 | `netstat -ano \| findstr :4000` |
| 关闭窗口即停 | 网关跟着退 | 必须做成服务，别用前台窗口 |

---

## 5. 第二阶段：多模态

### 5.1 能力矩阵

| 能力 | 谁来做 | 说明 |
|---|---|---|
| 看图（截图/UI 稿/表格） | `vision-pro` | 图片走 `image_url`，只发视觉模型 |
| 长 PDF / 长文档 | `vision-pro` | 超长上下文，配 `context_window_fallbacks` |
| 语音转文字 | `stt-local` | 会议、录音、口述需求 |
| 文字转语音 | `tts-local` | 播报、朗读 |
| 视频 | 先抽帧再当图 | 网关不处理视频，本地 ffmpeg 抽帧 |
| 检索 | `embed-local` | 向量化，配本地向量库 |

### 5.2 落地顺序（别一次全上）

1. 文本跑通（第 4.6 节 1–3 步）。
2. 视觉跑通（第 4 步）。
3. 转写：一段 30 秒录音转文字。
4. 合成：同一段文字读出来。
5. 检索：100 条文档切块 + 向量 + 召回。
6. 视频：最后做，抽帧就够了。

### 5.3 embedding 单独一层

embedding 不走 `chat/completions`，走 `/v1/embeddings`。前端和向量库各配一次 baseURL 即可。

```python
c.embeddings.create(model="embed-local", input=["第一段", "第二段"])
```

---

## 6. 第三阶段：多智能体

### 6.1 分层

| 角色 | 用什么 | 干什么 |
|---|---|---|
| 主指挥 | `vision-pro` / `claude-main` | 读需求、看截图、拆任务、验收 |
| 执行员 | `code-fast` | 写代码、改 SQL、跑测试 |
| 攻坚 | `reason-deep` | 卡住的 bug、并发、算法 |
| 兜底 | `local-offline` | 断网或敏感时顶上 |

派发规则：主指挥**只做决策和验收**，不写长代码；执行员**只做被派的那一小块**。

### 6.2 用 OpenCode 做调度

OpenCode 支持主代理 + 子代理。要点：

- 每个 agent 绑一个**别名**，不绑厂商型号。
- 子代理写清边界：能改哪些文件、什么时候停。
- 配置文件路径以当前版本为准（1.x 与 2.x 不同），先 `opencode --version` 再对着官方文档建。

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "local-gateway": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local LiteLLM Gateway",
      "options": {
        "baseURL": "http://127.0.0.1:4000/v1",
  "apiKey": "<为 OpenCode 单独创建且限制模型范围的虚拟 key>"
      },
      "models": {
        "code-fast":  { "name": "Code Fast (Company)" },
        "reason-deep": { "name": "Deep Reason (Company)" },
        "vision-pro": { "name": "Vision Pro (Gemini)" },
        "claude-main": { "name": "Claude Main" },
        "local-offline": { "name": "Local Offline" }
      }
    }
  },
  "agent": {
    "build": {
      "model": "local-gateway/vision-pro",
      "description": "主指挥：读图、拆任务、验收，不直接写长代码"
    },
    "fast-coder": {
      "mode": "subagent",
      "model": "local-gateway/code-fast",
      "description": "执行员：按指令改代码/SQL，改完跑测试"
    },
    "deep-thinker": {
      "mode": "subagent",
      "model": "local-gateway/reason-deep",
      "description": "攻坚：复杂 bug、并发、算法验证"
    }
  }
}
```

v1 这里还写死了 `claude-3-7-sonnet-20250219`，已退役。全部换成别名后，型号变了不用改这份文件。

### 6.3 不用 OpenCode 也行

Kiro Crew、Claude Code 自带子代理机制，同样可以绑别名。网关不关心谁来调，只关心请求里的 `model` 是哪个别名。

---

## 7. 第四阶段：前端接入

### 7.1 Windows / VS Code 上的真实情况（已核实）

| 前端 | 形态 | 接法 |
|---|---|---|
| Claude Code | VS Code 扩展 / 终端 | `ANTHROPIC_BASE_URL` 指向网关，走 `/v1/messages` |
| Codex | VS Code 扩展 / CLI | 配置里改 `base_url` 与 `model_provider` |
| Continue | VS Code 原生面板 | 配置 `provider: openai` + `apiBase` + `apiKey` + `model` |
| Cline | VS Code 原生面板 | 选 “OpenAI Compatible”，填 Base URL / Key / Model ID |
| Roo Code | VS Code 原生面板 | 同 Cline |
| OpenCode | 终端 TUI | 第 6.2 节配置 |

Claude Code 说的是 Anthropic 协议，不是 OpenAI 协议。它能指网关，是因为 LiteLLM 提供 `/v1/messages` 兼容端点。

### 7.2 OpenCode 在 VS Code 里到底什么样

官方扩展 `sst-dev.opencode`（publisher `sst-dev`）确实存在，但它只做三件事，全在**内置终端**里：

| 命令 | 作用 |
|---|---|
| Open opencode | 在终端开会话 |
| Open opencode in new tab | 新开终端页 |
| Add Filepath to Terminal | 把当前文件路径丢给终端 |

快捷键 `Ctrl/Cmd+Esc`。**它不是图形面板**，没有侧边栏、没有 diff 视图。

要“VS Code 里的图形界面”，别指望 opencode，用 Continue 或 Cline。它们本来就是 webview 面板，填个 baseURL 就接上了。

社区还有个 `opencode-vscode`（0.1.2，号称 GUI），版本太浅，不建议依赖。

---

## 8. 第五阶段：运维

### 8.1 花费与调用记录

`database_url` 配好后。生产使用时优先考虑 Postgres；SQLite 适合作为单机试用，虚拟 key、预算和访问控制支持情况需按当前 LiteLLM 版本验证：

```powershell
curl.exe -s http://127.0.0.1:4000/spend/logs -H "Authorization: Bearer $env:LITELLM_MASTER_KEY"
```

网关自带界面在 `http://127.0.0.1:4000/ui`。

v1 说“无需数据库”——那意味着**没有任何记录**，重启清零，查不到是哪个模型烧的钱。

### 8.2 key 分权（强烈建议）

| key | 允许的别名 | 用途 |
|---|---|---|
| `sk-company-*` | `code-fast`, `reason-deep` | 工作项目，只允许公司批准的模型 |
| `sk-personal-*` | 其余全部 | 个人项目 |

虚拟 key 的模型限制需用独立 key 实测。每个 fallback 目标也必须被该 key 授权；因此不要把可含公司数据的请求默认降级到个人云模型。未配置 key 分权前，master key 可访问配置中的所有模型，不能把它交给日常前端。

### 8.3 常驻运行

**任务计划程序**（简单）：

```powershell
schtasks /create /tn "LiteLLM Gateway" /sc onlogon /rl highest ^
  /tr "powershell -NoProfile -WindowStyle Hidden -File C:\Users\ziyi.fang\.litellm\start.ps1"
```

`start.ps1` 内容：加载 `env.ps1`，然后前台跑 `litellm`，输出重定向到 `proxy.log`。

**NSSM**（更稳，能自动重启）：`nssm install LiteLLM`，程序填 `litellm.exe`，参数填 config 与端口。

> 不要用 `&` / `Start-Process` 就完事。窗口一关，网关就死。

### 8.4 升级

```powershell
pip install -U "litellm[proxy]"
```

升级后重跑第 4.6 节四条验收。别名没变，前端不用动。

---

## 9. 安全边界

1. **公司数据只走公司批准的别名。** 用独立虚拟 key 限制模型；确认 fallback 目标也符合公司数据政策。仅靠别名命名不构成边界。
2. **key 只在环境变量。** 不进 yaml、不进 git、不进截图。
3. **网关绑 `127.0.0.1`。** 绑 `0.0.0.0` 等于把公司通道对内网开放。
4. **订阅反代（Claude Pro / ChatGPT Plus）** 技术上能跑，但违反服务条款，账号可能被封。你说这两份是你个人的、在 VS Code 里用 Claude Code 和 Codex——那就**分成两条独立路径**，不要接进公司流程，也不要让反代通道承担任何工作数据。
5. **日志本身会含业务内容。** `proxy.log` 与 `litellm.db` 按敏感文件对待。

---

## 10. 执行清单（一步一验，做一步再下一步）

| # | 动作 | 验收 |
|---|---|---|
| 1 | 装 `litellm[proxy]` | `litellm --version` 有输出 |
| 2 | 建目录与 `config.yaml`，先只留 1 个模型 | 文件存在，yaml 能解析 |
| 3 | 设 `env.ps1`（含 `NO_PROXY`） | 环境变量能打印 |
| 4 | 前台启动网关 | `/health/liveliness` 返回 200 |
| 5 | 查 `/v1/models` | 看到别名列表 |
| 6 | 文本请求 `code-fast` | 返回文字 |
| 7 | 加 `vision-pro`，发一张图 | 返回对图片的描述 |
| 8 | 加 `reason-deep` 与批准的 `fallbacks` | 用隔离测试 deployment 注入可控故障，检查响应和实际路由目标 |
| 9 | 配 `database_url` | `/spend/logs` 有记录 |
| 10 | 接第一个前端（Continue 或 Cline） | 面板里能选到别名并对话 |
| 11 | 接 Claude Code / Codex | 各自能对网关发请求 |
| 12 | 做成常驻服务 | 重启机器后自动可用 |
| 13 | key 分权（换 Postgres） | 公司 key 调 `vision-pro` 被拒 |
| 14 | 转写 / 合成 / embedding | 各一条最小验证 |
| 15 | 多智能体派发 | 一次真实任务，主指挥派给执行员 |

第 8 步不要用故意写错的真实上游 key 做验证：这不一定触发预期的 fallback，也可能触发凭据告警。用隔离的测试别名和可控故障（例如临时停用测试 deployment）验证；确认请求日志中的实际目标模型。fallback 只验证技术路径，不代表该目标满足数据政策。

---

## 11. 风险登记

| 风险 | 影响 | 处置 |
|---|---|---|
| 上游内容审核 400 | 请求被拒 | 返回错误并由调用者处理；不要默认跨提供方重试 |
| 公司网关限流 | 工作中断 | 仅切到公司政策明确允许的备用通道；否则返回错误 |
| 订阅反代被封 | 账号不可用 | 独立通道，不承担工作数据 |
| 网关绑 0.0.0.0 | 公司通道外泄 | 只绑 127.0.0.1 |
| 模型型号下线 | 配置失效 | 全部用别名，只改 `model_list` |
| 没有花费记录 | 不知道钱花在哪 | 第 8.1 节 |
| Windows 关窗退出 | 网关时有时无 | 服务化，第 8.3 节 |
| key 写进 yaml | 泄露 | 只用 `os.environ/` |

---

## 附录 A：本机现状（2026-11-13 实测）

| 项 | 状态 |
|---|---|
| Python | 3.12.10 ✅ |
| pip | 25.0.1 ✅ |
| Node | 24.15.0 ✅ |
| npm | 11.12.1 ✅ |
| litellm | 1.109.1 已装 ✅ |
| 网关进程 | 已启动，127.0.0.1:4000 ✅ |
| 生效配置 | `config.starter.yaml`（仅本地模型） |
| 上游 key | 未配置 ❌ |
| opencode | 未安装 ❌ |
| ollama | 未安装，11434 无响应 ❌ |

清单进度：第 1–5 步已完成并验收。

| 验收项 | 结果 |
|---|---|
| `/health/liveliness` | `"I'm alive!"` |
| `/v1/models` | `local-offline`、`embed-local` |
| 无 key 请求 | 401 |
| `chat local-offline` | 路由正确，Ollama 未装所以连接被拒 |

剩余：第 6 步需要 Ollama 或至少一个上游 key；第 7 步需要 `vision-pro` 的 key。

## 附录 B：相对 v1 的改动清单

| v1 | v2 |
|---|---|
| OpenCode 是唯一入口 | 网关是资产，前端任选 |
| 别名 = 厂商+型号 | 别名 = 能力 |
| 无数据库 | SQLite 记花费，Postgres 做 key 分权 |
| `fallbacks` 一条 | 区分故障与上下文降级；审核拒绝默认不跨通道重试 |
| 多模态 = Gemini 一条 | 能力矩阵 + 落地顺序 + 转写/合成/embedding |
| `claude-3-7-sonnet` | 占位符，按当前型号填 |
| `nohup &` | 任务计划程序 / NSSM |
| 无验收标准 | 15 步清单，每步有验收 |
| 无风险表 | 8 条风险与处置 |
