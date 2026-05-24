package main

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	htmltomarkdown "github.com/JohannesKaufmann/html-to-markdown/v2"
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
	Keyword string `json:"keyword" jsonschema:"search keyword for Brave Ask"`
	Proxy   string `json:"proxy,omitempty" jsonschema:"proxy URL or index into proxy list, optional"`
	HTML    bool   `json:"html,omitempty" jsonschema:"return raw HTML instead of Markdown"`
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

	el, err := page.Element("div.tap-round-footer")
	if err != nil {
		return "", "", fmt.Errorf("wait for footer: %w", err)
	}
	if err := el.WaitVisible(); err != nil {
		return "", "", fmt.Errorf("wait for footer visible: %w", err)
	}

	_, err = page.Eval(`() => {
		document.querySelectorAll('div.message.user, div.message.augment, div.message.response-header, div.tap-round-footer, div.tap-followups')
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

	markdown, err := htmltomarkdown.ConvertString(content)
	if err != nil {
		return "", "", fmt.Errorf("convert to markdown: %w", err)
	}

	return content, markdown, nil
}

func braveAskTool(
	ctx context.Context,
	req *mcp.CallToolRequest,
	input BraveAskInput,
) (*mcp.CallToolResult, any, error) {
	keyword := strings.TrimSpace(input.Keyword)
	if keyword == "" {
		return &mcp.CallToolResult{
			IsError: true,
			Content: []mcp.Content{
				&mcp.TextContent{Text: "keyword is required"},
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

	html, markdown, err := fetchBraveAskContent(keyword, proxy)
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
		Name:        "brave_ask_markdown",
		Description: "Fetch Brave Ask rendered result, remove noisy divs, and return Markdown by default or HTML when html=true.",
	}, braveAskTool)

	if err := server.Run(context.Background(), &mcp.StdioTransport{}); err != nil {
		log.Fatal(err)
	}
}
