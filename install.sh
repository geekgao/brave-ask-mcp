#!/usr/bin/env bash
set -euo pipefail

REPO="geekgao/brave-ask-mcp"
BIN_NAME="bravegrab"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
BIN_PATH="$INSTALL_DIR/$BIN_NAME"

# ============================================================
# Config file paths (overridable via env vars)
# ============================================================
OPENCODE_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"

case "$(uname -s)" in
  Darwin*)  _claude_default="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
  Linux*)   _claude_default="$HOME/.config/claude-desktop/claude_desktop_config.json" ;;
  MINGW*|MSYS*|CYGWIN*) _claude_default="$APPDATA/Claude/claude_desktop_config.json" ;;
  *)        _claude_default="" ;;
esac
CLAUDE_CONFIG="${CLAUDE_CONFIG:-$_claude_default}"

CURSOR_GLOBAL_CONFIG="${CURSOR_GLOBAL_CONFIG:-$HOME/.cursor/mcp.json}"
CONTINUE_CONFIG="${CONTINUE_CONFIG:-$HOME/.continue/config.json}"
ZED_CONFIG="${ZED_CONFIG:-$HOME/.config/zed/settings.json}"

# ============================================================
# Which tools to configure (env var flags)
# ============================================================
CONFIGURE_OPENCODE="${CONFIGURE_OPENCODE:-true}"
CONFIGURE_CLAUDE="${CONFIGURE_CLAUDE:-${CONFIGURE_ALL:-false}}"
CONFIGURE_CURSOR="${CONFIGURE_CURSOR:-${CONFIGURE_ALL:-false}}"
CONFIGURE_CONTINUE="${CONFIGURE_CONTINUE:-${CONFIGURE_ALL:-false}}"
CONFIGURE_ZED="${CONFIGURE_ZED:-${CONFIGURE_ALL:-false}}"

MUTED='\033[0;2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[38;5;214m'
NC='\033[0m'

# ============================================================
# Platform detection
# ============================================================
detect_platform() {
  local raw_os arch

  raw_os=$(uname -s)
  case "$raw_os" in
    Darwin*) os="darwin" ;;
    Linux*)  os="linux" ;;
    MINGW*|MSYS*|CYGWIN*) os="windows" ;;
    *) echo -e "${RED}Unsupported OS: $raw_os${NC}"; exit 1 ;;
  esac

  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo -e "${RED}Unsupported arch: $arch${NC}"; exit 1 ;;
  esac

  if [ "$os" = "darwin" ]; then
    asset="bravegrab-darwin-universal"
  elif [ "$os" = "linux" ] && [ "$arch" = "amd64" ]; then
    asset="bravegrab-linux-amd64"
  elif [ "$os" = "windows" ] && [ "$arch" = "amd64" ]; then
    asset="bravegrab-windows-amd64.exe"
  else
    echo -e "${RED}No pre-built binary for $os/$arch${NC}"
    echo -e "${MUTED}Supported: linux/amd64, darwin/universal, windows/amd64${NC}"
    exit 1
  fi

  echo "$os/$arch -> $asset" >&2
  echo "$asset"
}

# ============================================================
# Binary download
# ============================================================
download_release() {
  local asset="$1"
  local version="${VERSION:-latest}"

  if [ "$version" = "latest" ]; then
    url="https://github.com/$REPO/releases/latest/download/$asset"
  else
    url="https://github.com/$REPO/releases/download/v${version}/$asset"
  fi

  echo -e "${MUTED}Downloading $url${NC}" >&2

  tmpdir=$(mktemp -d)
  curl -fsSL -o "$tmpdir/$asset" "$url"
  chmod +x "$tmpdir/$asset"
  echo "$tmpdir/$asset"
}

# ============================================================
# Binary installation
# ============================================================
install_binary() {
  local src="$1"

  mkdir -p "$INSTALL_DIR"
  mv "$src" "$BIN_PATH"
  echo -e "${GREEN}Installed $BIN_NAME to $BIN_PATH${NC}"

  if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo -e "${MUTED}Warning: $INSTALL_DIR is not in PATH${NC}"
    echo -e "${MUTED}  export PATH=\"$INSTALL_DIR:\$PATH\"${NC}"
  fi
}

# ============================================================
# JSON editing helpers
# ============================================================
ensure_file() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  if [ ! -f "$file" ]; then
    echo '{}' > "$file"
  fi
}

# Set a key in a JSON object using jq/python3/node
# Usage: json_set FILE EXPRESSION
#   EXPRESSION is a jq expression using $val for the value
#   The value is passed as the third argument (JSON string)
json_set_obj() {
  local file="$1"
  local expr="$2"
  local val="$3"

  ensure_file "$file"

  if command -v jq &>/dev/null; then
    tmp=$(mktemp)
    jq --argjson val "$val" "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
    return 0
  fi

  if command -v python3 &>/dev/null; then
    export _JS_FILE="$file" _JS_EXPR="$expr" _JS_VAL="$val"
    python3 -c '
import json, os, re
file = os.environ["_JS_FILE"]
val = json.loads(os.environ["_JS_VAL"])
expr = os.environ["_JS_EXPR"]
with open(file) as f:
    cfg = json.load(f)

# Parse simple jq-like assignment expressions
# .mcp.brave_ask = $val  ->  cfg["mcp"]["brave_ask"] = val
# .mcpServers.brave_ask = $val  ->  cfg["mcpServers"]["brave_ask"] = val
m = re.match(r"^\.(\S+)\s*=\s*\$val$", expr.strip())
if m:
    parts = m.group(1).split(".")
    target = cfg
    for p in parts[:-1]:
        target = target.setdefault(p, {})
    target[parts[-1]] = val

with open(file, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
'
    return 0
  fi

  if command -v node &>/dev/null; then
    export _JS_FILE="$file" _JS_EXPR="$expr" _JS_VAL="$val"
    node -e '
const fs = require("fs");
const file = process.env._JS_FILE;
const val = JSON.parse(process.env._JS_VAL);
const expr = process.env._JS_EXPR;
let cfg = JSON.parse(fs.readFileSync(file, "utf8"));

const m = expr.trim().match(/^\.(\S+)\s*=\s*\$val$/);
if (m) {
  const parts = m[1].split(".");
  let target = cfg;
  for (let i = 0; i < parts.length - 1; i++) {
    target[parts[i]] = target[parts[i]] || {};
    target = target[parts[i]];
  }
  target[parts[parts.length - 1]] = val;
}

fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");
'
    return 0
  fi

  return 1
}

# Add an item to a JSON array at a given key
# Usage: json_append FILE KEY VALUE
json_append_arr() {
  local file="$1"
  local key="$2"
  local val="$3"

  ensure_file "$file"

  if command -v jq &>/dev/null; then
    tmp=$(mktemp)
    jq --argjson val "$val" ".${key} += [\$val]" "$file" > "$tmp" && mv "$tmp" "$file"
    return 0
  fi

  if command -v python3 &>/dev/null; then
    export _JS_FILE="$file" _JS_KEY="$key" _JS_VAL="$val"
    python3 -c '
import json, os
file = os.environ["_JS_FILE"]
key = os.environ["_JS_KEY"]
val = json.loads(os.environ["_JS_VAL"])
with open(file) as f:
    cfg = json.load(f)
arr = cfg.setdefault(key, [])
existing = [i for i, x in enumerate(arr) if x.get("name") == val.get("name")]
if existing:
    arr[existing[0]] = val
else:
    arr.append(val)
with open(file, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
'
    return 0
  fi

  if command -v node &>/dev/null; then
    export _JS_FILE="$file" _JS_KEY="$key" _JS_VAL="$val"
    node -e '
const fs = require("fs");
const file = process.env._JS_FILE;
const key = process.env._JS_KEY;
const val = JSON.parse(process.env._JS_VAL);
let cfg = JSON.parse(fs.readFileSync(file, "utf8"));
cfg[key] = cfg[key] || [];
const idx = cfg[key].findIndex(x => x.name === val.name);
if (idx >= 0) cfg[key][idx] = val;
else cfg[key].push(val);
fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");
'
    return 0
  fi

  return 1
}

# ============================================================
# Per-tool configuration
# ============================================================
configure_opencode() {
  local entry
  entry=$(cat <<EOF
{
  "type": "local",
  "command": ["$BIN_PATH"],
  "enabled": true
}
EOF
)

  if [ -f "$OPENCODE_CONFIG" ] && grep -q '"brave_ask"' "$OPENCODE_CONFIG" 2>/dev/null; then
    echo -e "${MUTED}brave_ask MCP already configured in opencode${NC}"
    return
  fi

  if json_set_obj "$OPENCODE_CONFIG" ".mcp.brave_ask = \$val" "$entry"; then
    echo -e "${GREEN}Added brave_ask MCP to opencode ($OPENCODE_CONFIG)${NC}"
    echo -e "${MUTED}Restart opencode for the change to take effect${NC}"
  else
    echo -e "${ORANGE}Could not auto-configure opencode (jq/python3/node not found)${NC}"
    echo -e "${MUTED}Add this to $OPENCODE_CONFIG manually:${NC}"
    echo ""
    echo -e "  \"brave_ask\": $entry"
    echo ""
  fi
}

configure_claude_desktop() {
  if [ -z "$CLAUDE_CONFIG" ]; then
    echo -e "${MUTED}Claude Desktop config path not available for this platform${NC}"
    return
  fi

  local entry
  entry=$(cat <<EOF
{
  "command": "$BIN_PATH"
}
EOF
)

  if [ -f "$CLAUDE_CONFIG" ] && grep -q '"brave_ask"' "$CLAUDE_CONFIG" 2>/dev/null; then
    echo -e "${MUTED}brave_ask MCP already configured in Claude Desktop${NC}"
    return
  fi

  if json_set_obj "$CLAUDE_CONFIG" ".mcpServers.brave_ask = \$val" "$entry"; then
    echo -e "${GREEN}Added brave_ask MCP to Claude Desktop ($CLAUDE_CONFIG)${NC}"
    echo -e "${MUTED}Restart Claude Desktop for the change to take effect${NC}"
  else
    echo -e "${ORANGE}Could not auto-configure Claude Desktop (jq/python3/node not found)${NC}"
    echo -e "${MUTED}Add this to mcpServers in $CLAUDE_CONFIG:${NC}"
    echo ""
    echo -e "  \"brave_ask\": $entry"
    echo ""
  fi
}

configure_cursor() {
  local entry
  entry=$(cat <<EOF
{
  "command": "$BIN_PATH"
}
EOF
)

  # Global config
  if [ -f "$CURSOR_GLOBAL_CONFIG" ] && grep -q '"brave_ask"' "$CURSOR_GLOBAL_CONFIG" 2>/dev/null; then
    echo -e "${MUTED}brave_ask MCP already configured in Cursor (global)${NC}"
  else
    if json_set_obj "$CURSOR_GLOBAL_CONFIG" ".mcpServers.brave_ask = \$val" "$entry"; then
      echo -e "${GREEN}Added brave_ask MCP to Cursor (global: $CURSOR_GLOBAL_CONFIG)${NC}"
    else
      echo -e "${ORANGE}Could not auto-configure Cursor (jq/python3/node not found)${NC}"
    fi
  fi

  # Project-level config
  local cursor_local="${CURSOR_LOCAL_CONFIG:-$(pwd)/.cursor/mcp.json}"
  if [ -f "$cursor_local" ]; then
    if grep -q '"brave_ask"' "$cursor_local" 2>/dev/null; then
      echo -e "${MUTED}brave_ask MCP already configured in Cursor (project)${NC}"
    else
      if json_set_obj "$cursor_local" ".mcpServers.brave_ask = \$val" "$entry"; then
        echo -e "${GREEN}Added brave_ask MCP to Cursor (project: $cursor_local)${NC}"
      fi
    fi
  fi
}

configure_continue() {
  local entry
  entry=$(cat <<EOF
{
  "name": "brave_ask",
  "command": "$BIN_PATH"
}
EOF
)

  if [ -f "$CONTINUE_CONFIG" ]; then
    if grep -q '"brave_ask"' "$CONTINUE_CONFIG" 2>/dev/null; then
      echo -e "${MUTED}brave_ask MCP already configured in Continue.dev${NC}"
      return
    fi
  fi

  if json_append_arr "$CONTINUE_CONFIG" "mcpServers" "$entry"; then
    echo -e "${GREEN}Added brave_ask MCP to Continue.dev ($CONTINUE_CONFIG)${NC}"
  else
    echo -e "${ORANGE}Could not auto-configure Continue.dev (jq/python3/node not found)${NC}"
    echo -e "${MUTED}Add this to mcpServers array in $CONTINUE_CONFIG:${NC}"
    echo ""
    echo -e "  $entry"
    echo ""
  fi
}

configure_zed() {
  local entry
  entry=$(cat <<EOF
{
  "command": {
    "path": "$BIN_PATH",
    "args": []
  }
}
EOF
)

  if [ -f "$ZED_CONFIG" ] && grep -q '"brave_ask"' "$ZED_CONFIG" 2>/dev/null; then
    echo -e "${MUTED}brave_ask MCP already configured in Zed${NC}"
    return
  fi

  if json_set_obj "$ZED_CONFIG" ".context_servers.brave_ask = \$val" "$entry"; then
    echo -e "${GREEN}Added brave_ask MCP to Zed ($ZED_CONFIG)${NC}"
    echo -e "${MUTED}Restart Zed for the change to take effect${NC}"
  else
    echo -e "${ORANGE}Could not auto-configure Zed (jq/python3/node not found)${NC}"
    echo -e "${MUTED}Add this to context_servers in $ZED_CONFIG:${NC}"
    echo ""
    echo -e "  \"brave_ask\": $entry"
    echo ""
  fi
}

# ============================================================
# Main
# ============================================================
main() {
  echo -e "${MUTED}Installing brave-ask-mcp for MCP clients...${NC}"

  local asset
  asset=$(detect_platform)

  local bin_path
  bin_path=$(download_release "$asset")

  install_binary "$bin_path"

  echo ""
  echo -e "${MUTED}Configuring MCP clients...${NC}"

  [ "$CONFIGURE_OPENCODE" = "true" ] && configure_opencode
  [ "$CONFIGURE_CLAUDE" = "true" ] && configure_claude_desktop
  [ "$CONFIGURE_CURSOR" = "true" ] && configure_cursor
  [ "$CONFIGURE_CONTINUE" = "true" ] && configure_continue
  [ "$CONFIGURE_ZED" = "true" ] && configure_zed

  echo ""
  echo -e "${GREEN}Done! brave-ask-mcp is ready.${NC}"
  echo ""
  echo -e "${MUTED}To configure additional MCP clients, re-run with env vars:${NC}"
  echo -e "  CONFIGURE_ALL=true  # configure all supported tools"
  echo -e "  CONFIGURE_CLAUDE=true CONFIGURE_CURSOR=true ...  # specific tools"
  echo ""
  echo -e "${MUTED}Restart your MCP client, then use the tool: brave_ask_markdown${NC}"
}

main
