"""网关三条链路自测：文本 / 图片 / embedding。零依赖，只用标准库。

    python scripts/smoke_test.py --model local-offline
    python scripts/smoke_test.py --model vision-pro --image ui.png
    python scripts/smoke_test.py --embed embed-local
"""
import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request


def post(url, key, payload, timeout=180):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--base", default="http://127.0.0.1:4000")
    p.add_argument("--key", default=os.environ.get("LITELLM_MASTER_KEY"))
    p.add_argument("--model", default="")
    p.add_argument("--image", default="")
    p.add_argument("--embed", default="")
    a = p.parse_args()

    if not a.key:
        sys.exit("缺少 key：设置 LITELLM_MASTER_KEY 或传 --key")

    base = a.base.rstrip("/")
    ok = True

    if a.model:
        content = [{"type": "text", "text": "只回复两个字：通了"}]
        if a.image:
            with open(a.image, "rb") as f:
                b64 = base64.b64encode(f.read()).decode()
            content.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/png;base64,{b64}"},
            })
        try:
            r = post(f"{base}/v1/chat/completions", a.key, {
                "model": a.model,
                "messages": [{"role": "user", "content": content}],
                "max_tokens": 64,
            })
            print(f"[PASS] chat {a.model}: {r['choices'][0]['message']['content'][:80]}")
        except urllib.error.HTTPError as e:
            print(f"[FAIL] chat {a.model}: HTTP {e.code} {e.read()[:300]!r}")
            ok = False

    if a.embed:
        try:
            r = post(f"{base}/v1/embeddings", a.key, {"model": a.embed, "input": ["a", "b"]})
            n = len(r["data"][0]["embedding"])
            print(f"[PASS] embed {a.embed}: dim={n}")
        except urllib.error.HTTPError as e:
            print(f"[FAIL] embed {a.embed}: HTTP {e.code} {e.read()[:300]!r}")
            ok = False

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())