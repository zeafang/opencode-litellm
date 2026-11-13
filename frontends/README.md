# 前端接入

所有前端只填三样：

| 字段 | 值 |
|---|---|
| Base URL | `http://127.0.0.1:4000/v1` |
| API Key | 该前端专用的虚拟 key（未做分权前用 master key） |
| Model | 别名，如 `code-fast` / `vision-pro` |

## Cline / Roo Code

设置 → API Provider 选 **OpenAI Compatible**：

- Base URL：`http://127.0.0.1:4000/v1`
- API Key：`<key>`
- Model ID：`code-fast`
- 勾选 “Supports Images” 仅当模型是 `vision-pro`

## Continue

见 `continue.config.example.yaml`，放到 `~/.continue/config.yaml`。

## Claude Code

见 `claude-code.ps1`。走 Anthropic 协议，LiteLLM 用 `/v1/messages` 兼容。

## Codex

`~/.codex/config.toml` 里设 `model_provider` 的 `base_url` 为
`http://127.0.0.1:4000/v1`，模型名填别名。

## OpenCode

见 `opencode.config.example.json`。

## 注意

- 每个前端发一个独立 key，限制可用别名。一个前端泄露，不牵连全部。
- Cline / Roo / Continue 会把系统提示发到上游。公司数据只配公司 key。
- 前端不会自动降级。降级发生在网关层。