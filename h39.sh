#!/usr/bin/env bash
#
# Harness39 (h39) - MCP tool installer for macOS and Linux
#
# Author:  Alejandro Quintanar  <https://github.com/alejandroqh>
# License: MIT
#
# DISCLAIMER: This software is provided "AS IS", without warranty of any kind,
# express or implied, including but not limited to the warranties of
# merchantability, fitness for a particular purpose and noninfringement. In no
# event shall the author or copyright holder be liable for any claim, damages
# or other liability, whether in an action of contract, tort or otherwise,
# arising from, out of or in connection with the software or the use or other
# dealings in the software. Use at your own risk.
#
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────

INSTALL_DIR="${H39_INSTALL_DIR:-${HOME}/.local/bin}"
GITHUB_ORG="alejandroqh"
SERVERS=(browser39 memory39 npcterm repo39 sudo39 z39)

# ── Output helpers ───────────────────────────────────────────────────────────

info()  { printf '\033[1;34m=>\033[0m %s\n' "$*" >&2; }
ok()    { printf '\033[1;32m=>\033[0m %s\n' "$*" >&2; }
warn()  { printf '\033[1;33m=>\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ── Server lookup ────────────────────────────────────────────────────────────

server_args() {
    case "$1" in
        browser39|memory39|repo39|z39) echo "mcp" ;;
        npcterm|sudo39)                echo "" ;;
    esac
}

server_has_windows() {
    case "$1" in
        repo39) return 1 ;;
        *)      return 0 ;;
    esac
}

# Server releases shipped as a zip archive (vs a bare binary). Zipped releases
# may bundle multiple files alongside the main binary.
server_is_zipped() {
    case "$1" in
        z39) return 0 ;;
        *)   return 1 ;;
    esac
}

# Extra binaries installed from a server's zip, alongside the main one.
# Used for chmod on install and cleanup on --purge. One per line.
server_sidecars() {
    case "$1" in
        z39) echo "z3" ;;
    esac
}

validate_server() {
    local s
    for s in "${SERVERS[@]}"; do
        [ "$s" = "$1" ] && return 0
    done
    die "Unknown MCP tool: $1. Valid: ${SERVERS[*]}"
}

# resolve_servers <name|all> → prints one server per line
resolve_servers() {
    if [ "$1" = "all" ]; then
        printf '%s\n' "${SERVERS[@]}"
    else
        validate_server "$1"
        echo "$1"
    fi
}

# ── Platform detection ───────────────────────────────────────────────────────

detect_platform() {
    local kernel arch
    kernel="$(uname -s)"
    arch="$(uname -m)"

    case "$kernel" in
        Darwin)                H39_OS="macos" ;;
        Linux)                 H39_OS="linux" ;;
        MINGW*|MSYS*|CYGWIN*) H39_OS="windows" ;;
        *)                     die "Unsupported OS: $kernel" ;;
    esac

    case "$arch" in
        arm64|aarch64) H39_ARCH="arm64" ;;
        x86_64|amd64)  H39_ARCH="x64" ;;
        *)             die "Unsupported arch: $arch" ;;
    esac
}

# ── JSON helpers ─────────────────────────────────────────────────────────────

json_tool_init() {
    command -v python3 &>/dev/null || die "python3 not found. Install python3 to continue."
}

# json_set_key <file> <dotpath> <key> <value_json>
json_set_key() {
    local file="$1" dotpath="$2" key="$3" value="$4"
    [ -f "$file" ] || echo '{}' > "$file"

    python3 -c "
import json, sys, os
file, dotpath, key, val_str = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
parts = [p for p in dotpath.lstrip('.').split('.') if p]
value = json.loads(val_str)
try:
    with open(file) as f: data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
node = data
for p in parts:
    node.setdefault(p, {})
    node = node[p]
node[key] = value
tmp = file + '.h39tmp'
with open(tmp, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.replace(tmp, file)
" "$file" "$dotpath" "$key" "$value"
}

# json_delete_key <file> <dotpath> <key>
json_delete_key() {
    local file="$1" dotpath="$2" key="$3"
    [ -f "$file" ] || return 0

    python3 -c "
import json, sys, os
file, dotpath, key = sys.argv[1], sys.argv[2], sys.argv[3]
parts = [p for p in dotpath.lstrip('.').split('.') if p]
try:
    with open(file) as f: data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    sys.exit(0)
node = data
for p in parts:
    if p not in node: sys.exit(0)
    node = node[p]
node.pop(key, None)
tmp = file + '.h39tmp'
with open(tmp, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.replace(tmp, file)
" "$file" "$dotpath" "$key"
}

# json_read_keys <file> <dotpath> → prints one key per line
json_read_keys() {
    local file="$1" dotpath="$2"
    [ -f "$file" ] || return 0

    python3 -c "
import json, sys
file, dotpath = sys.argv[1], sys.argv[2]
parts = [p for p in dotpath.lstrip('.').split('.') if p]
try:
    with open(file) as f: data = json.load(f)
except: sys.exit(0)
node = data
for p in parts:
    if p not in node: sys.exit(0)
    node = node[p]
if isinstance(node, dict):
    for k in sorted(node.keys()): print(k)
" "$file" "$dotpath" 2>/dev/null || true
}

# ── TOML helpers (for Codex config.toml) ─────────────────────────────────────

# toml_delete_server <file> <name> - remove [mcp_servers.<name>] and subsections
toml_delete_server() {
    local file="$1" name="$2"
    [ -f "$file" ] || return 0
    python3 -c "
import sys, os

file_path, name = sys.argv[1], sys.argv[2]
header_exact = '[mcp_servers.' + name + ']'
header_sub   = '[mcp_servers.' + name + '.'

with open(file_path) as f:
    lines = f.readlines()

result, skip = [], False
for line in lines:
    stripped = line.strip()
    if stripped.startswith('[') and not stripped.startswith('[['):
        skip = (stripped == header_exact or stripped.startswith(header_sub))
    if not skip:
        result.append(line)

tmp = file_path + '.h39tmp'
with open(tmp, 'w') as f:
    f.writelines(result)
os.replace(tmp, file_path)
" "$file" "$name"
}

# toml_set_server <file> <name> <command> <args_json> [env_json]
toml_set_server() {
    local file="$1" name="$2" cmd="$3" args_json="$4"
    local env_json='{}'
    [ $# -ge 5 ] && env_json="$5"

    # Remove existing entry, then append new one
    toml_delete_server "$file" "$name"

    python3 -c "
import sys, json, os

file_path, name, cmd, args_str, env_str = sys.argv[1:6]
args = json.loads(args_str)
env = json.loads(env_str)

try:
    with open(file_path) as f:
        content = f.read()
except FileNotFoundError:
    content = ''

content = content.rstrip('\n')
if content:
    content += '\n'

section = '\n[mcp_servers.' + name + ']\n'
section += 'command = ' + json.dumps(cmd) + '\n'
if args:
    section += 'args = ' + json.dumps(args) + '\n'
if env:
    section += '\n[mcp_servers.' + name + '.env]\n'
    for k, v in env.items():
        section += k + ' = ' + json.dumps(v) + '\n'

content += section

os.makedirs(os.path.dirname(file_path) or '.', exist_ok=True)
tmp = file_path + '.h39tmp'
with open(tmp, 'w') as f:
    f.write(content)
os.replace(tmp, file_path)
" "$file" "$name" "$cmd" "$args_json" "$env_json"
}

# toml_read_servers <file> → prints one server name per line
toml_read_servers() {
    local file="$1"
    [ -f "$file" ] || return 0
    python3 -c "
import sys, re
try:
    with open(sys.argv[1]) as f:
        content = f.read()
except FileNotFoundError:
    sys.exit(0)
names = set()
for m in re.finditer(r'\[mcp_servers\.([^.\]]+)\]', content):
    names.add(m.group(1))
for name in sorted(names):
    print(name)
" "$file"
}

# ── Target helpers ───────────────────────────────────────────────────────────

target_config_path() {
    case "$1" in
        claude-cli)
            echo "${HOME}/.claude.json"
            ;;
        claude-desktop)
            case "$H39_OS" in
                macos)   echo "${HOME}/Library/Application Support/Claude/claude_desktop_config.json" ;;
                linux)   echo "${HOME}/.config/Claude/claude_desktop_config.json" ;;
                windows) echo "${APPDATA:-}/Claude/claude_desktop_config.json" ;;
            esac
            ;;
        opencode)
            echo "${HOME}/.config/opencode/opencode.json"
            ;;
        codex)
            echo "${HOME}/.codex/config.toml"
            ;;
        openclaw)
            echo "${HOME}/.openclaw/openclaw.json"
            ;;
    esac
}

target_json_path() {
    case "$1" in
        claude-cli|claude-desktop) echo ".mcpServers" ;;
        opencode)                  echo ".mcp" ;;
        openclaw)                  echo ".mcp.servers" ;;
        codex)                     die "Bug: target_json_path called for codex (uses TOML)" ;;
    esac
}

target_exists() {
    local path
    path="$(target_config_path "$1")"
    local dir
    dir="$(dirname "$path")"
    [ -d "$dir" ] || [ -f "$path" ]
}

resolve_targets() {
    local requested="$1"
    if [ "$requested" != "all" ]; then
        echo "$requested"
        return
    fi
    local t
    for t in claude-cli claude-desktop opencode codex openclaw; do
        if target_exists "$t"; then
            echo "$t"
        fi
    done
}

# ── Config dispatchers ──────────────────────────────────────────────────────
# Abstracts codex (TOML) vs everything else (JSON) so call sites don't branch.

# config_set <target> <file> <server> <bin_path> [env_json]
config_set() {
    local target="$1" file="$2" server="$3" bin_path="$4" env_json="${5:-}"

    if [ "$target" = "codex" ]; then
        local args_val
        args_val="$(server_args "$server")"
        if [ -n "$args_val" ]; then
            args_val="[\"$args_val\"]"
        else
            args_val="[]"
        fi
        toml_set_server "$file" "$server" "$bin_path" "$args_val" "$env_json"
    else
        local jpath entry
        jpath="$(target_json_path "$target")"
        entry="$(build_mcp_entry "$server" "$target" "$bin_path" "$env_json")"
        json_set_key "$file" "$jpath" "$server" "$entry"
    fi
}

# config_delete <target> <file> <server>
config_delete() {
    local target="$1" file="$2" server="$3"

    if [ "$target" = "codex" ]; then
        toml_delete_server "$file" "$server"
    else
        local jpath
        jpath="$(target_json_path "$target")"
        json_delete_key "$file" "$jpath" "$server"
    fi
}

# config_read_keys <target> <file> → prints one key per line
config_read_keys() {
    local target="$1" file="$2"

    if [ "$target" = "codex" ]; then
        toml_read_servers "$file"
    else
        local jpath
        jpath="$(target_json_path "$target")"
        json_read_keys "$file" "$jpath"
    fi
}

# ── Config builder (JSON targets only) ──────────────────────────────────────

# build_mcp_entry <server> <target> <bin_path> [env_json]
build_mcp_entry() {
    local server="$1" target="$2" bin_path="$3" env_json="${4:-}"
    local args
    args="$(server_args "$server")"

    if [ "$target" = "opencode" ] && [ -n "$env_json" ] && [ "$env_json" != "{}" ]; then
        warn "OpenCode does not support env vars in MCP config - skipping env for $server"
        env_json="{}"
    fi

    python3 -c "
import json, sys
target, cmd, args_str, env_str = sys.argv[1:5]
args = [args_str] if args_str else []
env = json.loads(env_str) if env_str else {}

if target == 'claude-cli':
    entry = {'type': 'stdio', 'command': cmd, 'args': args}
elif target in ('claude-desktop', 'openclaw'):
    entry = {'command': cmd, 'args': args}
elif target == 'opencode':
    entry = {'type': 'local', 'command': ([cmd, args_str] if args_str else [cmd])}
else:
    sys.exit('unknown target: ' + target)

if env and target != 'opencode':
    entry['env'] = env

print(json.dumps(entry))
" "$target" "$bin_path" "$args" "$env_json"
}

# ── Download ─────────────────────────────────────────────────────────────────

bin_path() {
    local name="$1"
    if [ "$H39_OS" = "windows" ]; then
        echo "${INSTALL_DIR}/${name}.exe"
    else
        echo "${INSTALL_DIR}/${name}"
    fi
}

download_binary() {
    local server="$1"

    if [ "$H39_OS" = "windows" ] && ! server_has_windows "$server"; then
        warn "$server has no Windows build - skipping download"
        return 1
    fi

    mkdir -p "$INSTALL_DIR"

    if server_is_zipped "$server"; then
        local asset="${server}-${H39_OS}-${H39_ARCH}.zip"
        local url="https://github.com/${GITHUB_ORG}/${server}/releases/latest/download/${asset}"
        local tmpzip="${INSTALL_DIR}/.${server}.dl.zip"

        info "Downloading ${server} (${H39_OS}-${H39_ARCH})..."
        if ! curl -fSL --progress-bar -o "$tmpzip" "$url"; then
            rm -f "$tmpzip"
            die "Download failed: $url"
        fi

        info "Extracting ${asset}..."
        if ! python3 -m zipfile -e "$tmpzip" "$INSTALL_DIR"; then
            rm -f "$tmpzip"
            die "Failed to extract $tmpzip"
        fi
        rm -f "$tmpzip"

        # chmod +x on main binary and all sidecars (Python's zipfile strips mode bits)
        local main_bp
        main_bp="$(bin_path "$server")"
        [ -f "$main_bp" ] && chmod +x "$main_bp"

        local sc
        while IFS= read -r sc; do
            [ -z "$sc" ] && continue
            local sc_path
            sc_path="$(bin_path "$sc")"
            [ -f "$sc_path" ] && chmod +x "$sc_path"
        done < <(server_sidecars "$server")

        ok "Installed ${server} + sidecars to $INSTALL_DIR"
        return 0
    fi

    local asset="${server}-${H39_OS}-${H39_ARCH}"
    [ "$H39_OS" = "windows" ] && asset="${asset}.exe"

    local url="https://github.com/${GITHUB_ORG}/${server}/releases/latest/download/${asset}"
    local dest
    dest="$(bin_path "$server")"

    info "Downloading ${server} (${H39_OS}-${H39_ARCH})..."
    if ! curl -fSL --progress-bar -o "${dest}.dl" "$url"; then
        rm -f "${dest}.dl"
        die "Download failed: $url"
    fi

    mv "${dest}.dl" "$dest"
    chmod +x "$dest"
    ok "Installed binary: $dest"
}

# ── Backup ───────────────────────────────────────────────────────────────────

backup_config() {
    local file="$1"
    [ -f "$file" ] || return 0
    local bak="${file}.h39bak.$(date +%Y%m%d%H%M%S)"
    cp "$file" "$bak"
    info "Backed up: $bak"
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_install() {
    local server="" target="all" env_pairs=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --target) target="$2"; shift 2 ;;
            --env)    env_pairs+=("$2"); shift 2 ;;
            -*)       die "Unknown flag: $1" ;;
            *)        [ -z "$server" ] && server="$1" || die "Unexpected arg: $1"; shift ;;
        esac
    done
    [ -n "$server" ] || die "Usage: h39 install <tool|all> [--target T] [--env K=V]"

    # Build env JSON from --env pairs
    local env_json="{}"
    if [ ${#env_pairs[@]} -gt 0 ]; then
        env_json=$(python3 -c "
import json, sys
pairs = sys.argv[1:]
d = {}
for p in pairs:
    k, v = p.split('=', 1)
    d[k] = v
print(json.dumps(d))
" "${env_pairs[@]}")
    fi

    local servers
    servers="$(resolve_servers "$server")"

    while IFS= read -r srv; do
        echo ""
        info "── $srv ──"

        if ! download_binary "$srv"; then
            continue
        fi

        local bp
        bp="$(bin_path "$srv")"

        local targets
        targets="$(resolve_targets "$target")"
        if [ -z "$targets" ]; then
            warn "No MCP clients detected. Binary installed but no config updated."
            continue
        fi

        while IFS= read -r t; do
            local cfg
            cfg="$(target_config_path "$t")"
            backup_config "$cfg"
            config_set "$t" "$cfg" "$srv" "$bp" "$env_json"
            ok "Configured $srv in $t ($cfg)"
        done <<< "$targets"
    done <<< "$servers"

    echo ""
    ok "Done."
}

cmd_uninstall() {
    local server="" target="all" purge=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --target) target="$2"; shift 2 ;;
            --purge)  purge=true; shift ;;
            -*)       die "Unknown flag: $1" ;;
            *)        [ -z "$server" ] && server="$1" || die "Unexpected arg: $1"; shift ;;
        esac
    done
    [ -n "$server" ] || die "Usage: h39 uninstall <tool|all> [--target T] [--purge]"

    local servers
    servers="$(resolve_servers "$server")"

    while IFS= read -r srv; do
        echo ""
        info "── $srv ──"

        local targets
        targets="$(resolve_targets "$target")"
        while IFS= read -r t; do
            [ -z "$t" ] && continue
            local cfg
            cfg="$(target_config_path "$t")"

            if [ -f "$cfg" ]; then
                backup_config "$cfg"
                config_delete "$t" "$cfg" "$srv"
                ok "Removed $srv from $t ($cfg)"
            fi
        done <<< "$targets"

        if $purge; then
            local bp
            bp="$(bin_path "$srv")"
            if [ -f "$bp" ]; then
                rm "$bp"
                ok "Deleted binary: $bp"
            fi
            local sc
            while IFS= read -r sc; do
                [ -z "$sc" ] && continue
                local sc_path
                sc_path="$(bin_path "$sc")"
                if [ -f "$sc_path" ]; then
                    rm "$sc_path"
                    ok "Deleted sidecar: $sc_path"
                fi
            done < <(server_sidecars "$srv")
        fi
    done <<< "$servers"

    echo ""
    ok "Done."
}

cmd_update() {
    local server="${1:-}"
    [ -n "$server" ] || die "Usage: h39 update <tool|all>"

    local servers
    servers="$(resolve_servers "$server")"

    while IFS= read -r srv; do
        echo ""
        download_binary "$srv" || true
    done <<< "$servers"

    echo ""
    ok "Done."
}

cmd_list() {
    local all_targets=(claude-cli claude-desktop opencode codex openclaw)

    echo ""
    printf "%-18s %s\n" "TARGET" "MCP TOOLS"
    printf "%-18s %s\n" "──────" "─────────"

    for t in "${all_targets[@]}"; do
        local cfg
        cfg="$(target_config_path "$t")"
        if [ ! -f "$cfg" ]; then
            printf "%-18s %s\n" "$t" "(not installed)"
            continue
        fi

        local keys
        keys="$(config_read_keys "$t" "$cfg")"

        if [ -z "$keys" ]; then
            printf "%-18s %s\n" "$t" "(none)"
        else
            printf "%-18s %s\n" "$t" "$(echo "$keys" | tr '\n' ', ' | sed 's/,$//')"
        fi
    done

    echo ""
    printf "%-18s %s\n" "BINARY" "STATUS"
    printf "%-18s %s\n" "──────" "──────"

    local srv
    for srv in "${SERVERS[@]}"; do
        local bp
        bp="$(bin_path "$srv")"
        if [ -f "$bp" ]; then
            local size
            if [ "$H39_OS" = "macos" ]; then
                size=$(stat -f%z "$bp" 2>/dev/null || echo "?")
            else
                size=$(stat -c%s "$bp" 2>/dev/null || echo "?")
            fi
            if [ "$size" != "?" ]; then
                if [ "$size" -ge 1048576 ]; then
                    size="$((size / 1048576))M"
                elif [ "$size" -ge 1024 ]; then
                    size="$((size / 1024))K"
                else
                    size="${size}B"
                fi
            fi
            printf "%-18s %s (%s)\n" "$srv" "$bp" "$size"
        else
            printf "%-18s %s\n" "$srv" "(not found)"
        fi
    done
    echo ""
}

cmd_menu() {
    local ALL_TARGETS="claude-cli claude-desktop opencode codex openclaw"
    local PICKED_SERVER="" PICKED_TARGET=""

    # ── State: parallel arrays (bash 3.2 compat) ──
    local bin_installed_0=0 bin_installed_1=0 bin_installed_2=0 bin_installed_3=0 bin_installed_4=0 bin_installed_5=0
    local cfg_claude_cli="" cfg_claude_desktop="" cfg_opencode="" cfg_codex="" cfg_openclaw=""

    refresh_state() {
        local bp i=0
        for srv in "${SERVERS[@]}"; do
            bp="$(bin_path "$srv")"
            if [ -f "$bp" ]; then
                eval "bin_installed_${i}=1"
            else
                eval "bin_installed_${i}=0"
            fi
            i=$((i+1))
        done
        local t cfg _keys
        for t in $ALL_TARGETS; do
            cfg="$(target_config_path "$t")"
            _keys=""
            if [ -f "$cfg" ]; then
                _keys="$(config_read_keys "$t" "$cfg" | tr '\n' ' ')"
            fi
            eval "cfg_$(echo "$t" | tr '-' '_')=\"\$_keys\""
        done
    }

    get_bin_installed() {
        eval "echo \$bin_installed_$1"
    }

    get_cfg_keys() {
        local var="cfg_$(echo "$1" | tr '-' '_')"
        eval "echo \$$var"
    }

    is_configured() {
        local srv="$1" t="$2" keys
        keys=" $(get_cfg_keys "$t") "
        case "$keys" in
            *" $srv "*) return 0 ;;
            *)          return 1 ;;
        esac
    }

    server_index() {
        local i=0
        for s in "${SERVERS[@]}"; do
            [ "$s" = "$1" ] && echo "$i" && return
            i=$((i+1))
        done
    }

    server_status() {
        local srv="$1" idx
        idx=$(server_index "$srv")
        local bin_ok
        bin_ok=$(get_bin_installed "$idx")
        local cfg_count=0 t
        for t in $ALL_TARGETS; do
            is_configured "$srv" "$t" && cfg_count=$((cfg_count+1))
        done
        if [ "$bin_ok" = "1" ] && [ "$cfg_count" -gt 0 ]; then
            printf '\033[1;32m●\033[0m'
        elif [ "$bin_ok" = "1" ] || [ "$cfg_count" -gt 0 ]; then
            printf '\033[1;33m◐\033[0m'
        else
            printf '\033[1;30m○\033[0m'
        fi
    }

    target_line() {
        local t="$1" cfg
        cfg="$(target_config_path "$t")"
        if [ ! -f "$cfg" ]; then
            printf '\033[1;30m  (not detected)\033[0m'
            return
        fi
        local srvs="" srv
        for srv in "${SERVERS[@]}"; do
            if is_configured "$srv" "$t"; then
                [ -n "$srvs" ] && srvs="$srvs, "
                srvs="$srvs$srv"
            fi
        done
        if [ -z "$srvs" ]; then
            printf '\033[1;30m  (none)\033[0m'
        else
            printf '  %s' "$srvs"
        fi
    }

    local SERVER_DESCS_0="Headless web browser"
    local SERVER_DESCS_1="Temporal-priority memory"
    local SERVER_DESCS_2="Headless terminal emulator"
    local SERVER_DESCS_3="Token-optimized repo explorer"
    local SERVER_DESCS_4="Privilege-elevation server"
    local SERVER_DESCS_5="Z3-powered SMT reasoning"

    draw_menu() {
        printf '\033[2J\033[H'
        echo ""
        printf '  \033[1;36mHarness39\033[0m - MCP Tool Manager\n'
        printf '  \033[38;5;240mby Alejandro Quintanar - github.com/alejandroqh\033[0m\n'
        printf '  \033[38;5;240m%s  %s\033[0m\n' "$H39_OS" "$H39_ARCH"
        echo ""
        printf '  \033[1mMCP Tools\033[0m\n'
        local i=0 srv desc
        for srv in "${SERVERS[@]}"; do
            eval "desc=\$SERVER_DESCS_${i}"
            printf '    %s  \033[1m%-12s\033[0m \033[38;5;240m%s\033[0m\n' \
                "$(server_status "$srv")" "$srv" "$desc"
            i=$((i+1))
        done
        echo ""
        printf '  \033[1mTargets\033[0m\n'
        local t
        for t in $ALL_TARGETS; do
            printf '    %-18s%s\n' "$t" "$(target_line "$t")"
        done
        echo ""
        printf '  \033[38;5;240m● installed  ◐ partial  ○ not installed\033[0m\n'
        echo ""
        printf '  \033[1mActions\033[0m\n'
        printf '    \033[1;32m1\033[0m  Install MCP tool       \033[1;33m4\033[0m  Update MCP tool\n'
        printf '    \033[1;31m2\033[0m  Uninstall MCP tool     \033[1;36m5\033[0m  Install all\n'
        printf '    \033[1;34m3\033[0m  Show status (list)     \033[1;35m6\033[0m  Uninstall all\n'
        echo ""
        printf '    \033[38;5;240mq  Quit\033[0m\n'
        echo ""
    }

    pick_server() {
        local prompt_msg="${1:-Pick an MCP tool}"
        echo ""
        local i=0 srv
        for srv in "${SERVERS[@]}"; do
            printf '    \033[1m%d\033[0m  %s %s\n' "$((i+1))" "$(server_status "$srv")" "$srv"
            i=$((i+1))
        done
        echo ""
        printf '  %s [1-%d]: ' "$prompt_msg" "${#SERVERS[@]}"
        local choice
        read -r choice <&3
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#SERVERS[@]}" ]; then
            PICKED_SERVER="${SERVERS[$((choice-1))]}"
            return 0
        fi
        warn "Invalid choice"
        return 1
    }

    pick_target() {
        echo ""
        local i=1 t
        for t in $ALL_TARGETS; do
            printf '    \033[1m%d\033[0m  %s\n' "$i" "$t"
            i=$((i+1))
        done
        local all_num=$i
        printf '    \033[1m%d\033[0m  all (detected)\n' "$all_num"
        echo ""
        printf '  Target [1-%d, default=%d]: ' "$all_num" "$all_num"
        local choice
        read -r choice <&3
        choice="${choice:-$all_num}"

        if [ "$choice" = "$all_num" ]; then
            PICKED_TARGET="all"
            return 0
        fi

        local j=1
        for t in $ALL_TARGETS; do
            if [ "$j" = "$choice" ]; then
                PICKED_TARGET="$t"
                return 0
            fi
            j=$((j+1))
        done
        warn "Invalid choice"
        return 1
    }

    menu_pause() {
        echo ""
        printf '  \033[38;5;240mPress Enter to continue...\033[0m'
        read -r <&3
    }

    # ── Open TTY for interactive reads (needed for curl | bash) ──
    exec 3< /dev/tty || die "No terminal available for interactive menu"
    trap 'exec 3<&-' RETURN

    # ── Main loop ──
    while true; do
        refresh_state
        draw_menu
        printf '  Action: '
        local action
        read -r action <&3

        case "$action" in
            1)
                if pick_server "Install which MCP tool?" && pick_target; then
                    echo ""
                    cmd_install "$PICKED_SERVER" --target "$PICKED_TARGET"
                    menu_pause
                fi
                ;;
            2)
                if pick_server "Uninstall which MCP tool?" && pick_target; then
                    echo ""
                    printf '  Also remove binary? [y/N]: '
                    local purge_choice
                    read -r purge_choice <&3
                    case "$purge_choice" in
                        [Yy]) cmd_uninstall "$PICKED_SERVER" --target "$PICKED_TARGET" --purge ;;
                        *)    cmd_uninstall "$PICKED_SERVER" --target "$PICKED_TARGET" ;;
                    esac
                    menu_pause
                fi
                ;;
            3)
                echo ""
                cmd_list
                menu_pause
                ;;
            4)
                if pick_server "Update which MCP tool?"; then
                    echo ""
                    cmd_update "$PICKED_SERVER"
                    menu_pause
                fi
                ;;
            5)
                if pick_target; then
                    echo ""
                    cmd_install all --target "$PICKED_TARGET"
                    menu_pause
                fi
                ;;
            6)
                if pick_target; then
                    echo ""
                    printf '  Also remove binaries? [y/N]: '
                    local purge_all
                    read -r purge_all <&3
                    case "$purge_all" in
                        [Yy]) cmd_uninstall all --target "$PICKED_TARGET" --purge ;;
                        *)    cmd_uninstall all --target "$PICKED_TARGET" ;;
                    esac
                    menu_pause
                fi
                ;;
            q|Q|"")
                echo ""
                return 0
                ;;
            *)
                warn "Unknown action: $action"
                menu_pause
                ;;
        esac
    done
}

cmd_help() {
    cat >&2 <<'EOF'

  Harness39 - MCP tool installer
  Author: Alejandro Quintanar  <https://github.com/alejandroqh>
  License: MIT - Provided "AS IS", without warranty of any kind.

  Usage:
    h39                                    Interactive menu
    h39 install <tool|all>   [--target T] [--env K=V ...]
    h39 uninstall <tool|all> [--target T] [--purge]
    h39 update <tool|all>
    h39 list
    h39 help

  MCP Tools:
    browser39    Headless web browser for AI agents
    memory39     Temporal-priority memory system for AI agents
    npcterm      Headless terminal emulator for AI agents
    repo39       Token-optimized repo explorer for AI agents
    sudo39       Privilege-elevation for AI agents
    z39          Z3-powered SMT reasoning for AI agents

  Targets:
    claude-cli       Claude Code CLI (~/.claude.json)
    claude-desktop   Claude Desktop app
    opencode         OpenCode (~/.config/opencode/opencode.json)
    codex            OpenAI Codex CLI (~/.codex/config.toml)
    openclaw         OpenClaw (~/.openclaw/openclaw.json)
    all              All detected clients (default)

  Options:
    --target T       Target MCP client (default: all)
    --env K=V        Set environment variable in MCP config (repeatable)
    --purge          Also remove binary on uninstall

  Examples:
    h39 install browser39
    h39 install all --target claude-cli
    h39 install sudo39 --env SUDO39_ALLOWED_PROGRAMS=id,whoami
    h39 uninstall repo39 --purge
    h39 update all
    h39 list

  Install directory: ~/.local/bin (override: H39_INSTALL_DIR)
  Binaries downloaded from: github.com/alejandroqh/<tool>/releases

EOF
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    detect_platform
    json_tool_init

    local cmd="${1:-menu}"
    shift || true

    case "$cmd" in
        menu)      cmd_menu ;;
        install)   cmd_install "$@" ;;
        uninstall) cmd_uninstall "$@" ;;
        update)    cmd_update "$@" ;;
        list)      cmd_list "$@" ;;
        help|-h|--help) cmd_help ;;
        *)         die "Unknown command: $cmd. Run 'h39 help' for usage." ;;
    esac
}

main "$@"
