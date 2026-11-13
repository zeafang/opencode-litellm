# local-ai-gateway

一台机器、一个端口、一个 key：把手上的所有模型收成一个 OpenAI 兼容接口。

- **网关**：LiteLLM Proxy，只绑 `127.0.0.1`。
- **别名**：按**能力**命名（`vision-pro`、`code-fast`），不按厂商。
- **前端**：Claude Code、Codex、Continue、Cline、OpenCode、脚本，全部指同一个 `baseURL`。
- **边界**：公司通道与个人通道靠独立虚拟 key 分开，不靠记性。

完整设计见 [`docs/gateway-plan.md`](docs/gateway-plan.md)。

---

## 快速开始

```powershell
# 1. 依赖
pip install "litellm[proxy]"

# 2. 拿到本仓库
git clone https://github.com/zeafang/local-ai-gateway.git
cd local-ai-gateway

# 3. 配置（只改这一份，不要提交）
Copy-Item config\config.example.yaml "$HOME\.litellm\config.yaml"
Copy-Item scripts\env.example.ps1      "$HOME\.litellm\env.ps1"
notepad "$HOME\.litellm\env.ps1"      # 填 key

# 4. 启动
.\scripts\start.ps1

# 5. 验收
.\scripts\verify.ps1
```

`verify.ps1` 全部通过，网关就活了。

---

## 目录

```text
config/config.example.yaml    网关配置模板（复制到 ~/.litellm/config.yaml）
scripts/env.example.ps1       环境变量模板（复制到 ~/.litellm/env.ps1）
scripts/start.ps1             前台启动
scripts/verify.ps1            健康检查 + 别名清单 + 一次文本调用
scripts/smoke_test.py         文本 / 图片 / embedding 三条链路自测
scripts/install-service.ps1   注册开机自启（任务计划程序）
frontends/                    各前端的最小接入样例
tests/test_config.py          配置自检（别名、降级链、明文 key）
docs/gateway-plan.md          完整方案
```

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

---

## 前端接入

| 前端 | 样例 |
|---|---|
| Continue | `frontends/continue.config.example.yaml` |
| Cline / Roo Code | `frontends/README.md` |
| Claude Code | `frontends/claude-code.ps1` |
| OpenCode | `frontends/opencode.config.example.json` |

统一填三样：`baseURL = http://127.0.0.1:4000/v1`、`apiKey = <该前端的虚拟 key>`、`model = <别名>`。

---

## 安全

- 网关只绑 `127.0.0.1`，不要 `0.0.0.0`。
- `~/.litellm/env.ps1` 不进 git。
- 每个前端发一个独立虚拟 key，限制可用别名。
- 含公司数据的请求，降级目标也必须是公司批准的通道。
- 上游审核拒绝默认直接返回，不跨提供方重试。

---

## 排查

| 现象 | 先看 |
|---|---|
| 启动即退 | 端口占用：`netstat -ano \| findstr :4000` |
| 调用 502 / 超时 | 代理拦了 localhost：设 `NO_PROXY` |
| 图片报错 | 发给了非视觉模型：换 `vision-pro` |
| 401 | `LITELLM_MASTER_KEY` 没加载：先 `. env.ps1` |
| 没有花费记录 | `LITELLM_DATABASE_URL` 没配 |

## License

MIT