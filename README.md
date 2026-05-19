# brave-ask-mcp

[Brave Search](https://search.brave.com) 的 MCP 服务器，提供 `brave_ask_markdown` 工具，用于获取 Brave Ask AI 的搜索结果并返回干净的 Markdown 内容。而且不需要 API Key。

## 快速安装

```bash
curl -fsSL https://raw.githubusercontent.com/geekgao/brave-ask-mcp/main/install.sh | bash
```

脚本会自动：

1. 检测操作系统和架构，下载对应预编译二进制
2. 安装到 `$HOME/.local/bin/bravegrab`
3. 根据环境变量配置对应的 MCP 客户端（默认仅配置 opencode）

**一次性配置所有客户端：**

```bash
curl -fsSL https://raw.githubusercontent.com/geekgao/brave-ask-mcp/main/install.sh | CONFIGURE_ALL=true bash
```

**配置指定客户端：**

```bash
curl -fsSL https://raw.githubusercontent.com/geekgao/brave-ask-mcp/main/install.sh | CONFIGURE_CLAUDE=true CONFIGURE_CURSOR=true bash
```

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `INSTALL_DIR` | `~/.local/bin` | 二进制安装目录 |
| `CONFIGURE_ALL` | `false` | 设为 `true` 时自动配置所有支持的 MCP 客户端 |
| `CONFIGURE_OPENCODE` | `true` | 是否配置 opencode |
| `CONFIGURE_CLAUDE` | `false` | 是否配置 Claude Desktop（`CONFIGURE_ALL=true` 时自动启用） |
| `CONFIGURE_CURSOR` | `false` | 是否配置 Cursor |
| `CONFIGURE_CONTINUE` | `false` | 是否配置 Continue.dev |
| `CONFIGURE_ZED` | `false` | 是否配置 Zed |
| `OPENCODE_CONFIG` | `~/.config/opencode/opencode.json` | opencode 配置文件路径 |
| `CLAUDE_CONFIG` | 自动检测 | Claude Desktop 配置文件路径 |
| `CURSOR_GLOBAL_CONFIG` | `~/.cursor/mcp.json` | Cursor 全局配置文件路径 |
| `CURSOR_LOCAL_CONFIG` | `$(pwd)/.cursor/mcp.json` | Cursor 项目级配置文件路径 |
| `CONTINUE_CONFIG` | `~/.continue/config.json` | Continue.dev 配置文件路径 |
| `ZED_CONFIG` | `~/.config/zed/settings.json` | Zed 配置文件路径 |
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

### Claude Desktop

配置文件路径：

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`
- Linux: `~/.config/claude-desktop/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "brave_ask": {
      "command": "bravegrab"
    }
  }
}
```

> 修改配置后需要重启 Claude Desktop。

### Cursor

- 项目级配置：`.cursor/mcp.json`（项目根目录）
- 全局配置：`~/.cursor/mcp.json`

```json
{
  "mcpServers": {
    "brave_ask": {
      "command": "bravegrab"
    }
  }
}
```

> 支持热重载，修改后无需重启。

### Continue.dev

配置文件路径：`~/.continue/config.json`（或 `config.yaml`）

```json
{
  "mcpServers": [
    {
      "name": "brave_ask",
      "command": "bravegrab"
    }
  ]
}
```

> Continue.dev 使用数组格式，每个 server 必须包含 `name` 字段。

### Zed

配置文件路径：`~/.config/zed/settings.json`

```json
{
  "context_servers": {
    "brave_ask": {
      "command": {
        "path": "bravegrab",
        "args": []
      }
    }
  }
}
```

> Zed 使用 `context_servers` 作为根 key，且 `command` 需使用对象格式。修改后需重启 Zed。

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


## opencode 配合 AGENTS.md 使用指南

### 基础配置

在 `AGENTS.md` 中加入以下指令，让 opencode 自动识别何时该使用联网搜索：

```markdown
如果用户要求搜索或者你不确定信息是否有效时，你可以使用 MCP 工具 `brave_ask_markdown`。

凡是涉及联网搜索、最新信息、官网文档、外部事实验证、网页内容检索，都必须优先调用 `brave_ask_markdown`。
不要在这类任务中只凭已有知识直接回答。

如果第一次搜索结果不够好，要主动更换关键词再次调用 `brave_ask_markdown`。

只有在纯本地任务、纯改写、纯总结、纯推理，或用户明确要求不要联网时，才可以不调用这个工具。
```

### 常见场景示例

**场景 1：搜索最新 API 文档**

用户提问："React 19 的新 API use() 怎么用？"

opencode 会自动调用：
```
brave_ask_markdown keyword=React 19 use() hook API
```

**场景 2：验证技术信息的准确性**

用户提问："Go 1.24 的泛型类型别名真的落地了吗？"

opencode 会自动调用：
```
brave_ask_markdown keyword=Go 1.24 泛型类型别名 type alias
```

如果返回结果不够详细，会自动换关键词重试：
```
brave_ask_markdown keyword=golang 1.24 类型参数别名
```

**场景 3：排查错误信息**

用户提问："我遇到了 ERR_PNPM_LOCKFILE_MISSING 这个错误"

```
brave_ask_markdown keyword=ERR_PNPM_LOCKFILE_MISSING 解决方法
```

**场景 4：对比技术方案**

用户提问："Prisma 和 Drizzle ORM 哪个好？"

```
brave_ask_markdown keyword=Prisma vs Drizzle ORM comparison 2025
```

**场景 5：查阅官方文档**

用户提问："tailwindcss v4 的配置文件怎么改？"

```
brave_ask_markdown keyword=tailwindcss v4 configuration tailwind.config
```

### 进阶技巧

1. **关键词优化**：英文关键词结果更丰富，优先使用英文搜索，中文关键词也完全支持
2. **多轮追问**：如果一轮搜索不够，AGENTS.md 中的规则会触发自动换关键词重试
3. **结合本地知识**：搜索到的结果会和 opencode 自身知识融合，给出更准确的回答
4. **代理支持**：在 AGENTS.md 中也可以指定默认代理：
   ```markdown
   如果网络环境需要代理，调用 `brave_ask_markdown keyword=<关键词> proxy=0`
   ```

## 系统要求

- 运行时需要能够启动 headless Chromium（go-rod 会自动下载，首次启动较慢）
- 支持平台：
  - Linux amd64
  - macOS (universal, Intel/Apple Silicon)
  - Windows amd64

## License

[MIT](LICENSE)
