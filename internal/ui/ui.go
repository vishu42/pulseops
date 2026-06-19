package ui

import (
	"embed"
	"io/fs"
)

//go:embed static
var files embed.FS

func Files() fs.FS {
	static, err := fs.Sub(files, "static")
	if err != nil {
		panic(err)
	}
	return static
}
