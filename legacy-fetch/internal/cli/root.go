package cli

import (
	"github.com/omaticsoftware/fetch/internal/auth"
	"github.com/spf13/cobra"
)

var browserFlag string

var rootCmd = &cobra.Command{
	Use:   "fetch",
	Short: "Authenticated HTTP client for MS-authenticated sites",
	Long: `fetch makes authenticated HTTP requests to any MS-authenticated site.
It automatically handles browser-based authentication and caches sessions.

Use --browser to select which browser to use:
  edge   - Microsoft Edge (default, good for work/SSO)
  chrome - Google Chrome (good for personal accounts)`,
	SilenceUsage:  true,
	SilenceErrors: true,
}

func Execute() error {
	return rootCmd.Execute()
}

func init() {
	rootCmd.Version = "0.1.0"
	rootCmd.PersistentFlags().StringVarP(&browserFlag, "browser", "b", "edge", "Browser to use (edge, chrome)")
}

// GetBrowserType returns the browser type from the flag
func GetBrowserType() auth.BrowserType {
	switch browserFlag {
	case "chrome":
		return auth.BrowserChrome
	default:
		return auth.BrowserEdge
	}
}
