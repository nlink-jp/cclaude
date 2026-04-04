BINARY  := cclaude
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
PREFIX  ?= /usr/local
DESTDIR ?=

.PHONY: build install uninstall image-build test lint check clean help

## build: Copy script and assets to dist/
build:
	@mkdir -p dist
	cp cclaude dist/$(BINARY)
	chmod +x dist/$(BINARY)
	sed -i'' -e 's/^CCC_VERSION=".*"/CCC_VERSION="$(VERSION)"/' dist/$(BINARY)
	cp Dockerfile dist/
	cp config.toml.example dist/

## install: Install to $(DESTDIR)$(PREFIX)/bin and config dir
##   Examples:
##     make install                          → /usr/local/bin/cclaude
##     make install PREFIX=$$HOME/.local     → ~/.local/bin/cclaude
##     make install DESTDIR=/tmp/staging     → /tmp/staging/usr/local/bin/cclaude
install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 dist/$(BINARY) $(DESTDIR)$(PREFIX)/bin/$(BINARY)
	@mkdir -p $(HOME)/.config/cclaude
	install -m 644 dist/Dockerfile $(HOME)/.config/cclaude/Dockerfile
	@test -f $(HOME)/.config/cclaude/config.toml || \
		install -m 644 dist/config.toml.example $(HOME)/.config/cclaude/config.toml
	@printf 'Installed %s to %s%s/bin/%s\n' "$(BINARY)" "$(DESTDIR)" "$(PREFIX)" "$(BINARY)"
	@printf 'Dockerfile: %s/.config/cclaude/Dockerfile\n' "$(HOME)"

## uninstall: Remove installed files
uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/$(BINARY)
	@printf 'Removed %s%s/bin/%s\n' "$(DESTDIR)" "$(PREFIX)" "$(BINARY)"
	@printf 'Note: %s/.config/cclaude/ left intact (contains user config).\n' "$(HOME)"

## image-build: Build the container image
image-build:
	$(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null) build -t cclaude:latest -f Dockerfile .

## test: Run shellcheck + BATS
test: lint
	bats test/

## lint: Run shellcheck
lint:
	shellcheck cclaude

## check: lint + test
check: lint test

## clean: Remove build artifacts
clean:
	rm -rf dist/

## help: Show this help
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
