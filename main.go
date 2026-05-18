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
	"github.com/chromedp/cdproto/browser"
	"github.com/chromedp/chromedp"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

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
	targetURL := "https://search.brave.com/ask?q=" + url.QueryEscape(keyword)

	opts := append(chromedp.DefaultExecAllocatorOptions[:],
		chromedp.Flag("headless", false),
	)
	if proxy != "" {
		opts = append(opts, chromedp.ProxyServer(proxy))
	}

	allocCtx, cancel := chromedp.NewExecAllocator(context.Background(), opts...)
	defer cancel()

	ctx, cancel := chromedp.NewContext(allocCtx)
	defer cancel()

	ctx, cancel = context.WithTimeout(ctx, 60*time.Second)
	defer cancel()

	var content string

	err := chromedp.Run(ctx,
		chromedp.ActionFunc(func(ctx context.Context) error {
			windowID, _, err := browser.GetWindowForTarget().Do(ctx)
			if err != nil {
				return nil
			}
			return browser.SetWindowBounds(windowID, &browser.Bounds{
				WindowState: browser.WindowStateMinimized,
			}).Do(ctx)
		}),
		chromedp.Navigate(targetURL),
		chromedp.WaitVisible(`div.tap-round-footer`, chromedp.ByQuery),
		chromedp.Evaluate(`
			(() => {
				document
					.querySelectorAll('div.message.user, div.message.augment, div.message.response-header, div.tap-round-footer, div.tap-followups')
					.forEach(el => el.remove());
				return true;
			})()
		`, nil),
		chromedp.OuterHTML(`div.is-complete`, &content, chromedp.ByQuery),
	)
	if err != nil {
		return "", "", err
	}

	markdown, err := htmltomarkdown.ConvertString(content)
	if err != nil {
		return "", "", err
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
