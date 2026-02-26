package auth

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestSessionManager_SaveAndLoadCookies(t *testing.T) {
	// Create temp directory for test
	tempDir := t.TempDir()

	sm := &SessionManager{
		cacheDir: tempDir,
	}

	host := "test.example.com"

	// Create test cookies
	testCookies := []*http.Cookie{
		{
			Name:     "session_id",
			Value:    "abc123",
			Domain:   ".example.com",
			Path:     "/",
			Expires:  time.Now().Add(24 * time.Hour),
			HttpOnly: true,
			Secure:   true,
		},
		{
			Name:   "user_pref",
			Value:  "dark_mode",
			Domain: ".example.com",
			Path:   "/",
		},
	}

	// Test Save
	err := sm.SaveCookies(host, testCookies)
	if err != nil {
		t.Fatalf("SaveCookies failed: %v", err)
	}

	// Verify file was created
	expectedPath := filepath.Join(tempDir, "test.example.com.json")
	if _, err := os.Stat(expectedPath); os.IsNotExist(err) {
		t.Fatalf("Cookie file was not created at %s", expectedPath)
	}

	// Test Load
	loadedCookies, err := sm.LoadCookies(host)
	if err != nil {
		t.Fatalf("LoadCookies failed: %v", err)
	}

	// Verify loaded cookies match
	if len(loadedCookies) != len(testCookies) {
		t.Fatalf("Expected %d cookies, got %d", len(testCookies), len(loadedCookies))
	}

	for i, cookie := range loadedCookies {
		expected := testCookies[i]
		if cookie.Name != expected.Name {
			t.Errorf("Cookie %d: expected name %s, got %s", i, expected.Name, cookie.Name)
		}
		if cookie.Value != expected.Value {
			t.Errorf("Cookie %d: expected value %s, got %s", i, expected.Value, cookie.Value)
		}
		if cookie.Domain != expected.Domain {
			t.Errorf("Cookie %d: expected domain %s, got %s", i, expected.Domain, cookie.Domain)
		}
		if cookie.Path != expected.Path {
			t.Errorf("Cookie %d: expected path %s, got %s", i, expected.Path, cookie.Path)
		}
		if cookie.HttpOnly != expected.HttpOnly {
			t.Errorf("Cookie %d: expected HttpOnly %v, got %v", i, expected.HttpOnly, cookie.HttpOnly)
		}
		if cookie.Secure != expected.Secure {
			t.Errorf("Cookie %d: expected Secure %v, got %v", i, expected.Secure, cookie.Secure)
		}
	}
}

func TestSessionManager_LoadCookies_NotFound(t *testing.T) {
	tempDir := t.TempDir()

	sm := &SessionManager{
		cacheDir: tempDir,
	}

	// Try to load cookies for non-existent host
	cookies, err := sm.LoadCookies("nonexistent.example.com")

	// Should return empty slice, not an error
	if err != nil {
		t.Fatalf("LoadCookies should not error on missing file: %v", err)
	}

	if len(cookies) != 0 {
		t.Fatalf("Expected empty cookie slice, got %d cookies", len(cookies))
	}
}

func TestSessionManager_Clear(t *testing.T) {
	tempDir := t.TempDir()

	sm := &SessionManager{
		cacheDir: tempDir,
	}

	host := "test.example.com"

	// Save some cookies
	testCookies := []*http.Cookie{
		{Name: "test", Value: "value"},
	}
	err := sm.SaveCookies(host, testCookies)
	if err != nil {
		t.Fatalf("SaveCookies failed: %v", err)
	}

	// Verify file exists
	cookiePath := filepath.Join(tempDir, "test.example.com.json")
	if _, err := os.Stat(cookiePath); os.IsNotExist(err) {
		t.Fatalf("Cookie file was not created")
	}

	// Clear the session
	err = sm.Clear(host)
	if err != nil {
		t.Fatalf("Clear failed: %v", err)
	}

	// Verify file was deleted
	if _, err := os.Stat(cookiePath); !os.IsNotExist(err) {
		t.Fatalf("Cookie file should have been deleted")
	}
}

func TestSessionManager_Clear_NotFound(t *testing.T) {
	tempDir := t.TempDir()

	sm := &SessionManager{
		cacheDir: tempDir,
	}

	// Clear non-existent session should not error
	err := sm.Clear("nonexistent.example.com")
	if err != nil {
		t.Fatalf("Clear should not error on non-existent file: %v", err)
	}
}

func TestNewSessionManager(t *testing.T) {
	sm, err := NewSessionManager()
	if err != nil {
		t.Fatalf("NewSessionManager failed: %v", err)
	}

	// Verify cacheDir is set and uses home directory
	if sm.cacheDir == "" {
		t.Fatal("SessionManager cacheDir should not be empty")
	}

	// Should contain .omatic/auth
	if !filepath.IsAbs(sm.cacheDir) {
		t.Errorf("cacheDir should be absolute path, got: %s", sm.cacheDir)
	}
}

func TestSessionManager_ListSessions(t *testing.T) {
	tempDir := t.TempDir()

	sm := &SessionManager{
		cacheDir: tempDir,
	}

	// Save cookies for multiple hosts
	hosts := []string{"host1.example.com", "host2.example.com", "host3.example.com"}
	for _, host := range hosts {
		err := sm.SaveCookies(host, []*http.Cookie{{Name: "test", Value: "value"}})
		if err != nil {
			t.Fatalf("SaveCookies failed for %s: %v", host, err)
		}
	}

	// List sessions
	sessions, err := sm.ListSessions()
	if err != nil {
		t.Fatalf("ListSessions failed: %v", err)
	}

	if len(sessions) != len(hosts) {
		t.Fatalf("Expected %d sessions, got %d", len(hosts), len(sessions))
	}

	// Verify all hosts are in the list
	sessionMap := make(map[string]bool)
	for _, session := range sessions {
		sessionMap[session] = true
	}

	for _, host := range hosts {
		if !sessionMap[host] {
			t.Errorf("Expected host %s in sessions list", host)
		}
	}
}

func TestCookieSerialization(t *testing.T) {
	// Test that cookie serialization/deserialization preserves all fields
	original := &http.Cookie{
		Name:     "test_cookie",
		Value:    "test_value",
		Path:     "/api",
		Domain:   ".example.com",
		Expires:  time.Date(2026, 12, 31, 23, 59, 59, 0, time.UTC),
		MaxAge:   3600,
		Secure:   true,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	}

	// Serialize
	data, err := json.Marshal([]*http.Cookie{original})
	if err != nil {
		t.Fatalf("Failed to marshal cookie: %v", err)
	}

	// Deserialize
	var loaded []*http.Cookie
	err = json.Unmarshal(data, &loaded)
	if err != nil {
		t.Fatalf("Failed to unmarshal cookie: %v", err)
	}

	if len(loaded) != 1 {
		t.Fatalf("Expected 1 cookie, got %d", len(loaded))
	}

	restored := loaded[0]

	// Verify all fields
	if restored.Name != original.Name {
		t.Errorf("Name mismatch: expected %s, got %s", original.Name, restored.Name)
	}
	if restored.Value != original.Value {
		t.Errorf("Value mismatch: expected %s, got %s", original.Value, restored.Value)
	}
	if restored.Path != original.Path {
		t.Errorf("Path mismatch: expected %s, got %s", original.Path, restored.Path)
	}
	if restored.Domain != original.Domain {
		t.Errorf("Domain mismatch: expected %s, got %s", original.Domain, restored.Domain)
	}
	if restored.MaxAge != original.MaxAge {
		t.Errorf("MaxAge mismatch: expected %d, got %d", original.MaxAge, restored.MaxAge)
	}
	if restored.Secure != original.Secure {
		t.Errorf("Secure mismatch: expected %v, got %v", original.Secure, restored.Secure)
	}
	if restored.HttpOnly != original.HttpOnly {
		t.Errorf("HttpOnly mismatch: expected %v, got %v", original.HttpOnly, restored.HttpOnly)
	}
	if restored.SameSite != original.SameSite {
		t.Errorf("SameSite mismatch: expected %v, got %v", original.SameSite, restored.SameSite)
	}
}
