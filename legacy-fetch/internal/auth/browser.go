package auth

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/go-rod/rod"
	"github.com/go-rod/rod/lib/proto"
)

// BrowserAuth handles browser-based authentication using Rod
type BrowserAuth struct {
	sessionManager *SessionManager
	browserType    BrowserType
}

// NewBrowserAuth creates a new BrowserAuth instance
func NewBrowserAuth(sessionManager *SessionManager) *BrowserAuth {
	return &BrowserAuth{
		sessionManager: sessionManager,
		browserType:    BrowserEdge, // Default to Edge for work SSO
	}
}

// SetBrowserType sets which browser to use for authentication
func (b *BrowserAuth) SetBrowserType(browserType BrowserType) {
	b.browserType = browserType
}

// Authenticate opens a browser to the target URL and captures cookies after login
func (b *BrowserAuth) Authenticate(targetURL string) error {
	parsedURL, err := url.Parse(targetURL)
	if err != nil {
		return fmt.Errorf("failed to parse target URL: %w", err)
	}

	host := parsedURL.Host

	// Get browser config
	config, err := GetBrowserConfig(b.browserType)
	if err != nil {
		return fmt.Errorf("failed to get browser config: %w", err)
	}

	fmt.Printf("Opening browser to: %s\n", targetURL)
	fmt.Println("Completing login flow...")

	// Try to connect to existing browser, or launch one
	browser, needsClose, err := b.getOrLaunchBrowser(config)
	if err != nil {
		return fmt.Errorf("failed to get browser: %w", err)
	}
	if needsClose {
		defer browser.MustClose()
	}

	// Create a new page and navigate to target URL
	page := browser.MustPage(targetURL)
	defer page.MustClose()

	// Wait for login completion
	originalHost := host
	loginComplete := make(chan bool, 1)
	done := make(chan struct{})

	// Goroutine 1: Watch for URL to stabilize on original host
	go func() {
		var lastURL string
		var stableTime time.Time
		const stableThreshold = 3 * time.Second

		for {
			select {
			case <-done:
				return
			default:
				time.Sleep(500 * time.Millisecond)
				info, err := page.Info()
				if err != nil {
					return
				}

				currentURL := info.URL
				currentParsed, err := url.Parse(currentURL)
				if err != nil {
					continue
				}

				if currentURL != lastURL {
					lastURL = currentURL
					stableTime = time.Now()
					continue
				}

				if currentParsed.Host == originalHost && time.Since(stableTime) >= stableThreshold {
					select {
					case loginComplete <- true:
					default:
					}
					return
				}
			}
		}
	}()

	// Goroutine 2: Wait for user to press Enter
	go func() {
		reader := bufio.NewReader(os.Stdin)
		_, err := reader.ReadString('\n')
		if err != nil {
			return
		}
		select {
		case loginComplete <- true:
		default:
		}
	}()

	<-loginComplete
	close(done)

	fmt.Println("Login completed. Capturing cookies...")

	cookies, err := b.extractCookies(browser, host)
	if err != nil {
		return fmt.Errorf("failed to extract cookies: %w", err)
	}

	if len(cookies) == 0 {
		return fmt.Errorf("no cookies captured - login may have failed")
	}

	fmt.Printf("Captured %d cookies\n", len(cookies))

	if err := b.sessionManager.SaveCookies(host, cookies); err != nil {
		return fmt.Errorf("failed to save cookies: %w", err)
	}

	fmt.Printf("Session saved for host: %s\n", host)

	return nil
}

// AuthResult contains everything captured during a browser authentication flow.
type AuthResult struct {
	Cookies      []*http.Cookie
	LocalStorage map[string]string
}

// AuthenticateAndCapture performs the browser auth flow and returns all captured
// credentials (cookies and localStorage). Unlike Authenticate, it does not
// save cookies to the session cache — the caller decides what to do with the results.
func (b *BrowserAuth) AuthenticateAndCapture(targetURL string) (*AuthResult, error) {
	parsedURL, err := url.Parse(targetURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse target URL: %w", err)
	}

	host := parsedURL.Host

	config, err := GetBrowserConfig(b.browserType)
	if err != nil {
		return nil, fmt.Errorf("failed to get browser config: %w", err)
	}

	fmt.Printf("Opening browser to: %s\n", targetURL)
	fmt.Println("Completing login flow...")

	browser, needsClose, err := b.getOrLaunchBrowser(config)
	if err != nil {
		return nil, fmt.Errorf("failed to get browser: %w", err)
	}
	if needsClose {
		defer browser.MustClose()
	}

	page := browser.MustPage(targetURL)
	defer page.MustClose()

	// Wait for login completion
	// For SPA apps with Auth0, we need to wait until the URL moves past /landing
	// The flow is: /landing → Auth0 → MS SSO → Auth0 callback → /data-queue
	// We detect completion when the URL is stable on the original host AND
	// is not the landing page (indicating the auth flow completed)
	originalHost := host
	loginComplete := make(chan bool, 1)
	done := make(chan struct{})

	go func() {
		var lastURL string
		var stableTime time.Time
		const stableThreshold = 3 * time.Second

		for {
			select {
			case <-done:
				return
			default:
				time.Sleep(500 * time.Millisecond)
				info, err := page.Info()
				if err != nil {
					return
				}

				currentURL := info.URL
				currentParsed, err := url.Parse(currentURL)
				if err != nil {
					continue
				}

				if currentURL != lastURL {
					lastURL = currentURL
					stableTime = time.Now()
					continue
				}

				// Must be on original host, stable, and NOT on /landing
				isOnHost := currentParsed.Host == originalHost
				isStable := time.Since(stableTime) >= stableThreshold
				isPastLanding := currentParsed.Path != "/landing" && currentParsed.Path != "/landing/"

				if isOnHost && isStable && isPastLanding {
					select {
					case loginComplete <- true:
					default:
					}
					return
				}
			}
		}
	}()

	go func() {
		reader := bufio.NewReader(os.Stdin)
		_, err := reader.ReadString('\n')
		if err != nil {
			return
		}
		select {
		case loginComplete <- true:
		default:
		}
	}()

	<-loginComplete
	close(done)

	fmt.Println("Login completed. Capturing credentials...")

	// Extract cookies
	cookies, err := b.extractCookies(browser, host)
	if err != nil {
		return nil, fmt.Errorf("failed to extract cookies: %w", err)
	}
	fmt.Printf("Captured %d cookies\n", len(cookies))

	// Extract localStorage from the page we're on
	pageInfo, _ := page.Info()
	if pageInfo != nil {
		fmt.Printf("Reading localStorage from: %s\n", pageInfo.URL)
	}

	localStorage, err := ExtractLocalStorage(page)
	if err != nil {
		// Non-fatal — some sites don't use localStorage
		fmt.Printf("Warning: could not read localStorage: %v\n", err)
		localStorage = map[string]string{}
	} else {
		fmt.Printf("Captured %d localStorage entries\n", len(localStorage))
		if len(localStorage) == 0 {
			// Debug: list all pages to see if we're on the wrong one
			pages, _ := browser.Pages()
			fmt.Printf("Browser has %d pages:\n", len(pages))
			for i, p := range pages {
				info, _ := p.Info()
				if info != nil {
					fmt.Printf("  [%d] %s\n", i, info.URL)
				}
			}
		}
	}

	return &AuthResult{
		Cookies:      cookies,
		LocalStorage: localStorage,
	}, nil
}

// getOrLaunchBrowser connects to an existing debug browser or launches one
// Returns the browser, whether it needs to be closed, and any error
func (b *BrowserAuth) getOrLaunchBrowser(config *BrowserConfig) (*rod.Browser, bool, error) {
	// First, check if browser is already running with debug port
	if config.IsDebugPortOpen() {
		fmt.Printf("Connecting to existing %s browser on port %d...\n", config.Type, config.DebugPort)
		wsURL, err := config.WebSocketDebuggerURL()
		if err != nil {
			return nil, false, fmt.Errorf("failed to get WebSocket URL: %w", err)
		}
		browser := rod.New().ControlURL(wsURL).MustConnect()
		// Don't close browser we connected to - user's browser stays open
		return browser, false, nil
	}

	// Browser not running with debug, launch it
	fmt.Printf("Launching %s with debug port %d...\n", config.Type, config.DebugPort)

	cmd := exec.Command(config.ExePath,
		fmt.Sprintf("--remote-debugging-port=%d", config.DebugPort),
		fmt.Sprintf("--user-data-dir=%s", config.UserDataDir),
		"--remote-allow-origins=*",
	)
	if err := cmd.Start(); err != nil {
		return nil, false, fmt.Errorf("failed to launch browser: %w", err)
	}

	// Wait for debug port to become available
	for i := 0; i < 30; i++ {
		time.Sleep(500 * time.Millisecond)
		if config.IsDebugPortOpen() {
			break
		}
	}

	if !config.IsDebugPortOpen() {
		return nil, false, fmt.Errorf("browser debug port did not open after 15 seconds")
	}

	wsURL, err := config.WebSocketDebuggerURL()
	if err != nil {
		return nil, false, fmt.Errorf("failed to get WebSocket URL: %w", err)
	}

	browser := rod.New().ControlURL(wsURL).MustConnect()
	// We launched this browser, but don't close it - user may want to keep using it
	return browser, false, nil
}

// rawCookie is a flexible struct for parsing CDP cookie responses
// Chromium 136+ changed partitionKey from string to object, breaking Rod's types
type rawCookie struct {
	Name     string  `json:"name"`
	Value    string  `json:"value"`
	Domain   string  `json:"domain"`
	Path     string  `json:"path"`
	Expires  float64 `json:"expires"`
	Secure   bool    `json:"secure"`
	HTTPOnly bool    `json:"httpOnly"`
	SameSite string  `json:"sameSite"`
}

// extractCookies extracts cookies from the browser and converts them to http.Cookie format
func (b *BrowserAuth) extractCookies(browser *rod.Browser, host string) ([]*http.Cookie, error) {
	// Use raw CDP call to avoid Rod's outdated proto types
	ctx := context.Background()
	result, err := browser.Call(ctx, "", "Storage.getCookies", nil)
	if err != nil {
		return nil, fmt.Errorf("failed to get cookies from browser: %w", err)
	}

	// Parse the raw JSON response
	var response struct {
		Cookies []rawCookie `json:"cookies"`
	}
	if err := json.Unmarshal(result, &response); err != nil {
		return nil, fmt.Errorf("failed to parse cookies response: %w", err)
	}

	var httpCookies []*http.Cookie
	for _, c := range response.Cookies {
		sameSite := http.SameSiteDefaultMode
		switch c.SameSite {
		case "Strict":
			sameSite = http.SameSiteStrictMode
		case "Lax":
			sameSite = http.SameSiteLaxMode
		case "None":
			sameSite = http.SameSiteNoneMode
		}

		cookie := &http.Cookie{
			Name:     c.Name,
			Value:    c.Value,
			Path:     c.Path,
			Domain:   c.Domain,
			Expires:  time.Unix(int64(c.Expires), 0),
			Secure:   c.Secure,
			HttpOnly: c.HTTPOnly,
			SameSite: sameSite,
		}
		httpCookies = append(httpCookies, cookie)
	}

	return httpCookies, nil
}

// convertCookies converts proto.NetworkCookie to http.Cookie
func (b *BrowserAuth) convertCookies(rodCookies []*proto.NetworkCookie) []*http.Cookie {
	var httpCookies []*http.Cookie
	for _, c := range rodCookies {
		cookie := &http.Cookie{
			Name:     c.Name,
			Value:    c.Value,
			Path:     c.Path,
			Domain:   c.Domain,
			Expires:  time.Unix(int64(c.Expires), 0),
			Secure:   c.Secure,
			HttpOnly: c.HTTPOnly,
			SameSite: b.convertSameSite(c.SameSite),
		}
		httpCookies = append(httpCookies, cookie)
	}
	return httpCookies
}

// isCookieRelevant checks if a cookie is relevant to the target host
func (b *BrowserAuth) isCookieRelevant(cookie *proto.NetworkCookie, targetHost string) bool {
	if cookie.Domain == "" {
		return true
	}

	cookieDomain := strings.TrimPrefix(cookie.Domain, ".")
	targetHost = strings.TrimPrefix(targetHost, ".")

	return targetHost == cookieDomain || strings.HasSuffix(targetHost, "."+cookieDomain)
}

// convertSameSite converts Rod's SameSite value to http.Cookie SameSite
func (b *BrowserAuth) convertSameSite(sameSite proto.NetworkCookieSameSite) http.SameSite {
	switch sameSite {
	case proto.NetworkCookieSameSiteStrict:
		return http.SameSiteStrictMode
	case proto.NetworkCookieSameSiteLax:
		return http.SameSiteLaxMode
	case proto.NetworkCookieSameSiteNone:
		return http.SameSiteNoneMode
	default:
		return http.SameSiteDefaultMode
	}
}
