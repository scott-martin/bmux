package auth

import (
	"testing"
)

func TestParseLocalStorageJSON_Valid(t *testing.T) {
	input := `{"key1":"value1","@@auth0spajs@@::client::aud::scope":"{\"body\":{\"access_token\":\"tok\"}}"}`

	result, err := ParseLocalStorageJSON(input)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
	if len(result) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(result))
	}
	if result["key1"] != "value1" {
		t.Errorf("expected key1=value1, got %s", result["key1"])
	}
}

func TestParseLocalStorageJSON_Empty(t *testing.T) {
	result, err := ParseLocalStorageJSON(`{}`)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
	if len(result) != 0 {
		t.Fatalf("expected 0 entries, got %d", len(result))
	}
}

func TestParseLocalStorageJSON_Malformed(t *testing.T) {
	_, err := ParseLocalStorageJSON(`{not json`)
	if err == nil {
		t.Fatal("expected error on malformed JSON")
	}
}
