# z39 — OpenClaw plugin

> Z3-powered SMT reasoning for AI agents. Verifiable yes/no answers for scheduling, boolean logic, configuration, and action safety.

This plugin wraps the [`z39`](https://github.com/alejandroqh/z39) MCP server — the binary is spawned on demand and its tools are proxied through OpenClaw.

---

## Install

### Option 1 — via the `h39` script (recommended)

`h39` downloads the matching `z39` release for your platform (bundled with the `z3` solver) and wires it into every detected MCP client (Claude Code CLI, Claude Desktop, OpenCode, Codex, OpenClaw).

**Interactive menu**

```sh
curl -fsSL https://raw.githubusercontent.com/alejandroqh/marketplace/main/h39.sh | sh
```

Pick `z39` from the tool list, then pick a target (or `all`).

**Direct install**

```sh
# install z39 into every detected MCP client
h39 install z39

# install only for one target
h39 install z39 --target claude-cli

# update to the latest release
h39 update z39

# uninstall (keep binaries)
h39 uninstall z39

# uninstall and remove the z39 + z3 binaries
h39 uninstall z39 --purge
```

Binaries land in `~/.local/bin` by default (override with `H39_INSTALL_DIR`). The release zip ships `z39` alongside its `z3` dependency — `h39` extracts both and makes them executable.

### Option 2 — via OpenClaw marketplace

```sh
openclaw plugins install z39 \
  --marketplace https://github.com/alejandroqh/marketplace
```

For local development:

```sh
git clone https://github.com/alejandroqh/marketplace.git
cd marketplace/z39
npm install
openclaw plugins install . -l
```

The plugin expects the `z39` binary on your `PATH` (or set `binaryPath` in the plugin config). Install it separately from [alejandroqh/z39 releases](https://github.com/alejandroqh/z39/releases) if you skipped `h39`.

---

## Tools

| Tool | Purpose |
|------|---------|
| `z39_schedule` | Fit tasks into a time slot with ordering/overlap constraints |
| `z39_logic` | Prove always-true, find counterexamples, check equivalence/consistency |
| `z39_config` | Validate configuration constraints across bool/int/enum variables |
| `z39_safety` | Pre-check an action against protected resources (no Z3 invocation) |
| `z39_solve` | Execute a raw SMT-LIB2 formula (blocking) |
| `z39_solve_async` | Start a long-running solve, returns a `job_id` |
| `z39_job_status` | Poll an async solve job |
| `z39_job_result` | Retrieve a completed async solve result |
| `z39_job_cancel` | Cancel an in-progress async solve |

---

## Configuration

```json
{
  "binaryPath": "z39"
}
```

| Key | Description |
|-----|-------------|
| `binaryPath` | Path to the `z39` binary. Defaults to `z39` (must be on `PATH`). The `z3` solver must also be on `PATH` or next to `z39`. |

---

**Repo:** [alejandroqh/z39](https://github.com/alejandroqh/z39) &bull; **License:** Apache-2.0
