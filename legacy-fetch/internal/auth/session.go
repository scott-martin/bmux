package auth

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// SessionManager manages cookie storage for authenticated sessions by host
type SessionManager struct {
	cacheDir string // Directory where session files are stored (e.g., ~/.omatic/auth/)
}

// NewSessionManager creates a new SessionManager with default cache directory
func NewSessionManager() (*SessionManager, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get user home directory: %w", err)
	}

	cacheDir := filepath.Join(homeDir, ".omatic", "auth")

	// Ensure cache directory exists
	if err := os.MkdirAll(cacheDir, 0700); err != nil {
		return nil, fmt.Errorf("failed to create cache directory: %w", err)
	}

	return &SessionManager{
		cacheDir: cacheDir,
	}, nil
}

// SaveCookies saves cookies for a specific host to disk
func (s *SessionManager) SaveCookies(host string, cookies []*http.Cookie) error {
	cookiePath := s.getCookiePath(host)

	// Serialize cookies to JSON
	data, err := json.MarshalIndent(cookies, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal cookies: %w", err)
	}

	// Write to file
	if err := os.WriteFile(cookiePath, data, 0600); err != nil {
		return fmt.Errorf("failed to write cookie file: %w", err)
	}

	return nil
}

// LoadCookies loads cookies for a specific host from disk
// Returns an empty slice if no session exists (not an error)
func (s *SessionManager) LoadCookies(host string) ([]*http.Cookie, error) {
	cookiePath := s.getCookiePath(host)

	// Check if file exists
	if _, err := os.Stat(cookiePath); os.IsNotExist(err) {
		// No session cached - return empty slice
		return []*http.Cookie{}, nil
	}

	// Read file
	data, err := os.ReadFile(cookiePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read cookie file: %w", err)
	}

	// Deserialize cookies
	var cookies []*http.Cookie
	if err := json.Unmarshal(data, &cookies); err != nil {
		return nil, fmt.Errorf("failed to unmarshal cookies: %w", err)
	}

	return cookies, nil
}

// Clear removes the cached session for a specific host
func (s *SessionManager) Clear(host string) error {
	cookiePath := s.getCookiePath(host)

	// Check if file exists
	if _, err := os.Stat(cookiePath); os.IsNotExist(err) {
		// Nothing to clear - not an error
		return nil
	}

	// Delete the file
	if err := os.Remove(cookiePath); err != nil {
		return fmt.Errorf("failed to delete cookie file: %w", err)
	}

	return nil
}

// ListSessions returns a list of all cached session hosts
func (s *SessionManager) ListSessions() ([]string, error) {
	// Read directory
	entries, err := os.ReadDir(s.cacheDir)
	if err != nil {
		if os.IsNotExist(err) {
			// Cache directory doesn't exist yet - return empty list
			return []string{}, nil
		}
		return nil, fmt.Errorf("failed to read cache directory: %w", err)
	}

	// Extract hostnames from filenames
	var hosts []string
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		// Remove .json extension to get hostname
		filename := entry.Name()
		if strings.HasSuffix(filename, ".json") {
			host := strings.TrimSuffix(filename, ".json")
			hosts = append(hosts, host)
		}
	}

	return hosts, nil
}

// getCookiePath returns the file path for a host's cookie cache
func (s *SessionManager) getCookiePath(host string) string {
	return filepath.Join(s.cacheDir, fmt.Sprintf("%s.json", host))
}
