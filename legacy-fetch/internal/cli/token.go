package cli

import (
	"fmt"

	"github.com/omaticsoftware/fetch/internal/auth"
	"github.com/omaticsoftware/fetch/internal/client"
	"github.com/spf13/cobra"
)

var tokenCmd = &cobra.Command{
	Use:   "token <url>",
	Short: "Authenticate and print captured credentials",
	Long: `Opens a browser to the specified URL, completes the login flow,
then prints all captured credentials (JWT from localStorage, cookies) to stdout.

Output format (one per line):
  JWT=<token>
  COOKIE=name=value; name2=value2

Use in scripts:
  TOKEN=$(fetch token https://app.example.com | grep ^JWT= | cut -d= -f2-)
  curl -H "Authorization: Bearer $TOKEN" https://api.example.com/...`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		targetURL := args[0]

		c, err := client.NewClientWithBrowser(GetBrowserType())
		if err != nil {
			return fmt.Errorf("failed to create client: %w", err)
		}

		result, err := c.AuthenticateAndCapture(targetURL)
		if err != nil {
			return fmt.Errorf("authentication failed: %w", err)
		}

		// Try to extract Auth0 JWT from localStorage
		jwt, _ := auth.ParseAuth0Token(result.LocalStorage)

		output := auth.FormatTokenOutput(jwt, result.Cookies)
		if output != "" {
			fmt.Println(output)
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(tokenCmd)
}
