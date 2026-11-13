"""配置自检：别名唯一、降级目标存在、没有明文 key。

    python tests/test_config.py
"""
import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIGS = sorted((ROOT / "config").glob("*.yaml"))
SECRET = re.compile(r"(sk-[A-Za-z0-9]{12,}|AIza[0-9A-Za-z_\-]{20,})")

failures = []


def check(name, ok, detail=""):
    print(("[PASS] " if ok else "[FAIL] ") + name + (f" {detail}" if detail else ""))
    if not ok:
        failures.append(name)


for path in CONFIGS:
    cfg = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    models = cfg.get("model_list") or []
    aliases = [m.get("model_name") for m in models]

    check(f"{path.name}: 有模型", bool(aliases))
    check(f"{path.name}: 别名唯一", len(aliases) == len(set(aliases)))
    check(f"{path.name}: 别名非空", all(aliases))

    # 上游 model 必须带 provider 前缀
    bad = [m["model_name"] for m in models
           if "/" not in str((m.get("litellm_params") or {}).get("model", ""))]
    check(f"{path.name}: 上游带 provider 前缀", not bad, str(bad))

    # 降级目标必须是已定义的别名
    router = cfg.get("router_settings") or {}
    for key in ("fallbacks", "context_window_fallbacks", "content_policy_fallbacks"):
        for entry in router.get(key) or []:
            for src, targets in entry.items():
                check(f"{path.name}: {key} 源 {src} 存在", src in aliases)
                for t in targets or []:
                    check(f"{path.name}: {key} 目标 {t} 存在", t in aliases)

    # 不允许明文密钥
    hits = SECRET.findall(path.read_text(encoding="utf-8"))
    check(f"{path.name}: 无明文 key", not hits, str(hits))

print()
if failures:
    print(f"{len(failures)} 项失败")
    sys.exit(1)
print("全部通过")