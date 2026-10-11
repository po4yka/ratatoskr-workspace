package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/nats-io/nkeys"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: export-agent-product-nkeys OUTPUT_DIR")
		os.Exit(2)
	}
	root := os.Args[1]
	if err := os.MkdirAll(root, 0o700); err != nil {
		panic(err)
	}
	for _, name := range []string{"edge", "chatgpt", "claude"} {
		pair, err := nkeys.CreateUser()
		if err != nil {
			panic(err)
		}
		seed, err := pair.Seed()
		if err != nil {
			panic(err)
		}
		public, err := pair.PublicKey()
		if err != nil {
			panic(err)
		}
		if err := os.WriteFile(filepath.Join(root, name+".nkey"), append(seed, '\n'), 0o600); err != nil {
			panic(err)
		}
		if err := os.WriteFile(filepath.Join(root, name+".public"), []byte(public+"\n"), 0o600); err != nil {
			panic(err)
		}
	}
}
