package cli

import (
	"fmt"
	"time"

	"github.com/go-rod/rod"
	"github.com/go-rod/rod/lib/launcher"
	"github.com/spf13/cobra"
)

var inspectCmd = &cobra.Command{
	Use:   "inspect <url>",
	Short: "Navigate to URL and dump page structure (buttons, links, HTML)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		targetURL := args[0]

		fmt.Println("Connecting to browser...")
		u, err := launcher.ResolveURL("localhost:9222")
		if err != nil {
			fmt.Println("No existing browser, launching Edge...")
			edgePath := `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`
			l := launcher.New().Bin(edgePath).Headless(false)
			u = l.MustLaunch()
		}

		browser := rod.New().ControlURL(u)
		if err := browser.Connect(); err != nil {
			return fmt.Errorf("failed to connect: %w", err)
		}

		page := browser.MustPage(targetURL)
		defer page.MustClose()

		fmt.Println("Waiting 5 seconds for page to load...")
		time.Sleep(5 * time.Second)

		info, _ := page.Info()
		if info != nil {
			fmt.Printf("URL: %s\n", info.URL)
			fmt.Printf("Title: %s\n", info.Title)
		}

		html, err := page.HTML()
		if err != nil {
			return fmt.Errorf("failed to get HTML: %w", err)
		}

		fmt.Println("\n--- BUTTONS ---")
		buttons, _ := page.Elements("button")
		for i, btn := range buttons {
			text, _ := btn.Text()
			id, _ := btn.Attribute("id")
			class, _ := btn.Attribute("class")
			idStr, classStr := "", ""
			if id != nil { idStr = *id }
			if class != nil { classStr = *class }
			fmt.Printf("[%d] text=%q id=%q class=%q\n", i, text, idStr, classStr)
		}

		fmt.Println("\n--- LINKS ---")
		links, _ := page.Elements("a")
		for i, link := range links {
			text, _ := link.Text()
			href, _ := link.Attribute("href")
			hrefStr := ""
			if href != nil { hrefStr = *href }
			fmt.Printf("[%d] text=%q href=%q\n", i, text, hrefStr)
		}

		fmt.Println("\n--- HTML (first 5000 chars) ---")
		if len(html) > 5000 {
			fmt.Println(html[:5000])
			fmt.Printf("\n... (%d more bytes)\n", len(html)-5000)
		} else {
			fmt.Println(html)
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(inspectCmd)
}
