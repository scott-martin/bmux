package auth

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

// auth0CacheEntry represents the Auth0 SPA SDK localStorage cache format
type auth0CacheEntry struct {
	Body struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
		TokenType   string `json:"token_type"`
	} `json:"body"`
	ExpiresAt int64 `json:"expiresAt"`
}

// ParseAuth0Token finds and extracts an access_token from Auth0 SPA SDK
// localStorage entries. Keys are prefixed with @@auth0spajs@@.
func ParseAuth0Token(localStorage map[string]string) (string, error) {
	for key, value := range localStorage {
		if !strings.HasPrefix(key, "@@auth0spajs@@") {
			continue
		}

		var entry auth0CacheEntry
		if err := json.Unmarshal([]byte(value), &entry); err != nil {
			return "", fmt.Errorf("failed to parse Auth0 cache entry: %w", err)
		}

		if entry.Body.AccessToken == "" {
			return "", fmt.Errorf("Auth0 cache entry has no access_token")
		}

		return entry.Body.AccessToken, nil
	}

	return "", fmt.Errorf("no Auth0 token found in localStorage")
}

// FormatTokenOutput formats a JWT and cookies as KEY=value lines for stdout.
func FormatTokenOutput(jwt string, cookies []*http.Cookie) string {
	var lines []string

	if jwt != "" {
		lines = append(lines, "JWT="+jwt)
	}

	if len(cookies) > 0 {
		var parts []string
		for _, c := range cookies {
			parts = append(parts, c.Name+"="+c.Value)
		}
		lines = append(lines, "COOKIE="+strings.Join(parts, "; "))
	}

	return strings.Join(lines, "\n")
}
