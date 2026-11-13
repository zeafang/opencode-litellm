# 本地 AI 统一网关与多智能体调度方案（LiteLLM + OpenCode）

## 1. 架构目标与拓扑图

本方案旨在通过 **本地 LiteLLM 网关（Gateway）** 聚合你手头所有的模型资源（包括公司内网 LiteLLM 代理的 DeepSeek、个人 Gemini Pro、未来的 Claude Pro / GitHub Copilot 订阅及本地 Ollama 模型），并由 **OpenCode** 作为唯一的终端交互入口，实现“**单窗口管理 + 主从智能体（Orchestrator + Subagents）自动调度**”。

### 系统数据流架构

```text
+-------------------------------------------------------------------+
|                        OpenCode (唯一交互前端)                      |
|  +-----------------------+     +-------------------------------+  |
|  |  主指挥官 (Architect)  | --> |  专项子代理 (Subagents)        |  |
|  |  - 多模态识图/架构拆解   |     |  - Fast-Coder (日常编码/SQL)  |  |
|  |  - 任务派发与结果验收   |     |  - Deep-Thinker (疑难/推理)   |  |
|  +-----------------------+     +-------------------------------+  |
+---------------------------------+---------------------------------+
                                  | 统一 OpenAI 兼容协议
                                  | http://127.0.0.1:4000/v1
                                  v
+-------------------------------------------------------------------+
|                   本地 LiteLLM Proxy (中枢路由网关)                 |
|  - 统一接口标准化       - 故障自动切换 (Fallback)                  |
|  - 敏感信息隔离边界     - 本地 Token 消耗监控                      |
+---+--------------------+--------------------+------------------+--+
    |                    |                    |                  |
    v                    v                    v                  v
[公司 LiteLLM]      [Google AI API]     [订阅反代/OAuth]    [本地 Ollama]
DeepSeek V3/R1     Gemini 2.5 Pro      Claude / Copilot    本地离线小模型
(内网安全合规)      (超长上下文/视觉)    (复杂逻辑主力)        (完全离线隐私)
```

---

## 2. 第一阶段：部署本地 LiteLLM 统一网关

个人在本地部署 LiteLLM 无需配置复杂的数据库，直接通过 Python 轻量级运行即可。

### 2.1 安装依赖
打开终端（Windows PowerShell 或 WSL 均可），安装带有代理功能的 LiteLLM：

```bash
pip install 'litellm[proxy]'
```

### 2.2 创建网关配置文件 (`config.yaml`)
在你习惯的目录（例如 `C:\Users\ziyi.fang\.litellm\config.yaml` 或 `~/.litellm/config.yaml`）新建 `config.yaml`，将所有模型资源注册进去：

```yaml
model_list:
  # 1. 级联公司内网 LiteLLM（安全合规，走公司 DeepSeek 额度）
  - model_name: company-deepseek-v3
    litellm_params:
      model: openai/deepseek-chat        # 需与公司网关暴露的 model_name 一致
      api_base: http://公司litellm地址:4000/v1
      api_key: os.environ/COMPANY_LITELLM_KEY

  - model_name: company-deepseek-r1
    litellm_params:
      model: openai/deepseek-reasoner
      api_base: http://公司litellm地址:4000/v1
      api_key: os.environ/COMPANY_LITELLM_KEY

  # 2. 个人 Google Gemini Pro（处理多模态识图、超长仓库分析）
  - model_name: my-gemini-pro
    litellm_params:
      model: gemini/gemini-2.5-pro
      api_key: os.environ/GEMINI_API_KEY

  # 3. 未来扩展：个人 Anthropic Claude（API 或 OAuth 桥接）
  - model_name: my-claude-sonnet
    litellm_params:
      model: anthropic/claude-3-7-sonnet-20250219
      api_key: os.environ/ANTHROPIC_API_KEY

  # 4. 未来扩展：本地 Ollama 离线模型（完全断网可用）
  - model_name: local-qwen-coder
    litellm_params:
      model: ollama/qwen2.5-coder:14b
      api_base: http://localhost:11434

# 网关全局配置（高可用与故障转移）
router_settings:
  routing_strategy: simple-shuffle
  num_retries: 2
  fallbacks:
    # 如果公司 DeepSeek 偶尔限流，自动降级到本地模型或备用通道
    - {"company-deepseek-v3": ["local-qwen-coder"]}

general_settings:
  # 设置本地网关的访问密钥（供 OpenCode 连接使用）
  master_key: sk-local-master-123456
```

### 2.3 设置环境变量并启动网关
在启动前，将真实的 API Key 写入环境变量（避免明文硬编码在配置文件中）：

**Windows (PowerShell):**
```powershell
$env:COMPANY_LITELLM_KEY="你的公司虚拟Key"
$env:GEMINI_API_KEY="你的Google_API_Key"

# 启动本地网关（监听 4000 端口）
litellm --config $HOME\.litellm\config.yaml --port 4000
```

**Linux / WSL (Bash):**
```bash
export COMPANY_LITELLM_KEY="你的公司虚拟Key"
export GEMINI_API_KEY="你的Google_API_Key"

# 后台守护运行
nohup litellm --config ~/.litellm/config.yaml --port 4000 > ~/.litellm/proxy.log 2>&1 &
```

> **验证网关是否正常**：运行 `curl http://127.0.0.1:4000/v1/models -H "Authorization: Bearer sk-local-master-123456"`，能看到上述配置的模型列表即代表部署成功。

---

## 3. 第二阶段：安装并配置 OpenCode 统一调度

### 3.1 安装 OpenCode
在原生 Windows 或 WSL 中执行安装：

```bash
# 使用 npm 全局安装（推荐）
npm install -g opencode-ai

# 或通过官方脚本安装 (Linux/WSL/macOS)
curl -fsSL https://opencode.ai/install | bash
```

### 3.2 配置多模型与多智能体协同 (`opencode.json`)
在用户全局配置目录（`~/.config/opencode/config.json` 或 Windows 下 `%USERPROFILE%\.config\opencode\config.json`）中写入以下配置。

该配置实现了**两层能力**：
1. **统一接入**：所有模型均通过本地 LiteLLM 暴露，支持按 `/models` 随时秒切。
2. **智能体分层调度**：设立 `build`（主指挥官，使用 Gemini Pro）和两个专属 `subagent`（编码员和推理专家，使用公司 DeepSeek）。

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "local-gateway": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local LiteLLM Gateway",
      "options": {
        "baseURL": "http://127.0.0.1:4000/v1",
        "apiKey": "sk-local-master-123456"
      },
      "models": {
        "company-deepseek-v3": {
          "name": "DeepSeek V3 (Company Safe)"
        },
        "company-deepseek-r1": {
          "name": "DeepSeek R1 (Company Reasoning)"
        },
        "my-gemini-pro": {
          "name": "Gemini 2.5 Pro (Multimodal & Architect)"
        },
        "my-claude-sonnet": {
          "name": "Claude 3.7 Sonnet (Personal)"
        }
      }
    }
  },
  "agent": {
    "build": {
      "model": "local-gateway/my-gemini-pro",
      "description": "主指挥官：负责理解多模态截图、全局架构分析，并拆解任务派发给子代理执行"
    },
    "fast-coder": {
      "mode": "subagent",
      "model": "local-gateway/company-deepseek-v3",
      "description": "主力编码员：负责接收指挥官指令，执行具体的代码编写、SQL修改和单元测试"
    },
    "deep-thinker": {
      "mode": "subagent",
      "model": "local-gateway/company-deepseek-r1",
      "description": "深度推理专家：负责排查复杂 Bug、并发死锁或算法逻辑验证"
    }
  }
}
```

---

## 4. 第三阶段：未来个人订阅（Copilot / Claude Pro / GPT）接入指南

当你未来开通包月网页订阅（非按量付费 API）时，可按以下方式无缝并入上述体系，**无需打开多个官方 CLI**：

1. **GitHub Copilot ($10/mo)**：
   * **直接原生绑定**：在终端运行 `opencode auth login`，选择 `GitHub Copilot` 并完成浏览器授权。
   * 授权后，OpenCode 内部会直接新增 `github-copilot` 提供商，你可以直接调用其包含的 Claude Sonnet、GPT-4o、o3-mini 模型，不占用你其他 API 额度。
2. **Claude Pro ($20/mo)**：
   * 运行 `opencode auth login` 选择 `Anthropic`，使用你的 Claude Pro 网页账号进行 OAuth 登录即可直接复用订阅额度；或者在本地运行开源的 `claude-code-proxy` 将其转为 `http://127.0.0.1:8082/v1` 后注册进本地 LiteLLM 的 `config.yaml`。
3. **ChatGPT Plus ($20/mo)**：
   * 如需复用网页版 Plus 额度，可在本地运行开源反代桥接器（如 `CLIProxyAPI`），将其映射为本地 OpenAI 兼容端口，并在 LiteLLM `config.yaml` 中新增一条 `model_name: my-gpt-plus` 即可统一纳管。

---

## 5. 日常实战工作流与安全规范

### 5.1 典型多模态与多模型调度操作
1. 进入你的项目目录并启动 OpenCode：
   ```bash
   cd /你的项目路径
   opencode
   ```
2. **场景 A：多模态开发（看图写代码 + 自动派发任务）**
   * 默认当前为主指挥官（**Gemini 2.5 Pro**）。
   * 直接在对话框引用UI截图或报错截图并下达指令：
     > *"请查看 `@ui_mockup.png` 的表格设计，结合当前项目的数据库表结构，规划前后端修改方案。规划完成后，将具体的 SQL 和组件编写任务派发给 `@fast-coder` 执行，最后由你进行代码审查。"*
3. **场景 B：随时手动热切换模型**
   * 在对话中随时输入 `/models`（或按 `Tab` 键），即可在 `DeepSeek V3`、`DeepSeek R1`、`Gemini Pro`、`Claude` 之间无缝切换，当前上下文对话历史完整保留。

### 5.2 企业数据安全边界（重要）
* **涉及公司内部业务代码、生产数据库表结构、仓库敏感数据时**：务必将当前模型切换为 `company-deepseek-v3` 或 `company-deepseek-r1`（数据流量仅经过公司内网 LiteLLM 网关，受公司安全脱敏与审计保护）。
* **涉及通用技术架构、开源组件学习、非敏感 UI 样式调试时**：可自由使用个人 `my-gemini-pro`、`GitHub Copilot` 或 `Claude` 通道。