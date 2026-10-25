# HipFire Claude Code compatibility + DeepSeek Web Search patch kit

This package carries a reusable source patch for HipFire’s Anthropic Messages endpoint. It was prepared against the official `warpfront/hipfire` tree at commit `56367a75aefa3093520a5b3880395bc65daf7a8d` (`0.4.3+patch.1`). It also applies cleanly to the older `Cefox/hipfire` master commit `6fded099bf9022ffd431abcfc7ac491e33711c8b` that you cloned: this was checked in a separate worktree, and `cargo check -q -p hipfire-cli` succeeded there. For other fork revisions, let the apply script’s clean-tree and `git apply --check` guards decide; do not force-apply it. The package does not change the installed server or write any API key.

The patch includes the previously requested Claude Code compatibility work and DeepSeek Search API support:

- Correctly lowers inline `system` messages and recognizes Claude Code’s `count_tokens` request path.
- Counts prompts through the resident Qwen4 template/tokenizer path and keeps counting side-effect free.
- Raises the total tool documentation budget to 4 MiB while retaining separate tool/name/schema limits.
- Executes Claude’s native `web_search` server tool through DeepSeek’s Search API, maps results to Anthropic server-tool response blocks, and feeds summaries back into local generation.
- Preserves the mixed server/client tool sequence: a search is deferred when Claude Code also needs to run a local tool, then executed after the client returns its result.
- Keeps the tool call authenticated with HipFire’s bearer token and reads the DeepSeek credential only from the HipFire process environment. Search result text is explicitly marked as untrusted input to reduce prompt-injection risk.

## Apply after a HipFire upgrade

Stop the HipFire service first. After `hipfire update @master`, run the following from this patch-kit directory to apply the patch to the managed source tree:

```bash
./scripts/apply.sh "$HOME/.hipfire/src"
```

If you specifically want to patch your older standalone clone instead, pass its path explicitly:

```bash
./scripts/apply.sh /path/to/your/hipfire-clone
```

The script refuses a dirty source tree, detects an already-applied patch, and uses `git apply --check` before changing files. If the patch no longer applies cleanly after a later upstream change, stop and rebase/review it; do not force-apply it.

Build the changed binaries from that source tree:

```bash
cd "$HOME/.hipfire/src"
cargo build --release --locked -p hipfire-cli -p hipfire-daemon
```

Then install/restart them through your normal HipFire setup procedure. The patch script intentionally does not overwrite binaries or restart a running service. To remove the patch before applying another version, stop HipFire and run:

```bash
./scripts/revert.sh "$HOME/.hipfire/src"
```

## DeepSeek Search API setup

The HipFire process needs one of these environment variables:

- `HIPFIRE_DEEPSEEK_API_KEY` (preferred)
- `DEEPSEEK_API_KEY` (fallback)

For a foreground launch, enter the key without echoing it and then start the service in that same shell:

```bash
read -r -s -p 'DeepSeek API key: ' HIPFIRE_DEEPSEEK_API_KEY
printf '\n'
export HIPFIRE_DEEPSEEK_API_KEY
```

For systemd, store it in a permission-restricted environment file and reference that file from the HipFire service unit; do not put the key in this patch kit or a shell command line. Because web search uses a server-held credential and the DeepSeek Search API is billed per successful request, HipFire requires `serve.api_key_file` to be configured as well. Set the matching bearer token in CC Switch. Search and Fetch are listed at $0.75 per 1,000 successful direct API requests in [DeepSeek’s Search & Fetch billing docs](https://api-docs.deepseek.com/guides/search/#billing); this patch calls the Search endpoint directly.

The adapter supports the basic `web_search_20250305` tool and direct-call use of the 20260209/20260318 variants. It refuses dynamic-filtering requests that require code execution, and it does not implement Claude’s separate `web_fetch` tool. Anthropic’s protocol requires a `server_tool_use` / `web_search_tool_result` pair; when mixed with client tools, the result is deferred until the client tool result arrives ([server tool protocol](https://platform.claude.com/docs/en/agents-and-tools/tool-use/server-tools), [web search protocol](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)). DeepSeek’s API accepts `query`, `count`, `need_content`, domain operators, and returns ranked results with summary, snippet, URL, and date ([Search API](https://api-docs.deepseek.com/guides/search/)).

## 1M-context launch and CC Switch values

For the previously selected Qwen3.8 Flash-Next 1M profile, set `HIPFIRE_MODEL` to the absolute installed model path and run:

```bash
export HIPFIRE_MODEL=/absolute/path/to/qwen3.8-flash-next.mq4-xts
./scripts/start-serve-1m.sh
```

The service binds to `0.0.0.0:11435` by default; set `BIND_ADDRESS=127.0.0.1` for localhost only. The profile uses YaRN factor 4, Q8 KV, MTP, and the existing GPU/NPU trunk route. A configured `serve.api_key_file` is required before exposing paid search to LAN clients.

CC Switch provider settings for Claude Code:

| Setting | Value |
|---|---|
| API compatibility | Anthropic Messages API |
| Base URL (same host) | `http://127.0.0.1:11435` |
| Base URL (other LAN device) | `http://192.168.0.144:11435` |
| API key | The bearer token configured by HipFire’s `serve.api_key_file` |
| Model and model aliases | The exact model ID/path accepted by the HipFire server |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` | `1048576` |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | `786432` |
| Thinking | Keep enabled; do not set a thinking-disable variable |

These values are guidance for CC Switch; this package does not edit the client’s personal provider settings. Verify that the client’s API key matches the server token and that TCP port 11435 is reachable from the intended LAN.

## Verification performed

The patch was built and tested in a temporary worktree based on the commit above, not installed into the live HipFire source:

- Anthropic adapter tests: 18 passed, including a mixed native-search/client-tool round trip.
- DeepSeek web-search tests: 5 passed, including result-to-Anthropic mapping and continuation decoding.
- Pending search/server result ordering test: passed without a network call.
- Qwen4 inline-system adapter tests in generate and loader crates: passed.
- Earlier checks on the same patch set also passed the tool-budget regression and `cargo check` for `hipfire-cli` and `hipfire-generate`.

No live DeepSeek API call was made because it is billable and no credential was supplied. Install and run it on the live server only after applying the patch and building the binaries.
