package cli

import (
	"fmt"

	"github.com/omaticsoftware/fetch/internal/client"
	"github.com/spf13/cobra"
)

// authCmd represents the auth command
var authCmd = &cobra.Command{
	Use:   "auth <url>",
	Short: "Force re-authentication for a URL",
	Long: `Force browser-based authentication for the specified URL.
This will clear any existing cached session for the host and
trigger a new browser authentication flow.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		targetURL := args[0]

		c, err := client.NewClientWithBrowser(GetBrowserType())
		if err != nil {
			return fmt.Errorf("failed to create client: %w", err)
		}

		fmt.Printf("Authenticating to %s...\n", targetURL)
		if err := c.Authenticate(targetURL); err != nil {
			return fmt.Errorf("authentication failed: %w", err)
		}

		fmt.Println("Authentication successful!")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(authCmd)
}
