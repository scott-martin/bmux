package main

import (
	"fmt"
	"os"

	"github.com/omaticsoftware/fetch/internal/cli"
)

var version = "0.1.0"

func main() {
	if len(os.Args) > 1 && (os.Args[1] == "--version" || os.Args[1] == "-v") {
		fmt.Printf("fetch version %s\n", version)
		os.Exit(0)
	}

	if err := cli.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
