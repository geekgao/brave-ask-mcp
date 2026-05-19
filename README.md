# brave-ask-mcp

[Brave Search](https://search.brave.com) 的 MCP 服务器，提供 `brave_ask_markdown` 工具，用于获取 Brave Ask AI 的搜索结果并返回干净的 Markdown 内容。而且不需要 API Key。

## 快速安装

```bash
curl -fsSL https://raw.githubusercontent.com/geekgao/brave-ask-mcp/main/install.sh | bash
```

脚本会自动：

1. 检测操作系统和架构，下载对应预编译二进制
2. 安装到 `$HOME/.local/bin/bravegrab`
3. 自动配置 opencode MCP 配置（`~/.config/opencode/opencode.json`）

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `INSTALL_DIR` | `~/.local/bin` | 二进制安装目录 |
| `OPENCODE_CONFIG` | `~/.config/opencode/opencode.json` | opencode 配置文件路径 |
| `PROXY_LIST` | `http://127.0.0.1:8080,socks5://127.0.0.1:1080` | 代理列表（逗号/空格/分号分隔） |

## 手动编译

```bash
git clone https://github.com/geekgao/brave-ask-mcp.git
cd brave-ask-mcp
go build -o bravegrab .
```

将生成的 `bravegrab` 放到 `PATH` 中。

## MCP 配置

### opencode

添加到 `~/.config/opencode/opencode.json`：

```json
{
  "mcp": {
    "brave_ask": {
      "type": "local",
      "command": ["bravegrab"],
      "enabled": true
    }
  }
}
```

### 其他 MCP 客户端

```json
{
  "mcpServers": {
    "brave_ask": {
      "command": "bravegrab"
    }
  }
}
```

## 工具

### `brave_ask_markdown`

使用 headless 浏览器获取 Brave Ask AI 搜索结果，去除用户消息、增强信息、页脚等干扰元素，返回 Markdown 格式。

**参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `keyword` | string | 是 | 搜索关键词 |
| `proxy` | string | 否 | 代理 URL 或 `PROXY_LIST` 中的索引（如 `0`、`1`） |
| `html` | bool | 否 | 设为 `true` 时返回原始 HTML 而非 Markdown |

**使用示例（opencode）：**

```
brave_ask_markdown keyword=Go语言泛型教程
brave_ask_markdown keyword=golang context proxy=0 html=true
```


## 系统要求

- 运行时需要能够启动 headless Chromium（go-rod 会自动下载，首次启动较慢）
- 支持平台：
  - Linux amd64
  - macOS (universal, Intel/Apple Silicon)
  - Windows amd64

## License

[MIT](LICENSE)
