#!/usr/bin/env bash
set -euo pipefail

REPO="geekgao/brave-ask-mcp"
BIN_NAME="bravegrab"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"

MUTED='\033[0;2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[38;5;214m'
NC='\033[0m'

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

install_binary() {
  local src="$1"
  local dest="$INSTALL_DIR/$BIN_NAME"

  mkdir -p "$INSTALL_DIR"
  mv "$src" "$dest"
  echo -e "${GREEN}Installed $BIN_NAME to $dest${NC}"

  if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo -e "${MUTED}Warning: $INSTALL_DIR is not in PATH${NC}"
    echo -e "${MUTED}  export PATH=\"$INSTALL_DIR:\$PATH\"${NC}"
  fi
}

mcp_entry() {
  cat <<EOF
{
  "type": "local",
  "command": ["$INSTALL_DIR/$BIN_NAME"],
  "enabled": true
}
EOF
}

configure_opencode() {
  mkdir -p "$(dirname "$OPENCODE_CONFIG")"

  if [ -f "$OPENCODE_CONFIG" ] && grep -q '"brave_ask"' "$OPENCODE_CONFIG" 2>/dev/null; then
    echo -e "${MUTED}brave_ask MCP already configured in $OPENCODE_CONFIG${NC}"
    return
  fi

  local entry
  entry=$(mcp_entry)

  if [ ! -f "$OPENCODE_CONFIG" ]; then
    echo '{}' > "$OPENCODE_CONFIG"
  fi

  if command -v jq &>/dev/null; then
    tmp=$(mktemp)
    jq --argjson val "$entry" '.mcp.brave_ask = $val' "$OPENCODE_CONFIG" > "$tmp" && mv "$tmp" "$OPENCODE_CONFIG"

  elif command -v python3 &>/dev/null; then
    export _OC_CFG="$OPENCODE_CONFIG"
    export _OC_ENTRY="$entry"
    python3 -c '
import json, os
with open(os.environ["_OC_CFG"]) as f:
    cfg = json.load(f)
cfg.setdefault("mcp", {})["brave_ask"] = json.loads(os.environ["_OC_ENTRY"])
with open(os.environ["_OC_CFG"], "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
'

  elif command -v node &>/dev/null; then
    export _OC_CFG="$OPENCODE_CONFIG"
    export _OC_ENTRY="$entry"
    node -e '
const fs = require("fs");
const cfg = JSON.parse(fs.readFileSync(process.env._OC_CFG, "utf8"));
cfg.mcp = cfg.mcp || {};
cfg.mcp.brave_ask = JSON.parse(process.env._OC_ENTRY);
fs.writeFileSync(process.env._OC_CFG, JSON.stringify(cfg, null, 2) + "\n");
'

  else
    echo -e "${ORANGE}Could not auto-configure opencode (jq/python3/node not found)${NC}"
    echo -e "${MUTED}Add this to $OPENCODE_CONFIG manually:${NC}"
    echo ""
    echo -e "  \"brave_ask\": $entry"
    echo ""
    return
  fi

  echo -e "${GREEN}Added brave_ask MCP to $OPENCODE_CONFIG${NC}"
  echo -e "${MUTED}Restart opencode for the change to take effect${NC}"
}

main() {
  echo -e "${MUTED}Installing brave-ask-mcp for opencode...${NC}"

  local asset
  asset=$(detect_platform)

  local bin_path
  bin_path=$(download_release "$asset")

  install_binary "$bin_path"
  configure_opencode

  echo ""
  echo -e "${GREEN}Done! brave-ask-mcp is ready.${NC}"
  echo -e "${MUTED}Restart opencode, then use:${NC}"
  echo -e "  brave_ask_markdown"
}

main
