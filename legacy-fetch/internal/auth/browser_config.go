package auth

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"
)

// BrowserType represents a supported browser
type BrowserType string

const (
	BrowserEdge   BrowserType = "edge"
	BrowserChrome BrowserType = "chrome"
)

// BrowserConfig holds configuration for a browser
type BrowserConfig struct {
	Type        BrowserType
	ExePath     string
	UserDataDir string
	DebugPort   int
}

// GetBrowserConfig returns the configuration for the specified browser type
func GetBrowserConfig(browserType BrowserType) (*BrowserConfig, error) {
	switch browserType {
	case BrowserEdge:
		return &BrowserConfig{
			Type:        BrowserEdge,
			ExePath:     findEdgePath(),
			UserDataDir: os.ExpandEnv("$LOCALAPPDATA/Microsoft/EdgeDebug"),
			DebugPort:   9222,
		}, nil
	case BrowserChrome:
		return &BrowserConfig{
			Type:        BrowserChrome,
			ExePath:     findChromePath(),
			UserDataDir: os.ExpandEnv("$LOCALAPPDATA/Google/ChromeDebug"),
			DebugPort:   9223,
		}, nil
	default:
		return nil, fmt.Errorf("unsupported browser type: %s", browserType)
	}
}

// DebugURL returns the debug endpoint URL for this browser
func (c *BrowserConfig) DebugURL() string {
	return fmt.Sprintf("http://127.0.0.1:%d", c.DebugPort)
}

// WebSocketDebuggerURL returns the WebSocket URL for CDP connection
func (c *BrowserConfig) WebSocketDebuggerURL() (string, error) {
	resp, err := http.Get(c.DebugURL() + "/json/version")
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		WebSocketDebuggerURL string `json:"webSocketDebuggerUrl"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}

	if result.WebSocketDebuggerURL == "" {
		return "", fmt.Errorf("webSocketDebuggerUrl not found in response")
	}

	return result.WebSocketDebuggerURL, nil
}

// IsDebugPortOpen checks if the browser's debug port is responding
func (c *BrowserConfig) IsDebugPortOpen() bool {
	client := &http.Client{Timeout: 500 * time.Millisecond}
	resp, err := client.Get(c.DebugURL() + "/json/version")
	if err != nil {
		return false
	}
	resp.Body.Close()
	return resp.StatusCode == 200
}

// findEdgePath returns the path to Edge executable
func findEdgePath() string {
	paths := []string{
		os.ExpandEnv("$PROGRAMFILES(X86)/Microsoft/Edge/Application/msedge.exe"),
		os.ExpandEnv("$PROGRAMFILES/Microsoft/Edge/Application/msedge.exe"),
		"C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
		"C:/Program Files/Microsoft/Edge/Application/msedge.exe",
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return "msedge.exe" // Fallback to PATH
}

// findChromePath returns the path to Chrome executable
func findChromePath() string {
	paths := []string{
		os.ExpandEnv("$PROGRAMFILES/Google/Chrome/Application/chrome.exe"),
		os.ExpandEnv("$PROGRAMFILES(X86)/Google/Chrome/Application/chrome.exe"),
		"C:/Program Files/Google/Chrome/Application/chrome.exe",
		"C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return "chrome.exe" // Fallback to PATH
}
