#!/usr/bin/env python3
"""Exercise count/generation parity with client-side deferred tool discovery."""
import argparse
import json
import os
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:11435")
    parser.add_argument("--model", default="qwen3.8:flash-next")
    parser.add_argument("--output", help="Optional JSON report path")
    args = parser.parse_args()
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def post(path, body):
        headers = {"Content-Type": "application/json", "anthropic-version": "2023-06-01"}
        if os.environ.get("HIPFIRE_API_KEY"):
            headers["Authorization"] = "Bearer " + os.environ["HIPFIRE_API_KEY"]
        request = urllib.request.Request(args.url.rstrip("/") + path,
                                         data=json.dumps(body).encode(), headers=headers)
        with opener.open(request, timeout=120) as response:
            return json.load(response)

    def count(body):
        return post("/v1/messages/count_tokens", body)["input_tokens"]

    def generate(body, expected):
        response = post("/v1/messages", body)
        usage = response["usage"]
        actual = sum(usage.get(key, 0) or 0 for key in
                     ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
        if actual != expected:
            raise AssertionError(f"count_tokens={expected}, generated input usage={actual}")
        return {"count_tokens": expected, "generation_input_tokens": actual,
                "output_tokens": usage["output_tokens"], "stop_reason": response["stop_reason"]}

    search = {"name": "ToolSearch", "description": "Find optional tools when needed.",
              "input_schema": {"type": "object", "properties": {"query": {"type": "string"}}}}
    body = {"model": args.model, "max_tokens": 16, "thinking": {"type": "disabled"},
            "system": "For this diagnostic, reply only OK and do not call tools.",
            "tools": [search], "messages": [{"role": "user", "content": "hi"}]}
    baseline = count(body)
    deferred = [{"name": f"mcp_optional_{i}", "defer_loading": True,
                 "description": "Documentation for an optional deferred MCP tool. " * 100,
                 "input_schema": {"type": "object", "properties": {"query": {"type": "string"}}}}
                for i in range(232)]
    body["tools"] = [search] + deferred
    dormant = count(body)
    if dormant != baseline:
        raise AssertionError(f"Dormant tools inflated count: baseline={baseline}, dormant={dormant}")
    initial = generate(body, dormant)
    body["messages"] += [
        {"role": "assistant", "content": [{"type": "tool_use", "id": "toolu_search_regression",
             "name": "ToolSearch", "input": {"query": "select:mcp_optional_7"}}]},
        {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "toolu_search_regression",
             "content": [{"type": "tool_reference", "tool_name": "mcp_optional_7"}]},
             {"type": "text", "text": "Tool loaded. Reply only OK."}]},
    ]
    selected = count(body)
    if not dormant < selected < dormant + 10000:
        raise AssertionError(f"Unexpected activated-tool count: {selected} (initial {dormant})")
    follow_up = generate(body, selected)
    report = {"model": args.model, "deferred_tools": len(deferred),
              "wire_tool_json_bytes": len(json.dumps(body["tools"]).encode()),
              "baseline_input_tokens": baseline, "dormant_tools_input_tokens": dormant,
              "initial": initial, "tool_reference_follow_up": follow_up, "passed": True}
    text = json.dumps(report, ensure_ascii=False, indent=2)
    print(text)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as output:
            output.write(text + "\n")


if __name__ == "__main__":
    main()
