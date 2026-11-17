package main

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	htmltomarkdown "github.com/JohannesKaufmann/html-to-markdown/v2/converter"
	"github.com/JohannesKaufmann/html-to-markdown/v2/plugin/base"
	"github.com/JohannesKaufmann/html-to-markdown/v2/plugin/commonmark"
	"github.com/JohannesKaufmann/html-to-markdown/v2/plugin/table"
	"github.com/go-rod/rod"
	"github.com/go-rod/rod/lib/launcher"
	"github.com/go-rod/rod/lib/proto"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func minimizePage(p *rod.Page) {
	win, err := proto.BrowserGetWindowForTarget{}.Call(p)
	if err != nil {
		return
	}
	proto.BrowserSetWindowBounds{
		WindowID: win.WindowID,
		Bounds: &proto.BrowserBounds{
			WindowState: proto.BrowserWindowStateMinimized,
		},
	}.Call(p)
}

var defaultProxies = []string{
	"http://127.0.0.1:8080",
	"socks5://127.0.0.1:1080",
}

type BraveAskInput struct {
	// Why：参数名就是 prompt——叫 keyword 模型就填关键词堆，
	// 叫 question 模型才写完整问题。老 keyword 留别名兼容旧客户端。
	Question string `json:"question,omitempty" jsonschema:"ONE self-contained natural-language research question (e.g. compare Hainan vs Hangzhou gas prices). NOT a pile of keywords"`
	Keyword  string `json:"keyword,omitempty" jsonschema:"deprecated alias of question"`
	Proxy    string `json:"proxy,omitempty" jsonschema:"proxy URL or index into proxy list, optional"`
	HTML     bool   `json:"html,omitempty" jsonschema:"return raw HTML instead of Markdown"`
}

func proxyList() []string {
	env := os.Getenv("PROXY_LIST")
	if env == "" {
		return defaultProxies
	}
	return strings.FieldsFunc(env, func(r rune) bool {
		return r == ',' || r == ' ' || r == ';'
	})
}

func resolveProxy(proxyValue string) (string, error) {
	if strings.TrimSpace(proxyValue) == "" {
		return "", nil
	}

	proxies := proxyList()
	if strings.Contains(proxyValue, "://") {
		return proxyValue, nil
	}

	idx, err := strconv.Atoi(proxyValue)
	if err != nil {
		return "", fmt.Errorf("invalid proxy value %q (must be a URL or index)", proxyValue)
	}
	if idx < 0 || idx >= len(proxies) {
		return "", fmt.Errorf("invalid proxy index %d (available 0-%d)", idx, len(proxies)-1)
	}
	return proxies[idx], nil
}

func fetchBraveAskContent(keyword string, proxy string) (string, string, error) {
	targetURL := "https://search.brave.com/ask?q=" + url.QueryEscape("你是精通编程的专家，请基于最新、权威的信息.不要编造内容.**任务**：  ") + url.QueryEscape(keyword)

	l := launcher.New()
	if proxy != "" {
		l = l.Proxy(proxy)
	}

	controlURL, err := l.Launch()
	if err != nil {
		return "", "", fmt.Errorf("launch browser: %w", err)
	}

	browser := rod.New().ControlURL(controlURL)
	if err := browser.Connect(); err != nil {
		return "", "", fmt.Errorf("connect browser: %w", err)
	}
	defer browser.Close()

	page, err := browser.Page(proto.TargetCreateTarget{URL: targetURL})
	if err != nil {
		return "", "", fmt.Errorf("navigate: %w", err)
	}
	defer page.Close()

	page = page.Timeout(60 * time.Second)
	defer page.CancelTimeout()

	minimizePage(page)

	if captchaBtn, err := page.Timeout(3 * time.Second).Element(`button[name="captcha-button"]`); err == nil {
		captchaBtn.MustClick()
		captchaBtn.MustWaitInvisible()
	}

	el, err := page.Element("div.tap-round-footer")
	if err != nil {
		return "", "", fmt.Errorf("wait for footer: %w", err)
	}
	if err := el.WaitVisible(); err != nil {
		return "", "", fmt.Errorf("wait for footer visible: %w", err)
	}

	_, err = page.Eval(`() => {
		document.querySelectorAll('div.message.user, div.message.augment, div.message.response-header, div.tap-round-footer, div.tap-followups, div.logo-wrapper')
			.forEach(el => el.remove());
	}`)
	if err != nil {
		return "", "", fmt.Errorf("cleanup DOM: %w", err)
	}

	contentEl, err := page.Element("div.is-complete")
	if err != nil {
		return "", "", fmt.Errorf("find content element: %w", err)
	}

	content, err := contentEl.HTML()
	if err != nil {
		return "", "", fmt.Errorf("get content HTML: %w", err)
	}

	// Why: favicon 图标代理（imgs.search.brave.com）与 +N 图片计数徽标
	// 都包在 div.logo-wrapper 里，一并移除；表格需 table 插件否则会被拼成纯文本。
	markdown, err := convertToMarkdown(promoteTableHeader(content))
	if err != nil {
		return "", "", fmt.Errorf("convert to markdown: %w", err)
	}

	return content, markdown, nil
}

var (
	// Why：Brave 的回答表格经常没有 <th>，table 插件此时会吐空表头
	// （`|  |  |`）还把首行数据挤进正文。无 th 的表才把首行 td 提为 th，
	// 有 th 的表原样不动；只动首行，避免把数据行误标成表头。
	reTableBlock = regexp.MustCompile(`(?is)<table.*?</table>`)
	reFirstRow   = regexp.MustCompile(`(?is)<tr[^>]*>.*?</tr>`)
	reTdOpen     = regexp.MustCompile(`(?i)<td(\s[^>]*)?>`)
	reTdClose    = regexp.MustCompile(`(?i)</td>`)
)

func promoteTableHeader(html string) string {
	return reTableBlock.ReplaceAllStringFunc(html, func(block string) string {
		if strings.Contains(strings.ToLower(block), "<th") {
			return block
		}
		first := true
		return reFirstRow.ReplaceAllStringFunc(block, func(row string) string {
			if !first {
				return row
			}
			first = false
			row = reTdOpen.ReplaceAllString(row, "<th$1>")
			return reTdClose.ReplaceAllString(row, "</th>")
		})
	})
}

func convertToMarkdown(html string) (string, error) {
	conv := htmltomarkdown.NewConverter(
		htmltomarkdown.WithPlugins(
			base.NewBasePlugin(),
			commonmark.NewCommonmarkPlugin(),
			table.NewTablePlugin(),
		),
	)
	return conv.ConvertString(html)
}

func braveAskTool(
	ctx context.Context,
	req *mcp.CallToolRequest,
	input BraveAskInput,
) (*mcp.CallToolResult, any, error) {
	question := strings.TrimSpace(input.Question)
	if question == "" {
		question = strings.TrimSpace(input.Keyword)
	}
	if question == "" {
		return &mcp.CallToolResult{
			IsError: true,
			Content: []mcp.Content{
				&mcp.TextContent{Text: "question is required"},
			},
		}, nil, nil
	}

	proxy, err := resolveProxy(input.Proxy)
	if err != nil {
		return &mcp.CallToolResult{
			IsError: true,
			Content: []mcp.Content{
				&mcp.TextContent{Text: err.Error()},
			},
		}, nil, nil
	}

	html, markdown, err := fetchBraveAskContent(question, proxy)
	if err != nil {
		return &mcp.CallToolResult{
			IsError: true,
			Content: []mcp.Content{
				&mcp.TextContent{Text: fmt.Sprintf("fetch failed: %v", err)},
			},
		}, nil, nil
	}

	result := markdown
	if input.HTML {
		result = html
	}

	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: result},
		},
	}, nil, nil
}

func main() {
	server := mcp.NewServer(
		&mcp.Implementation{
			Name:    "brave-ask-mcp",
			Version: "0.1.0",
		},
		nil,
	)

	mcp.AddTool(server, &mcp.Tool{
		Name: "brave_ask_markdown",
		Description: "Fetch Brave Ask rendered result, remove noisy divs, and return Markdown by default or HTML when html=true. " +
			"Brave Ask is an AI answering agent: ask ONE complete question per call " +
			"(e.g. compare Hainan vs Hangzhou gas prices) — a single call suffices, " +
			"do NOT split one question into multiple searches.",
	}, braveAskTool)

	if err := server.Run(context.Background(), &mcp.StdioTransport{}); err != nil {
		log.Fatal(err)
	}
}
