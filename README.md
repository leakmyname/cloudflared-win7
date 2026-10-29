# Cloudflare Tunnel client

---

## Windows 7 32-bit Build (This Fork)

This fork builds `cloudflared` for **Windows 7 32-bit** using **Go 1.21.13** (the last Go release supporting Win7). The upstream cloudflared now requires Go 1.27+ and only targets Windows 10+.

### What this fork changes

1. **Source patches** (Go 1.21 compatibility, already applied in this repo):
   - `go.mod`: `go 1.22` -> `go 1.21`, `go.uber.org/mock` v0.5.0 -> v0.4.0
   - `features/selector.go`: `slices.Concat` (Go 1.22+) replaced with manual `append`
   - `diagnostic/diagnostic.go`: `for range len(x)` (Go 1.22+) replaced with classic `for` loop
   - `features/features.go` + `features/selector.go`: `slices.Contains` replaced with local helper (avoids `slices` stdlib dependency)

2. **Go runtime patch** (`patches/patch-go-runtime.sh`):
   - Go 1.21 uses `bcryptprimitives.dll!ProcessPrng` for random data, which only exists on Windows 10+
   - On Windows 7 the function pointer is nil, causing a crash at `PC=0x0` in `runtime.asmstdcall`
   - The patch adds a fallback to `advapi32.dll!SystemFunction036` (aka `RtlGenRandom`), same as Go 1.20
   - **This does not weaken security**: `RtlGenRandom` is a cryptographically secure PRNG backed by the same OS entropy pool. Go 1.20 and all earlier versions used it on Windows. The fallback only activates on Win7; Win10+ still uses `ProcessPrng`

3. **Version injection**: The version string is injected via `-ldflags -X 'main.Version=...'`. The actual codebase is cloudflared `2025.5.0` + cherry-pick of TUN-9171. The version string does not affect tunnel security -- it is a plain string with no signature verification by Cloudflare edge servers.

### Build

```bash
# Auto-detect latest upstream version
bash build-win7.sh

# Fixed version (e.g. far-future to suppress auto-update prompts)
bash build-win7.sh 2999.12.31
```

The script expects Go 1.21.13 on PATH (or set `GO_BIN=/path/to/go`). Set `GOROOT` to have the runtime patch applied automatically.

### GitHub Actions

Two workflows are included in `.github/workflows/`:
- `build-win7-latest.yml` -- injects the latest upstream version, builds Win7 32-bit
- `build-win7-fixed.yml` -- injects `2999.12.31`, builds Win7 32-bit

Both patch the Go runtime in CI before building. Artifacts are uploaded automatically.

### Security notes

- **Codebase is 2025.5.0**: security fixes in later cloudflared releases are not included. This is the main risk, larger than the runtime patch.
- **Go 1.21.13**: last release of the Go 1.21 branch, includes all 1.21 security fixes. Does not include Go 1.22+ fixes.
- **Version `2999.12.31`**: suppresses auto-update prompts on Win7 (update server sees a "future" version). Does not affect tunnel encryption or authentication.
- **`RtlGenRandom` fallback**: cryptographically equivalent to `ProcessPrng`. No entropy reduction, no weaker algorithm.

### Base version info

| Component | Version |
|---|---|
| cloudflared codebase | 2025.5.0 + cherry-pick e144eac2 (TUN-9171) |
| Go toolchain | 1.21.13 (patched runtime) |
| Target | `GOOS=windows GOARCH=386 CGO_ENABLED=0` (PE32 Intel 80386) |
| Version string | injected via ldflags (latest or 2999.12.31) |

---

Contains the command-line client for Cloudflare Tunnel, a tunneling daemon that proxies traffic from the Cloudflare network to your origins.
This daemon sits between Cloudflare network and your origin (e.g. a webserver). Cloudflare attracts client requests and sends them to you
via this daemon, without requiring you to poke holes on your firewall --- your origin can remain as closed as possible.
Extensive documentation can be found in the [Cloudflare Tunnel section](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps) of the Cloudflare Docs.
All usages related with proxying to your origins are available under `cloudflared tunnel help`.

You can also use `cloudflared` to access Tunnel origins (that are protected with `cloudflared tunnel`) for TCP traffic
at Layer 4 (i.e., not HTTP/websocket), which is relevant for use cases such as SSH, RDP, etc.
Such usages are available under `cloudflared access help`.

You can instead use [WARP client](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/private-networks)
to access private origins behind Tunnels for Layer 4 traffic without requiring `cloudflared access` commands on the client side.


## Before you get started

Before you use Cloudflare Tunnel, you'll need to complete a few steps in the Cloudflare dashboard: you need to add a
website to your Cloudflare account. Note that today it is possible to use Tunnel without a website (e.g. for private
routing), but for legacy reasons this requirement is still necessary:
1. [Add a website to Cloudflare](https://support.cloudflare.com/hc/en-us/articles/201720164-Creating-a-Cloudflare-account-and-adding-a-website)
2. [Change your domain nameservers to Cloudflare](https://support.cloudflare.com/hc/en-us/articles/205195708)


## Installing `cloudflared`

Downloads are available as standalone binaries, a Docker image, and Debian, RPM, and Homebrew packages. You can also find releases [here](https://github.com/cloudflare/cloudflared/releases) on the `cloudflared` GitHub repository.

* You can [install on macOS](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation#macos) via Homebrew or by downloading the [latest Darwin amd64 release](https://github.com/cloudflare/cloudflared/releases)
* Binaries, Debian, and RPM packages for Linux [can be found here](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation#linux)
* A Docker image of `cloudflared` is [available on DockerHub](https://hub.docker.com/r/cloudflare/cloudflared)
* You can install on Windows machines with the [steps here](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation#windows)
* To build from source, first you need to download the go toolchain by running `./.teamcity/install-cloudflare-go.sh` and follow the output. Then you can run `make cloudflared`

User documentation for Cloudflare Tunnel can be found at https://developers.cloudflare.com/cloudflare-one/connections/connect-apps


## Creating Tunnels and routing traffic

Once installed, you can authenticate `cloudflared` into your Cloudflare account and begin creating Tunnels to serve traffic to your origins.

* Create a Tunnel with [these instructions](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/)
* Route traffic to that Tunnel:
  * Via public [DNS records in Cloudflare](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/routing-to-tunnel/dns)
  * Or via a public hostname guided by a [Cloudflare Load Balancer](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/routing-to-tunnel/lb)
  * Or from [WARP client private traffic](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/private-net/)


## TryCloudflare

Want to test Cloudflare Tunnel before adding a website to Cloudflare? You can do so with TryCloudflare using the documentation [available here](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/trycloudflare/).

## Deprecated versions

Cloudflare currently supports versions of cloudflared that are **within one year** of the most recent release. Breaking changes unrelated to feature availability may be introduced that will impact versions released more than one year ago. You can read more about upgrading cloudflared in our [developer documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/#updating-cloudflared).

For example, as of January 2023 Cloudflare will support cloudflared version 2023.1.1 to cloudflared 2022.1.1.

## Development

### Requirements
- [GNU Make](https://www.gnu.org/software/make/)
- [capnp](https://capnproto.org/install.html)
- [cloudflare go toolchain](https://github.com/cloudflare/go)
- Optional tools:
  - [capnpc-go](https://pkg.go.dev/zombiezen.com/go/capnproto2/capnpc-go)
  - [goimports](https://pkg.go.dev/golang.org/x/tools/cmd/goimports)
  - [golangci-lint](https://github.com/golangci/golangci-lint)
  - [gomocks](https://pkg.go.dev/go.uber.org/mock)

### Build
To build cloudflared locally run `make cloudflared`

### Test
To locally run the tests run `make test`

### Linting
To format the code and keep a good code quality use `make fmt` and `make lint`

### Mocks
After changes on interfaces you might need to regenerate the mocks, so run `make mock`
