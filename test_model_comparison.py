#!/usr/bin/env python3
"""Compare qwen3.5-plus vs qwen-flash, with and without proxy."""
import json, time, os

def test_model(endpoint, api_key, model, content, use_proxy=True):
    import httpx

    proxy_url = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
    label = f"{model} ({'via proxy' if use_proxy and proxy_url else 'direct'})"
    print(f"\n{'='*60}")
    print(f"Test: {label}")
    print(f"Content: {len(content)} chars")
    if use_proxy and proxy_url:
        print(f"Proxy: {proxy_url}")
    else:
        print(f"Proxy: NONE")
    print(f"{'='*60}")

    payload = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": (
                    "You are a helpful assistant that translates help center articles. "
                    "Translate the following content to zh. "
                    "Preserve all HTML tags and formatting exactly as they are. "
                    "Return ONLY the translated text."
                ),
            },
            {"role": "user", "content": content},
        ],
    }
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }

    client_kwargs = {"timeout": 300.0}
    if use_proxy and proxy_url:
        client_kwargs["proxy"] = proxy_url
    else:
        client_kwargs["proxy"] = None

    start = time.monotonic()
    with httpx.Client(**client_kwargs) as client:
        resp = client.post(endpoint, json=payload, headers=headers)
        resp.raise_for_status()
    elapsed_ms = (time.monotonic() - start) * 1000

    data = resp.json()
    result = data.get("choices", [{}])[0].get("message", {}).get("content", "")
    usage = data.get("usage", {})
    print(f"  Time:       {elapsed_ms:.0f}ms")
    print(f"  Output:     {len(result)} chars")
    print(f"  Tokens:     prompt={usage.get('input_tokens','?')} completion={usage.get('output_tokens','?')} total={usage.get('total_tokens','?')}")
    return elapsed_ms


if __name__ == "__main__":
    p = json.load(open("/tmp/translation_test_payload.json"))
    endpoint = p["endpoint"]
    api_key = p["api_key"]
    content = p["user_content"]

    print(f"Endpoint: {endpoint}")
    print(f"Content:  {len(content)} chars")

    results = {}

    for model in ["qwen-flash", "qwen3.5-plus"]:
        for use_proxy in [True, False]:
            proxy_url = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
            tag = f"{model} ({'proxy' if use_proxy and proxy_url else 'direct'})"
            t = test_model(endpoint, api_key, model, content, use_proxy=use_proxy)
            results[tag] = t
            time.sleep(1)

    print(f"\n{'='*60}")
    print(f"SUMMARY")
    print(f"{'='*60}")
    for tag, t in results.items():
        print(f"  {tag:35s}: {t:>8.0f}ms")
