#!/bin/bash
###############################################################################
# build-win7.sh — Build cloudflared for Windows 7 32-bit (Go 1.21.13)
#
# Usage:
#   bash build-win7.sh              # auto-detect latest upstream version
#   bash build-win7.sh 2999.12.31   # use a fixed version string
#
# Patches applied to the source tree:
#   - go.mod:        go 1.22 -> 1.21, go.uber.org/mock v0.5.0 -> v0.4.0
#   - selector.go:   slices.Concat (Go 1.22+) -> manual append
#   - diagnostic.go: for range len(x) (Go 1.22+) -> classic for loop
#
# Go runtime patch (Windows 7 compatibility):
#   Go 1.21 uses bcryptprimitives.dll!ProcessPrng for random data,
#   which only exists on Windows 10+. This script patches the Go
#   runtime to fall back to advapi32.dll!SystemFunction036 (RtlGenRandom)
#   when ProcessPrng is unavailable (Windows 7).
###############################################################################
set -euo pipefail

GO_BIN="${GO_BIN:-go}"
GO_ROOT_OVERRIDE="${GOROOT:-}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"
FIXED_VERSION="${1:-}"

log()  { echo -e "\033[1;32m[build]\033[0m $*"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }
err()  { echo -e "\033[1;31m[err]\033[0m $*"; }

cd "$(dirname "$0")"

# ---------- determine version ----------
if [ -n "$FIXED_VERSION" ]; then
    VERSION="$FIXED_VERSION"
    log "Using fixed version: $VERSION"
else
    log "Fetching latest cloudflared release version from GitHub..."
    VERSION=$(git ls-remote --tags https://github.com/cloudflare/cloudflared.git 2>/dev/null \
        | grep -oP 'refs/tags/[0-9]{4}\.[0-9]+\.[0-9]+' \
        | sort -V | tail -1 | cut -d/ -f3)
    if [ -z "$VERSION" ]; then
        err "Could not fetch latest version from GitHub"
        exit 1
    fi
    log "Latest upstream version: $VERSION"
fi

# ---------- verify source patches ----------
log "Verifying source patches..."
if grep -q '^go 1\.2[2-9]' go.mod 2>/dev/null; then
    err "go.mod still requires Go 1.22+ — patches not applied!"
    exit 1
fi
if grep -q 'slices\.Concat' features/selector.go 2>/dev/null; then
    err "selector.go still uses slices.Concat — patch not applied!"
    exit 1
fi
log "  Source patches OK"

# ---------- patch Go runtime for Win7 ----------
if [ -n "$GO_ROOT_OVERRIDE" ]; then
    log "Patching Go runtime for Windows 7 ProcessPrng fallback..."
    bash patches/patch-go-runtime.sh "$GO_ROOT_OVERRIDE" || true
    "$GO_BIN" clean -cache 2>/dev/null || true
fi

# ---------- dependencies ----------
log "Downloading dependencies..."
export GOTOOLCHAIN=local
export GOSUMDB=off
export GOFLAGS="${GOFLAGS:--mod=mod}"
"${GO_BIN}" mod download 2>&1 | tail -3

# ---------- build ----------
BUILD_TIME=$(date -u '+%Y-%m-%d-%H%M UTC')
OUTPUT="${OUTPUT_DIR}/cloudflared-${VERSION}-win7-386.exe"

log "Building cloudflared $VERSION for Windows 7 32-bit..."
log "  Go:        $("${GO_BIN}" version)"
log "  BuildTime: $BUILD_TIME"

GOOS=windows GOARCH=386 CGO_ENABLED=0 "${GO_BIN}" build \
    -ldflags "-s -w -X 'main.Version=${VERSION}' -X 'main.BuildTime=${BUILD_TIME}'" \
    -o "$OUTPUT" \
    ./cmd/cloudflared/

# ---------- verify ----------
log "Verifying binary..."
file "$OUTPUT" 2>/dev/null || true
SIZE=$(du -h "$OUTPUT" | cut -f1)
log "Output: $OUTPUT ($SIZE)"

EMBEDDED=$(strings "$OUTPUT" | grep -c "$VERSION" || true)
if [ "$EMBEDDED" -gt 0 ]; then
    log "  Version '$VERSION' confirmed in binary"
else
    warn "  Version '$VERSION' not found in binary strings"
fi

log "Done!  $OUTPUT"
