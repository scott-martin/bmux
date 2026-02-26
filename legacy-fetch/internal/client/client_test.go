package client

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/omaticsoftware/fetch/internal/auth"
)

// TestNewClient verifies that a new client can be created
func TestNewClient(t *testing.T) {
	client, err := NewClient()
	if err != nil {
		t.Fatalf("NewClient() failed: %v", err)
	}

	if client == nil {
		t.Fatal("NewClient() returned nil client")
	}
}

// TestClient_InjectsCookies verifies that cookies from session are injected into requests
func TestClient_InjectsCookies(t *testing.T) {
	// Create a test server that verifies cookies are present
	var receivedCookies []*http.Cookie
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedCookies = r.Cookies()
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok"}`))
	}))
	defer server.Close()

	// Create session manager and save test cookies
	sessionManager, err := auth.NewSessionManager()
	if err != nil {
		t.Fatalf("Failed to create session manager: %v", err)
	}

	serverURL, _ := url.Parse(server.URL)
	host := serverURL.Host

	testCookies := []*http.Cookie{
		{Name: "session_id", Value: "test123"},
		{Name: "auth_token", Value: "abc456"},
	}

	if err := sessionManager.SaveCookies(host, testCookies); err != nil {
		t.Fatalf("Failed to save test cookies: %v", err)
	}
	defer sessionManager.Clear(host)

	// Create client and make request
	client, err := NewClient()
	if err != nil {
		t.Fatalf("NewClient() failed: %v", err)
	}

	resp, err := client.Get(server.URL)
	if err != nil {
		t.Fatalf("Get() failed: %v", err)
	}
	defer resp.Body.Close()

	// Verify cookies were sent
	if len(receivedCookies) != 2 {
		t.Errorf("Expected 2 cookies, got %d", len(receivedCookies))
	}

	foundSession := false
	foundAuth := false
	for _, cookie := range receivedCookies {
		if cookie.Name == "session_id" && cookie.Value == "test123" {
			foundSession = true
		}
		if cookie.Name == "auth_token" && cookie.Value == "abc456" {
			foundAuth = true
		}
	}

	if !foundSession {
		t.Error("session_id cookie not found in request")
	}
	if !foundAuth {
		t.Error("auth_token cookie not found in request")
	}
}

// TestClient_MakesRequestWithoutSession verifies that client works when no session exists
// (for phase 4, it should just make the request without cookies - auth trigger tested separately)
func TestClient_MakesRequestWithoutSession(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok"}`))
	}))
	defer server.Close()

	client, err := NewClient()
	if err != nil {
		t.Fatalf("NewClient() failed: %v", err)
	}

	// Don't save any session - client should still work
	resp, err := client.Get(server.URL)
	if err != nil {
		t.Fatalf("Get() should work without session: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200, got %d", resp.StatusCode)
	}
}

// TestClient_Handles401 verifies that 401 responses are returned properly
// (auto re-auth is manual flow, tested separately - this just verifies error handling)
func TestClient_Handles401(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(`{"error":"unauthorized"}`))
	}))
	defer server.Close()

	client, err := NewClient()
	if err != nil {
		t.Fatalf("NewClient() failed: %v", err)
	}

	resp, err := client.Get(server.URL)
	if err != nil {
		t.Fatalf("Get() failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("Expected status 401, got %d", resp.StatusCode)
	}
}

// TestClient_POST verifies POST requests work with body
func TestClient_POST(t *testing.T) {
	var receivedBody string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("Expected POST, got %s", r.Method)
		}
		body := make([]byte, r.ContentLength)
		r.Body.Read(body)
		receivedBody = string(body)
		w.WriteHeader(http.StatusCreated)
		w.Write([]byte(`{"id":"123"}`))
	}))
	defer server.Close()

	client, err := NewClient()
	if err != nil {
		t.Fatalf("NewClient() failed: %v", err)
	}

	testBody := `{"name":"test"}`
	resp, err := client.Post(server.URL, "application/json", []byte(testBody))
	if err != nil {
		t.Fatalf("Post() failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		t.Errorf("Expected status 201, got %d", resp.StatusCode)
	}

	if receivedBody != testBody {
		t.Errorf("Expected body %q, got %q", testBody, receivedBody)
	}
}

// TestClient_PUT verifies PUT requests work
func TestClient_PUT(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPut {
			t.Errorf("Expected PUT, got %s", r.Method)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client, err := NewClient()
	if err != nil {
		t.Fatalf("NewClient() failed: %v", err)
	}

	resp, err := client.Put(server.URL, "application/json", []byte(`{"name":"updated"}`))
	if err != nil {
		t.Fatalf("Put() failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200, got %d", resp.StatusCode)
	}
}

// TestClient_DELETE verifies DELETE requests work
func TestClient_DELETE(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodDelete {
			t.Errorf("Expected DELETE, got %s", r.Method)
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	client, err := NewClient()
	if err != nil {
		t.Fatalf("NewClient() failed: %v", err)
	}

	resp, err := client.Delete(server.URL)
	if err != nil {
		t.Fatalf("Delete() failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent {
		t.Errorf("Expected status 204, got %d", resp.StatusCode)
	}
}
