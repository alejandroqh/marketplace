<p align="center">
  <img src="https://img.shields.io/badge/Marketplace-blue?style=for-the-badge" alt="Marketplace" />
  <br/>
  <strong>Personal Collection of Harness plugins for AI agents</strong>
  <br/>
  <sub>Browser automation &bull; Terminal emulation &bull; Memory &bull; Repo exploration &bull; Privilege elevation</sub>
</p>

<p align="center">
  <a href="#installation"><img src="https://img.shields.io/badge/-Install-green?style=flat-square" alt="Install" /></a>
  <a href="#plugins"><img src="https://img.shields.io/badge/-Plugins-purple?style=flat-square" alt="Plugins" /></a>
  <a href="https://github.com/alejandroqh"><img src="https://img.shields.io/badge/-Author-orange?style=flat-square" alt="Author" /></a>
  <img src="https://img.shields.io/badge/plugins-5-blue?style=flat-square" alt="5 plugins" />
  <img src="https://img.shields.io/badge/license-Apache--2.0-lightgrey?style=flat-square" alt="License" />
</p>

---

## Quick Install (MCP Servers)

Launch the interactive installer to pick tools and targets:

```sh
curl -fsSL https://raw.githubusercontent.com/alejandroqh/marketplace/main/h39.sh | bash
```

Binaries are installed to `~/.local/bin` (override with `H39_INSTALL_DIR`).

---

## Installation (OpenClaw Plugins)

Point OpenClaw at this marketplace and install any plugin in one command:

```bash
# Install a plugin from this marketplace
openclaw plugins install browser39 \
  --marketplace https://github.com/alejandroqh/marketplace

# Browse all available plugins
openclaw plugins marketplace list \
  https://github.com/alejandroqh/marketplace
```

For local development:

```bash
git clone https://github.com/alejandroqh/marketplace.git
cd marketplace

# Link a plugin locally (no copy, instant updates)
openclaw plugins install ./browser39 -l

# Install its dependencies
cd browser39 && npm install
```

---

## Plugins

### browser39

> Headless web browser for AI agents. Fetches pages as token-optimized markdown with JS support, forms, cookies, storage, and web search.

| | |
|---|---|
| **Version** | `1.6.2` |
| **License** | Apache-2.0 |
| **Repo** | [alejandroqh/browser39](https://github.com/alejandroqh/browser39) |

<details>
<summary><strong>18 tools</strong> &mdash; click to expand</summary>

| Tool | Description |
|------|-------------|
| `browser39_fetch` | Load a page as markdown |
| `browser39_click` | Follow a link or click an element |
| `browser39_links` | List all links on the current page |
| `browser39_dom_query` | Run CSS selectors or JS on the DOM |
| `browser39_fill` | Fill form fields |
| `browser39_submit` | Submit a form |
| `browser39_search` | Search the web |
| `browser39_cookies` | List cookies |
| `browser39_set_cookie` | Set a cookie |
| `browser39_delete_cookie` | Delete a cookie |
| `browser39_storage_get` | Get a storage value |
| `browser39_storage_set` | Set a storage value |
| `browser39_storage_delete` | Delete a storage value |
| `browser39_storage_list` | List storage entries |
| `browser39_storage_clear` | Clear all storage |
| `browser39_back` | Navigate back |
| `browser39_forward` | Navigate forward |
| `browser39_history` | View navigation history |
| `browser39_info` | Current page info |

</details>

---

### memory39

> Temporal-priority memory system for AI agents. Store and recall events, facts, people, and places with intelligent scoring (relevance + importance + recency).

| | |
|---|---|
| **Version** | `1.0.1` |
| **License** | Apache-2.0 |
| **Repo** | [alejandroqh/memory39](https://github.com/alejandroqh/memory39) |

<details>
<summary><strong>8 tools</strong> &mdash; click to expand</summary>

| Tool | Description |
|------|-------------|
| `recall` | Search memories with temporal-priority scoring |
| `event` | Store a dated or undated event |
| `thing` | Store a fact, concept, or object |
| `person` | Store a social memory about someone |
| `place` | Store a spatial/location memory |
| `forget` | Delete a memory by universal ID |
| `alter` | Modify fields of an existing memory |
| `connect` | Find 2-3 hop connections between concepts |

</details>

---

### npcterm

> Headless, in-memory terminal emulator for AI agents. Full ANSI/VT100 emulation with PTY spawning.

| | |
|---|---|
| **Version** | `1.3.1` |
| **License** | Apache-2.0 |
| **Repo** | [alejandroqh/npcterm](https://github.com/alejandroqh/npcterm) |

<details>
<summary><strong>17 tools</strong> &mdash; click to expand</summary>

| Tool | Description |
|------|-------------|
| `terminal_create` | Spawn a new terminal session |
| `terminal_destroy` | Kill a terminal session |
| `terminal_list` | List active terminals |
| `terminal_send_key` | Send a single keypress |
| `terminal_send_keys` | Send a sequence of keys |
| `terminal_mouse` | Send mouse events |
| `terminal_read_screen` | Read the full screen buffer |
| `terminal_show_screen` | Render the screen visually |
| `terminal_read_rows` | Read specific rows |
| `terminal_read_region` | Read a rectangular region |
| `terminal_status` | Terminal status and dimensions |
| `terminal_poll_events` | Poll for terminal events |
| `terminal_select` | Select text on screen |
| `terminal_scroll` | Scroll the terminal buffer |
| `viewer_start` | Start the visual viewer |
| `viewer_stop` | Stop the visual viewer |
| `viewer_open` | Open viewer in browser |

</details>

---

### repo39

> Token-optimized repository explorer for AI agents. Directory trees, symbol maps, dependency parsing, git diffs, and content search.

| | |
|---|---|
| **Version** | `1.0.1` |
| **License** | Apache-2.0 |
| **Repo** | [alejandroqh/repo39](https://github.com/alejandroqh/repo39) |

<details>
<summary><strong>8 tools</strong> &mdash; click to expand</summary>

| Tool | Description |
|------|-------------|
| `repo39_tree` | Directory tree listing |
| `repo39_identify` | Detect project type with confidence scores |
| `repo39_map` | Extract code symbols with line numbers |
| `repo39_deps` | List dependencies from manifest files |
| `repo39_changes` | Compact git log or branch diff |
| `repo39_search` | Token-compact content search |
| `repo39_review` | Symbol-level diff between git refs |
| `repo39_summary` | One-shot repo orientation |

</details>

---

### sudo39

> Guarded privilege-elevation MCP server for AI agents. Run commands via sudo, pkexec, macOS admin prompt, or Windows UAC, gated by an allowlist policy.

| | |
|---|---|
| **Version** | `1.0.1` |
| **License** | Apache-2.0 |
| **Repo** | [alejandroqh/sudo39](https://github.com/alejandroqh/sudo39) |

<details>
<summary><strong>6 tools</strong> &mdash; click to expand</summary>

| Tool | Description |
|------|-------------|
| `sudo_run` | Execute a command with elevated privileges |
| `sudo39_policy` | View the current allowlist policy |
| `sudo39_add_allowed_program` | Add a program to the allowlist |
| `sudo39_remove_allowed_program` | Remove a program from the allowlist |
| `sudo39_set_allow_unsafe` | Toggle unrestricted mode |
| `sudo39_reload_policy_from_env` | Reload policy from environment |

</details>

---

## Repo Structure

```
marketplace/
├── h39.sh                        # MCP server installer (curl | bash)
├── .claude-plugin/
│   └── marketplace.json          # Plugin index
├── browser39/                    # Headless browser
│   ├── openclaw.plugin.json
│   ├── package.json
│   └── index.ts
├── memory39/                     # Agent memory
│   ├── openclaw.plugin.json
│   ├── package.json
│   └── index.ts
├── npcterm/                      # Terminal emulator
│   ├── openclaw.plugin.json
│   ├── package.json
│   └── index.ts
├── repo39/                       # Repo explorer
│   ├── openclaw.plugin.json
│   ├── package.json
│   └── index.ts
├── sudo39/                       # Privilege elevation
│   ├── openclaw.plugin.json
│   ├── package.json
│   └── index.ts
└── README.md
```

## Adding Your Own Plugin

1. Create a directory: `mkdir my-plugin`
2. Add the three required files:
   - `openclaw.plugin.json` — manifest with `id`, `contracts`, and `configSchema`
   - `package.json` — with `openclaw.extensions` and `openclaw.compat`
   - `index.ts` — export via `definePluginEntry()`
3. Register it in `.claude-plugin/marketplace.json`
4. Run `cd my-plugin && npm install`

See [CLAUDE.md](./CLAUDE.md) for the full file reference and templates.

---

## Author

**Alejandro Quintanar** &mdash; [github.com/alejandroqh](https://github.com/alejandroqh)

---

<p align="center">
  <sub>Built for <a href="https://openclaw.dev">OpenClaw</a></sub>
</p>
