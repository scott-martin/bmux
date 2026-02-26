package client

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"github.com/omaticsoftware/fetch/internal/auth"
)

// Client is an HTTP client that automatically injects cookies from cached sessions
type Client struct {
	httpClient     *http.Client
	sessionManager *auth.SessionManager
	browserAuth    *auth.BrowserAuth
}

// NewClient creates a new Client with default settings
func NewClient() (*Client, error) {
	return NewClientWithBrowser(auth.BrowserEdge)
}

// NewClientWithBrowser creates a new Client with the specified browser type
func NewClientWithBrowser(browserType auth.BrowserType) (*Client, error) {
	sessionManager, err := auth.NewSessionManager()
	if err != nil {
		return nil, fmt.Errorf("failed to create session manager: %w", err)
	}

	browserAuth := auth.NewBrowserAuth(sessionManager)
	browserAuth.SetBrowserType(browserType)

	return &Client{
		httpClient:     &http.Client{},
		sessionManager: sessionManager,
		browserAuth:    browserAuth,
	}, nil
}

// SetBrowserType changes the browser used for authentication
func (c *Client) SetBrowserType(browserType auth.BrowserType) {
	c.browserAuth.SetBrowserType(browserType)
}

// Get performs a GET request with automatic cookie injection
func (c *Client) Get(targetURL string) (*http.Response, error) {
	req, err := http.NewRequest(http.MethodGet, targetURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	return c.do(req)
}

// Post performs a POST request with automatic cookie injection
func (c *Client) Post(targetURL string, contentType string, body []byte) (*http.Response, error) {
	req, err := http.NewRequest(http.MethodPost, targetURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}

	return c.do(req)
}

// Put performs a PUT request with automatic cookie injection
func (c *Client) Put(targetURL string, contentType string, body []byte) (*http.Response, error) {
	req, err := http.NewRequest(http.MethodPut, targetURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}

	return c.do(req)
}

// Delete performs a DELETE request with automatic cookie injection
func (c *Client) Delete(targetURL string) (*http.Response, error) {
	req, err := http.NewRequest(http.MethodDelete, targetURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	return c.do(req)
}

// do executes an HTTP request with cookie injection and auto-authentication
func (c *Client) do(req *http.Request) (*http.Response, error) {
	// Extract host from request URL
	parsedURL, err := url.Parse(req.URL.String())
	if err != nil {
		return nil, fmt.Errorf("failed to parse URL: %w", err)
	}

	host := parsedURL.Host

	// Load cookies from session cache
	cookies, err := c.sessionManager.LoadCookies(host)
	if err != nil {
		return nil, fmt.Errorf("failed to load cookies: %w", err)
	}

	// Inject only cookies that match the request domain
	for _, cookie := range cookies {
		if cookieMatchesDomain(cookie, host) {
			req.AddCookie(cookie)
		}
	}

	// Make the request
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}

	// Check for 401 Unauthorized
	if resp.StatusCode == http.StatusUnauthorized {
		// For now, just return the response
		// In a future enhancement, we could trigger re-authentication here
		// but that requires user interaction (browser flow), which is better
		// handled explicitly via the CLI auth command
		return resp, nil
	}

	return resp, nil
}

// GetWithAuth performs a GET request, triggering browser authentication if no session exists
func (c *Client) GetWithAuth(targetURL string) (*http.Response, error) {
	// Extract host from URL
	parsedURL, err := url.Parse(targetURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse URL: %w", err)
	}

	host := parsedURL.Host

	// Check if session exists
	cookies, err := c.sessionManager.LoadCookies(host)
	if err != nil {
		return nil, fmt.Errorf("failed to load cookies: %w", err)
	}

	// If no session exists, trigger authentication
	if len(cookies) == 0 {
		fmt.Printf("No session found for %s, triggering authentication...\n", host)
		if err := c.browserAuth.Authenticate(targetURL); err != nil {
			return nil, fmt.Errorf("authentication failed: %w", err)
		}
	}

	// Make the request
	req, err := http.NewRequest(http.MethodGet, targetURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.do(req)
	if err != nil {
		return nil, err
	}

	// If we get 401, session may have expired - trigger re-authentication
	if resp.StatusCode == http.StatusUnauthorized {
		fmt.Printf("Session expired for %s, re-authenticating...\n", host)
		resp.Body.Close() // Close the 401 response

		if err := c.browserAuth.Authenticate(targetURL); err != nil {
			return nil, fmt.Errorf("re-authentication failed: %w", err)
		}

		// Retry the request
		req, err = http.NewRequest(http.MethodGet, targetURL, nil)
		if err != nil {
			return nil, fmt.Errorf("failed to create retry request: %w", err)
		}

		return c.do(req)
	}

	return resp, nil
}

// PostWithAuth performs a POST request with auto-authentication
func (c *Client) PostWithAuth(targetURL string, contentType string, body []byte) (*http.Response, error) {
	parsedURL, err := url.Parse(targetURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse URL: %w", err)
	}

	host := parsedURL.Host

	// Check if session exists
	cookies, err := c.sessionManager.LoadCookies(host)
	if err != nil {
		return nil, fmt.Errorf("failed to load cookies: %w", err)
	}

	// If no session exists, trigger authentication
	if len(cookies) == 0 {
		fmt.Printf("No session found for %s, triggering authentication...\n", host)
		if err := c.browserAuth.Authenticate(targetURL); err != nil {
			return nil, fmt.Errorf("authentication failed: %w", err)
		}
	}

	// Make the request
	req, err := http.NewRequest(http.MethodPost, targetURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}

	resp, err := c.do(req)
	if err != nil {
		return nil, err
	}

	// If we get 401, session may have expired - trigger re-authentication and retry
	if resp.StatusCode == http.StatusUnauthorized {
		fmt.Printf("Session expired for %s, re-authenticating...\n", host)
		resp.Body.Close()

		if err := c.browserAuth.Authenticate(targetURL); err != nil {
			return nil, fmt.Errorf("re-authentication failed: %w", err)
		}

		// Retry the request
		req, err = http.NewRequest(http.MethodPost, targetURL, bytes.NewReader(body))
		if err != nil {
			return nil, fmt.Errorf("failed to create retry request: %w", err)
		}

		if contentType != "" {
			req.Header.Set("Content-Type", contentType)
		}

		return c.do(req)
	}

	return resp, nil
}

// Authenticate triggers browser authentication for a specific URL
func (c *Client) Authenticate(targetURL string) error {
	return c.browserAuth.Authenticate(targetURL)
}

// AuthenticateAndCapture triggers browser authentication and returns all
// captured credentials (cookies, localStorage) without caching them.
func (c *Client) AuthenticateAndCapture(targetURL string) (*auth.AuthResult, error) {
	return c.browserAuth.AuthenticateAndCapture(targetURL)
}

// ListSessions returns a list of all cached sessions
func (c *Client) ListSessions() ([]string, error) {
	return c.sessionManager.ListSessions()
}

// ClearSession removes the cached session for a specific host
func (c *Client) ClearSession(host string) error {
	return c.sessionManager.Clear(host)
}

// GetBody is a convenience function to get the response body as a byte slice
func GetBody(resp *http.Response) ([]byte, error) {
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}

// cookieMatchesDomain checks if a cookie should be sent to the given host
func cookieMatchesDomain(cookie *http.Cookie, host string) bool {
	domain := cookie.Domain
	if domain == "" {
		return true // No domain restriction
	}

	// Strip leading dot from cookie domain
	domain = strings.TrimPrefix(domain, ".")
	host = strings.TrimPrefix(host, ".")

	// Exact match
	if domain == host {
		return true
	}

	// Host is a subdomain of cookie domain
	if strings.HasSuffix(host, "."+domain) {
		return true
	}

	return false
}
