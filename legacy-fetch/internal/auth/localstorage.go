package auth

import (
	"encoding/json"
	"fmt"

	"github.com/go-rod/rod"
)

// The JavaScript to enumerate all localStorage entries as a JSON object
const localStorageJS = `() => {
	const result = {};
	for (let i = 0; i < localStorage.length; i++) {
		const key = localStorage.key(i);
		result[key] = localStorage.getItem(key);
	}
	return JSON.stringify(result);
}`

// ExtractLocalStorage reads all localStorage entries from a browser page.
func ExtractLocalStorage(page *rod.Page) (map[string]string, error) {
	result, err := page.Eval(localStorageJS)
	if err != nil {
		return nil, fmt.Errorf("failed to read localStorage: %w", err)
	}

	jsonStr := result.Value.Str()
	return ParseLocalStorageJSON(jsonStr)
}

// ParseLocalStorageJSON parses the JSON string returned by the localStorage JS.
// Exported for testing without a browser.
func ParseLocalStorageJSON(jsonStr string) (map[string]string, error) {
	var entries map[string]string
	if err := json.Unmarshal([]byte(jsonStr), &entries); err != nil {
		return nil, fmt.Errorf("failed to parse localStorage JSON: %w", err)
	}
	return entries, nil
}
