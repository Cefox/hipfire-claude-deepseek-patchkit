# HipFire Claude Code compatibility + DeepSeek Web Search patch kit

This package carries a reusable source patch for HipFire’s Anthropic Messages endpoint. It was prepared against the official `warpfront/hipfire` tree at commit `56367a75aefa3093520a5b3880395bc65daf7a8d` (`0.4.3+patch.1`). It also applies cleanly to the older `Cefox/hipfire` master commit `6fded099bf9022ffd431abcfc7ac491e33711c8b` that you cloned: this was checked in a separate worktree, and `cargo check -q -p hipfire-cli` succeeded there. For other fork revisions, let the apply script’s clean-tree and `git apply --check` guards decide; do not force-apply it. The package does not change the installed server or write any API key.

The patch includes the previously requested Claude Code compatibility work and DeepSeek Search API support:

- Correctly lowers inline `system` messages and recognizes Claude Code’s `count_tokens` request path.
- Counts prompts through the resident Qwen4 template/tokenizer path and keeps counting side-effect free.
- Supports client-side ToolSearch `tool_reference` results and `defer_loading`: only referenced deferred schemas enter the rendered prompt, using the same projection for counting and generation.
- Raises the total tool documentation budget to 4 MiB while retaining separate tool/name/schema limits.
- Executes Claude’s native `web_search` server tool through DeepSeek’s Search API, maps results to Anthropic server-tool response blocks, and feeds summaries back into local generation.
- Preserves the mixed server/client tool sequence: a search is deferred when Claude Code also needs to run a local tool, then executed after the client returns its result.
- Uses the DeepSeek key carried by each Claude Code request; a server-side DeepSeek key remains an optional fallback and requires HipFire bearer authentication. Search result text is explicitly marked as untrusted input to reduce prompt-injection risk.

## Apply after a HipFire upgrade

Stop the HipFire service first. After `hipfire update @master`, run the following from this patch-kit directory to apply the patch to the managed source tree:

```bash
./scripts/apply.sh "$HOME/.hipfire/src"
```

If you specifically want to patch your older standalone clone instead, pass its path explicitly:

```bash
./scripts/apply.sh /path/to/your/hipfire-clone
```

The script applies the original compatibility patch followed by the deferred-tool patch. It also upgrades a source tree that already has the original patch, detects an already-completed upgrade, and refuses unrelated dirty source trees. Each patch is checked before application; if a fresh installation cannot apply the second patch, the first patch is rolled back. If the patch no longer applies cleanly after a later upstream change, stop and rebase/review it; do not force-apply it.

Build the changed binaries from that source tree:

```bash
cd "$HOME/.hipfire/src"
cargo build --release --locked -p hipfire-cli -p hipfire-daemon
```

The patch script intentionally does not overwrite binaries or restart a running service. For the standard managed installation, back up and replace both binaries after the build:

```bash
backup="$HOME/.hipfire/backups/hipfire-patch-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 700 "$backup"
cp -p "$HOME/.hipfire/bin/hipfire" "$backup/hipfire"
cp -p "$HOME/.hipfire/bin/daemon" "$backup/daemon"
install -m 755 "$HOME/.hipfire/src/target/release/hipfire" "$HOME/.hipfire/bin/hipfire"
install -m 755 "$HOME/.hipfire/src/target/release/daemon" "$HOME/.hipfire/bin/daemon"
```

Start HipFire again using your normal service command. The backup directory contains the previous binaries for rollback. To remove the patch before applying another version, stop HipFire and run:

```bash
./scripts/revert.sh "$HOME/.hipfire/src"
```

## DeepSeek Search API setup

The patched HipFire server accepts the DeepSeek key either in a Claude Code request header or from its own process environment. When both are present, the request header takes precedence. The header name is `X-HipFire-DeepSeek-API-Key`.

### Configure both keys through CC Switch

In the Claude Code provider editor, set the protocol to Anthropic Messages and the base URL to `http://127.0.0.1:11435`. If you have configured HipFire bearer authentication, enter its matching token in the provider's **API Key** field. CC Switch maps that value to Claude Code's `ANTHROPIC_AUTH_TOKEN`.

Then add the DeepSeek Search key in the Claude Code config JSON editor at the bottom of the provider editor. Preserve the existing JSON and add this property inside its `env` object:

```json
"ANTHROPIC_CUSTOM_HEADERS": "X-HipFire-DeepSeek-API-Key: <DEEPSEEK_SEARCH_API_KEY>"
```

Replace the placeholder with your DeepSeek API key. Claude Code requires version 2.1.227 or newer for `ANTHROPIC_CUSTOM_HEADERS`; this host has 2.1.310. CC Switch v4.0.19 writes custom environment variables from this editor to the global `~/.claude/settings.json`, so the DeepSeek header is sent to whichever Claude Code provider is selected. Remove it from the editor before switching to another provider. The value is stored in that JSON file; treat the file as a secret. Keep the HipFire base URL on `127.0.0.1` when CC Switch and HipFire run on the same machine, because plain HTTP over a LAN would expose the header in transit. See the [Claude Code environment-variable reference](https://code.claude.com/docs/en/env-vars) and [CC Switch provider editor guide](https://github.com/farion1231/cc-switch/blob/v4.0.19/docs/user-manual/en/2-providers/2.3-edit.md).

### Configure the key in the HipFire service instead

If you do not want Claude Code to send the DeepSeek key, set one of these variables in the HipFire process environment:

- `HIPFIRE_DEEPSEEK_API_KEY` (preferred)
- `DEEPSEEK_API_KEY` (fallback)

For a foreground launch, enter the key without echoing it and then start the service in that same shell:

```bash
read -r -s -p 'DeepSeek API key: ' HIPFIRE_DEEPSEEK_API_KEY
printf '\n'
export HIPFIRE_DEEPSEEK_API_KEY
```

For systemd, store it in a permission-restricted environment file and reference that file from the HipFire service unit; do not put the key in this patch kit or a shell command line. With the CC Switch request-header method above, HipFire does not need a server-side DeepSeek key or a `serve.api_key_file` just to perform search: each request carries the caller's DeepSeek credential. If you instead configure the DeepSeek key in HipFire's process environment, enable HipFire bearer authentication so LAN clients cannot spend that server-held key. Independently, bearer authentication is recommended when exposing the inference API to a LAN. Search and Fetch are listed at $0.75 per 1,000 successful direct API requests in [DeepSeek’s Search & Fetch billing docs](https://api-docs.deepseek.com/guides/search/#billing); this patch calls the Search endpoint directly.

The adapter supports the basic `web_search_20250305` tool and direct-call use of the 20260209/20260318 variants. It refuses dynamic-filtering requests that require code execution, and it does not implement Claude’s separate `web_fetch` tool. Anthropic’s protocol requires a `server_tool_use` / `web_search_tool_result` pair; when mixed with client tools, the result is deferred until the client tool result arrives ([server tool protocol](https://platform.claude.com/docs/en/agents-and-tools/tool-use/server-tools), [web search protocol](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)). DeepSeek’s API accepts `query`, `count`, `need_content`, domain operators, and returns ranked results with summary, snippet, URL, and date ([Search API](https://api-docs.deepseek.com/guides/search/)).

## Claude Code ToolSearch / context-overflow fix (2026-10-25)

The observed 256K failure was caused by protocol compatibility, not by an inaccurate Qwen tokenizer. A fresh Claude Code 2.1.310 conversation sent `hi` with about 14.6K rendered input tokens. When its client-side ToolSearch returned a `tool_reference`, the old adapter rejected that block. Claude Code then disabled tool search and resent 232 complete tool definitions (about 909K JSON characters), producing about 274K input tokens before the 32K output allowance.

`patches/hipfire-claude-deferred-tools.patch` fixes that round trip. It accepts `tool_reference` blocks inside user `tool_result` content, validates their names against the request's tool definitions, and activates only referenced deferred tools. Unselected `defer_loading: true` definitions stay out of the prompt. The count and generation endpoints use this same transformation. Explicitly non-deferred definitions remain available; genuinely oversized prompts are still refused rather than silently truncated.

This implements client-side ToolSearch results. It does not implement Anthropic's server-side regex/BM25 search tools. Selected schemas are exposed through Qwen's normal function-tool section, so activating a tool can change the prompt prefix; exact Anthropic inline-expansion/cache behavior is not claimed. See [Anthropic's tool-search protocol](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool).

For the current native 256K service, configure CC Switch as follows (do not append `[1m]` to the model):

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:11435",
    "ANTHROPIC_MODEL": "qwen3.8:flash-next",
    "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "262144",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "196608",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "32000",
    "CLAUDE_CODE_EFFORT_LEVEL": "xhigh"
  }
}
```

Merge these entries into the existing configuration and preserve authentication/custom headers. Configure all model aliases and subagent overrides for the same accepted model ID. The package does not edit personal Claude Code settings. Restart Claude Code after rebuilding/restarting HipFire. Prefer a new CC conversation for verification: a conversation that already switched to eager loading can continue to resend the enlarged tool registry.

Run the local regression against a running patched service without external search calls:

```bash
python3 scripts/verify-deferred-tools.py --url http://127.0.0.1:11435 --model qwen3.8:flash-next
```

The script checks that 232 dormant tool definitions do not inflate the prompt, a referenced tool is activated, both a normal and a ToolSearch follow-up request succeed, and `/count_tokens` matches total input usage (including cached input). It generates only short responses and never executes a returned client tool.

## Optional historical 1M-context launch and CC Switch values

For the previously selected Qwen3.8 Flash-Next 1M profile, set `HIPFIRE_MODEL` to the absolute installed model path and run:

```bash
export HIPFIRE_MODEL=/absolute/path/to/qwen3.8-flash-next.mq4-xts
./scripts/start-serve-1m.sh
```

The service binds to `0.0.0.0:11435` by default; set `BIND_ADDRESS=127.0.0.1` for localhost only. The profile uses YaRN factor 4, Q8 KV, MTP, and the existing GPU/NPU trunk route. With the CC Switch request-header key, no extra HipFire bearer-key setup is required for search; bearer authentication remains recommended for general LAN API access.

CC Switch provider settings for Claude Code:

| Setting | Value |
|---|---|
| API compatibility | Anthropic Messages API |
| Base URL (same host) | `http://127.0.0.1:11435` |
| Base URL (other LAN device) | Use a TLS-protected endpoint; plain HTTP exposes the custom DeepSeek header |
| API key | If HipFire bearer authentication is configured, use the matching token; the request-header search mode needs no extra server token |
| Model and model aliases | The exact model ID/path accepted by the HipFire server |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` | `1048576` |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | `786432` |
| Thinking | Keep enabled; do not set a thinking-disable variable |

These values are guidance for CC Switch; this package does not edit the client’s personal provider settings. Verify that TCP port 11435 is reachable from the intended host. When bearer authentication is enabled, the provider API key must match the server token.

## Deferred-tool verification results

On the native 262144-token Qwen3.8 Flash-Next service with forced NPU enabled:

| Check | Count endpoint | Generation input usage |
|---|---:|---:|
| Baseline request, only ToolSearch | 278 | — |
| Same request plus 232 dormant schemas (1,172,342 bytes of tool JSON) | 278 | 278 |
| Follow-up activating one deferred schema | 1,201 | 1,201 |
| Replay using the local CC tool registry and its WebSearch reference | 14,875 | 14,875 |

The eager fallback registry from that CC session still counts as 273,472 tokens in the replay control, exceeding native 256K. The fix preserves lazy discovery so that fallback is not necessary; it does not falsify counts or silently discard explicitly active tools. Exact failing-session counts differ because its message history changed between retries. The real-request replay used a short, explicit 16-token generation cap; its `max_tokens` stop reason is expected for that bounded diagnostic.

An end-to-end Claude Code 2.1.310 run also passed: it called only ToolSearch, received one `tool_reference`, and returned `OK` in two turns with zero API errors. Its two request shapes contained 12 and 13 tool definitions, so no eager-registry fallback occurred. No external web search was executed.

Sanitized reports (no user prompts, keys, or tool documentation) are in `verification/`. The installed CLI checksum is recorded in the real-request report. The pinned upstream is HipFire, an original AMD inference engine by Kaden Schutt, under its existing Apache-2.0 / per-file license notices; this kit retains the upstream notices in modified source files.

## Verification performed

The patch was tested in a temporary worktree based on the commit above:

- Anthropic adapter tests after the deferred-tool fix: 22 passed, including deferred-schema filtering, reference validation, count/generation projection parity, and the existing native-search/client-tool round trip.
- DeepSeek web-search tests: passed, including key precedence, a local mock Search API request, result-to-Anthropic mapping, and continuation decoding.
- HipFire CLI tests: 877 passed, 0 failed, 1 ignored. HipFire daemon tests: 62 passed, 0 failed.
- Pending search/server result ordering test: passed without a network call.
- Qwen4 inline-system adapter tests in generate and loader crates: passed.
- Earlier checks on the same patch set also passed the tool-budget regression and `cargo check` for `hipfire-cli` and `hipfire-generate`.

No live DeepSeek API call was made because it is billable and no credential was supplied. The local mock test verifies the request's bearer header and response mapping without contacting DeepSeek.
