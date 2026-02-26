package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"

	"github.com/omaticsoftware/fetch/internal/auth"
	"github.com/omaticsoftware/fetch/internal/client"
	"github.com/spf13/cobra"
)

var dataFlag string

// getCmd represents the GET command
var getCmd = &cobra.Command{
	Use:   "GET <url>",
	Short: "Perform a GET request",
	Long:  `Perform an authenticated GET request to the specified URL.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		targetURL := args[0]

		c, err := client.NewClientWithBrowser(GetBrowserType())
		if err != nil {
			return fmt.Errorf("failed to create client: %w", err)
		}

		resp, err := c.GetWithAuth(targetURL)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer resp.Body.Close()

		return printResponse(resp)
	},
}

// postCmd represents the POST command
var postCmd = &cobra.Command{
	Use:   "POST <url>",
	Short: "Perform a POST request",
	Long:  `Perform an authenticated POST request to the specified URL.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		targetURL := args[0]

		var body []byte
		if dataFlag != "" {
			body = []byte(dataFlag)
		}

		c, err := client.NewClientWithBrowser(GetBrowserType())
		if err != nil {
			return fmt.Errorf("failed to create client: %w", err)
		}

		// Default to JSON content type if data is provided
		contentType := ""
		if len(body) > 0 {
			contentType = "application/json"
		}

		resp, err := c.PostWithAuth(targetURL, contentType, body)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer resp.Body.Close()

		return printResponse(resp)
	},
}

// putCmd represents the PUT command
var putCmd = &cobra.Command{
	Use:   "PUT <url>",
	Short: "Perform a PUT request",
	Long:  `Perform an authenticated PUT request to the specified URL.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		targetURL := args[0]

		var body []byte
		if dataFlag != "" {
			body = []byte(dataFlag)
		}

		c, err := client.NewClientWithBrowser(GetBrowserType())
		if err != nil {
			return fmt.Errorf("failed to create client: %w", err)
		}

		// Default to JSON content type if data is provided
		contentType := ""
		if len(body) > 0 {
			contentType = "application/json"
		}

		// PUT needs the same auto-auth logic as POST
		// For now, we'll use a similar pattern
		parsedURL, err := parseURL(targetURL)
		if err != nil {
			return err
		}

		host := parsedURL.Host
		cookies, err := loadCookiesForHost(c, host)
		if err != nil {
			return err
		}

		// If no session exists, trigger authentication
		if len(cookies) == 0 {
			fmt.Printf("No session found for %s, triggering authentication...\n", host)
			if err := c.Authenticate(targetURL); err != nil {
				return fmt.Errorf("authentication failed: %w", err)
			}
		}

		resp, err := c.Put(targetURL, contentType, body)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer resp.Body.Close()

		// Handle 401 by re-authenticating
		if resp.StatusCode == 401 {
			fmt.Printf("Session expired for %s, re-authenticating...\n", host)
			resp.Body.Close()

			if err := c.Authenticate(targetURL); err != nil {
				return fmt.Errorf("re-authentication failed: %w", err)
			}

			// Retry
			resp, err = c.Put(targetURL, contentType, body)
			if err != nil {
				return fmt.Errorf("retry request failed: %w", err)
			}
			defer resp.Body.Close()
		}

		return printResponse(resp)
	},
}

// deleteCmd represents the DELETE command
var deleteCmd = &cobra.Command{
	Use:   "DELETE <url>",
	Short: "Perform a DELETE request",
	Long:  `Perform an authenticated DELETE request to the specified URL.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		targetURL := args[0]

		c, err := client.NewClientWithBrowser(GetBrowserType())
		if err != nil {
			return fmt.Errorf("failed to create client: %w", err)
		}

		// DELETE needs the same auto-auth logic
		parsedURL, err := parseURL(targetURL)
		if err != nil {
			return err
		}

		host := parsedURL.Host
		cookies, err := loadCookiesForHost(c, host)
		if err != nil {
			return err
		}

		// If no session exists, trigger authentication
		if len(cookies) == 0 {
			fmt.Printf("No session found for %s, triggering authentication...\n", host)
			if err := c.Authenticate(targetURL); err != nil {
				return fmt.Errorf("authentication failed: %w", err)
			}
		}

		resp, err := c.Delete(targetURL)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer resp.Body.Close()

		// Handle 401 by re-authenticating
		if resp.StatusCode == 401 {
			fmt.Printf("Session expired for %s, re-authenticating...\n", host)
			resp.Body.Close()

			if err := c.Authenticate(targetURL); err != nil {
				return fmt.Errorf("re-authentication failed: %w", err)
			}

			// Retry
			resp, err = c.Delete(targetURL)
			if err != nil {
				return fmt.Errorf("retry request failed: %w", err)
			}
			defer resp.Body.Close()
		}

		return printResponse(resp)
	},
}

func init() {
	rootCmd.AddCommand(getCmd)
	rootCmd.AddCommand(postCmd)
	rootCmd.AddCommand(putCmd)
	rootCmd.AddCommand(deleteCmd)

	// Add --data flag for POST and PUT
	postCmd.Flags().StringVarP(&dataFlag, "data", "d", "", "Request body data")
	putCmd.Flags().StringVarP(&dataFlag, "data", "d", "", "Request body data")
}

// printResponse prints the HTTP response with pretty-printed JSON if applicable
func printResponse(resp *http.Response) error {
	// Print status line
	fmt.Printf("%s %s\n", resp.Proto, resp.Status)

	// Print headers
	for name, values := range resp.Header {
		for _, value := range values {
			fmt.Printf("%s: %s\n", name, value)
		}
	}
	fmt.Println()

	// Read body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response body: %w", err)
	}

	// Try to pretty-print JSON
	if isJSONResponse(resp) && len(body) > 0 {
		var jsonData interface{}
		if err := json.Unmarshal(body, &jsonData); err == nil {
			// Successfully parsed as JSON, pretty-print it
			prettyJSON, err := json.MarshalIndent(jsonData, "", "  ")
			if err == nil {
				fmt.Println(string(prettyJSON))
				return nil
			}
		}
	}

	// Not JSON or failed to parse, print as-is
	fmt.Println(string(body))
	return nil
}

// isJSONResponse checks if the response content type is JSON
func isJSONResponse(resp *http.Response) bool {
	contentType := resp.Header.Get("Content-Type")
	return containsString(contentType, "application/json") ||
		containsString(contentType, "text/json")
}

// containsString checks if a string contains a substring (case-insensitive)
func containsString(s, substr string) bool {
	return len(s) >= len(substr) &&
		(s == substr || findSubstring(s, substr))
}

func findSubstring(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

// Helper functions for PUT/DELETE auth logic
func parseURL(targetURL string) (*url.URL, error) {
	parsedURL, err := url.Parse(targetURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse URL: %w", err)
	}
	return parsedURL, nil
}

func loadCookiesForHost(c *client.Client, host string) ([]*http.Cookie, error) {
	// This is a bit hacky - we need to access the session manager
	// In a real implementation, we might expose a method on Client to check for sessions
	// For now, we'll just try to load cookies directly by creating a new session manager
	sessionManager, err := auth.NewSessionManager()
	if err != nil {
		return nil, fmt.Errorf("failed to create session manager: %w", err)
	}
	return sessionManager.LoadCookies(host)
}
