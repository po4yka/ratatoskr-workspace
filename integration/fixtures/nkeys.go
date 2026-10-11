package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"

	"github.com/nats-io/nkeys"
)

var identity = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)

// Writes NAME.nkey (the seed, mode 0600) and NAME.public (the public key) into OUTPUT_DIR for
// every NAME given. Used by integration/lib/nats-conf.sh to key the deployed NATS configuration.
func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: nkeys OUTPUT_DIR NAME...")
		os.Exit(2)
	}
	root := os.Args[1]
	if err := os.MkdirAll(root, 0o700); err != nil {
		panic(err)
	}
	for _, name := range os.Args[2:] {
		if !identity.MatchString(name) {
			fmt.Fprintf(os.Stderr, "identity names are lower case words, got %q\n", name)
			os.Exit(2)
		}
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
