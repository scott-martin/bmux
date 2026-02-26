package auth

import (
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestParseAuth0Token_ValidEntry(t *testing.T) {
	localStorage := map[string]string{
		"@@auth0spajs@@::XpGXs7Hz7ay1KmDeXHMTIju4TZlje2OB::https://webbackend.omaticcloud.io::openid profile email": `{
			"body": {
				"access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.test",
				"expires_in": 86400,
				"token_type": "Bearer"
			},
			"expiresAt": 1740600000
		}`,
	}

	token, err := ParseAuth0Token(localStorage)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
	if token != "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.test" {
		t.Errorf("expected token to match, got: %s", token)
	}
}

func TestParseAuth0Token_FindsKeyAmongOthers(t *testing.T) {
	localStorage := map[string]string{
		"some_other_key":        "some_value",
		"another_key":           `{"foo": "bar"}`,
		"@@auth0spajs@@::abc::https://api.example.com::openid": `{
			"body": {
				"access_token": "my-jwt-token",
				"expires_in": 3600,
				"token_type": "Bearer"
			},
			"expiresAt": 9999999999
		}`,
		"yet_another_key": "123",
	}

	token, err := ParseAuth0Token(localStorage)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
	if token != "my-jwt-token" {
		t.Errorf("expected 'my-jwt-token', got: %s", token)
	}
}

func TestParseAuth0Token_NoAuth0Keys(t *testing.T) {
	localStorage := map[string]string{
		"some_key":    "some_value",
		"another_key": "another_value",
	}

	_, err := ParseAuth0Token(localStorage)
	if err == nil {
		t.Fatal("expected error when no Auth0 keys found")
	}
}

func TestParseAuth0Token_NoAccessToken(t *testing.T) {
	localStorage := map[string]string{
		"@@auth0spajs@@::client::audience::scope": `{
			"body": {
				"expires_in": 86400,
				"token_type": "Bearer"
			},
			"expiresAt": 1740600000
		}`,
	}

	_, err := ParseAuth0Token(localStorage)
	if err == nil {
		t.Fatal("expected error when no access_token in entry")
	}
}

func TestParseAuth0Token_MalformedJSON(t *testing.T) {
	localStorage := map[string]string{
		"@@auth0spajs@@::client::audience::scope": `{not valid json`,
	}

	_, err := ParseAuth0Token(localStorage)
	if err == nil {
		t.Fatal("expected error on malformed JSON")
	}
}

func TestFormatTokenOutput_BothPresent(t *testing.T) {
	jwt := "eyJhbGciOiJSUzI1NiJ9.test"
	cookies := []*http.Cookie{
		{Name: "session", Value: "abc123"},
		{Name: "pref", Value: "dark"},
	}

	output := FormatTokenOutput(jwt, cookies)

	if !strings.Contains(output, "JWT=eyJhbGciOiJSUzI1NiJ9.test") {
		t.Errorf("expected JWT line in output, got:\n%s", output)
	}
	if !strings.Contains(output, "COOKIE=session=abc123; pref=dark") {
		t.Errorf("expected COOKIE line in output, got:\n%s", output)
	}
}

func TestFormatTokenOutput_JWTOnly(t *testing.T) {
	output := FormatTokenOutput("my-token", nil)

	if !strings.Contains(output, "JWT=my-token") {
		t.Errorf("expected JWT line, got:\n%s", output)
	}
	if strings.Contains(output, "COOKIE=") {
		t.Error("expected no COOKIE line when cookies are nil")
	}
}

func TestFormatTokenOutput_CookiesOnly(t *testing.T) {
	cookies := []*http.Cookie{
		{Name: "sid", Value: "xyz"},
	}

	output := FormatTokenOutput("", cookies)

	if strings.Contains(output, "JWT=") {
		t.Error("expected no JWT line when jwt is empty")
	}
	if !strings.Contains(output, "COOKIE=sid=xyz") {
		t.Errorf("expected COOKIE line, got:\n%s", output)
	}
}

func TestFormatTokenOutput_NeitherPresent(t *testing.T) {
	output := FormatTokenOutput("", nil)

	if output != "" {
		t.Errorf("expected empty output, got:\n%s", output)
	}
}

// Ensure time import is used (for future expiry tests)
var _ = time.Now
