package cli

import (
	"fmt"

	"github.com/omaticsoftware/fetch/internal/client"
	"github.com/spf13/cobra"
)

// statusCmd represents the status command
var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "List cached authentication sessions",
	Long:  `List all cached authentication sessions stored on disk.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := client.NewClient()
		if err != nil {
			return fmt.Errorf("failed to create client: %w", err)
		}

		sessions, err := c.ListSessions()
		if err != nil {
			return fmt.Errorf("failed to list sessions: %w", err)
		}

		if len(sessions) == 0 {
			fmt.Println("No cached sessions found.")
			return nil
		}

		fmt.Printf("Cached sessions (%d):\n", len(sessions))
		for _, host := range sessions {
			fmt.Printf("  - %s\n", host)
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(statusCmd)
}
