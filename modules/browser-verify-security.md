# browser-verify-security

URL security constraints for browser verification commands and HTTP commands.

## Purpose

Centrally manages URL security constraints (SSRF prevention) for browser verification commands (`browser_check` / `browser_screenshot`) and HTTP commands (`http_status`).

Callers: `skills/issue/SKILL.md`, `skills/verify/SKILL.md`, `modules/verify-executor.md`, `modules/browser-adapter.md`

## Input

- URL string to verify

## Processing Steps

Execute the following checks in order. If any applies, treat as UNCERTAIN and include detailed reason.

1. **Scheme check (SSRF prevention)**: Only `http://` and `https://` schemes are allowed. Reject `file://`, `ftp://`, and all other schemes.

2. **Internal address check**: Reject internal-facing addresses. However, `localhost` and `127.0.0.1` are permitted as exceptions for local development server use.

   **Permitted (exceptions):**
   - `localhost` — allowed for browser verification with local dev servers
   - `127.0.0.1` — same (allowed as loopback address)

   **Rejected (target patterns):**
   - `10.*` (private network)
   - `192.168.*` (private network)
   - `172.16.*` to `172.31.*` (private network)
   - `*.local` (mDNS)
   - Other internal IP addresses

3. **Check passed**: If none of the above applies, allow the URL.

## http_status URL Security Policy

`http_status` command is HTTP GET only (read-only), so applying URL security check allows execution even in safe mode.

### Mode-Based Policy Table

| Mode | localhost/Private IP | External URL | Reason |
|------|---------------------|-------------|--------|
| safe | **Block → UNCERTAIN** | Allowed (execute with curl) | SSRF prevention (verify commands in Issue body are untrusted input) |
| full | Allowed | Allowed (execute with curl) | Local dev server verification may be needed |

### Addresses to Block in safe Mode

Only block the following addresses in safe mode and return UNCERTAIN. No restrictions in full mode.

- `127.0.0.0/8` (localhost)
- `169.254.169.254` (cloud metadata endpoint)
- `10.0.0.0/8` (private IP class A)
- `172.16.0.0/12` (private IP class B)
- `192.168.0.0/16` (private IP class C)
- `::1` (IPv6 localhost)
- `fc00::/7` (IPv6 unique local addresses)

### `--allow-localhost` Opt-in

When `--allow-localhost` is present in the verify command, `127.0.0.0/8` (localhost) is permitted even in safe mode. All other addresses in the block list (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, cloud metadata endpoints, IPv6 private ranges) remain blocked regardless of this flag.

| Flag | safe mode localhost | Other private IPs |
|------|--------------------|--------------------|
| (none) | **Block → UNCERTAIN** | Block → UNCERTAIN |
| `--allow-localhost` | **Allowed** | Block → UNCERTAIN |

This is an explicit opt-in: the caller must deliberately add `--allow-localhost` to enable localhost access. The flag has no effect in full mode (full mode already allows all addresses).

### Handling Preview URLs from Deployments API

Preview URLs obtained from the GitHub Deployments API (`gh api repos/:owner/:repo/deployments`) are from GitHub's trusted service data, not from Issue body (external input), so they are not subject to the safe mode restriction "return UNCERTAIN for Issue-body-derived URLs".

- Preview URLs obtained from Deployments API during `/review` phase → browser verification may be executed even in safe mode
- URLs written in Issue body (external input derived) → return UNCERTAIN in safe mode as before

**However, the scheme check (only `http/https` allowed) and internal address check (reject `10.*`, `192.168.*`, etc.) still apply to Deployments API-derived URLs.** The safe mode exception only covers "do not execute unknown URLs from Issue body directly"; it does not bypass URL security checks themselves.

This distinction allows `/review` to safely perform automated browser verification in preview environments.

## Output

- **Allowed**: URL meets security constraints; browser verification may proceed
- **Rejected (UNCERTAIN)**: URL does not meet security constraints. Include detailed reason (e.g., "URL contains internal address `127.0.0.1`, returning UNCERTAIN")
