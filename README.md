# bmux

Browser multiplexer — Perl, raw CDP over WebSocket. Controls Chromium-based browsers (Edge, Chrome, Brave) and Safari via CLI.

## Usage

```bash
bmux session new -s edge       # Launch browser with CDP debug port
bmux attach edge               # Attach to session
bmux goto "https://example.com"
bmux tab list
bmux tab new
bmux tab kill 2
bmux capture "button, input"   # DOM at selector
bmux capture "button" -p       # Text content only
bmux eval "document.title"
bmux fill "#username" "user@example.com"
bmux type "#search" "query"
bmux click "#submit"
bmux click "#submit" --js      # JS .click() fallback
bmux storage                   # localStorage JSON
bmux cookies                   # Cookies JSON
bmux session list
bmux session kill edge
```

## WSL Setup

bmux in WSL controls Edge running on Windows. Since Edge binds to `127.0.0.1` which isn't directly reachable from WSL, a `netsh` portproxy bridges the gap.

### One-time setup (elevated PowerShell)

```powershell
# Port proxy: forward 0.0.0.0:19222 -> 127.0.0.1:9222
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=19222 connectaddress=127.0.0.1 connectport=9222

# Firewall rule to allow traffic on the proxy port
netsh advfirewall firewall add rule name="CDP Debug Port" dir=in action=allow protocol=TCP localport=19222

# Allow WSL inbound traffic through Hyper-V firewall
# NOTE: this resets on WSL restart — add to a startup script if needed
Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow
```

### How it works

1. bmux launches Windows Edge with `--remote-debugging-port=9222`
2. Edge listens on `127.0.0.1:9222` (Windows loopback)
3. `netsh portproxy` forwards `0.0.0.0:19222` to `127.0.0.1:9222`
4. bmux connects from WSL via the default gateway IP on port 19222
5. WebSocket URLs from CDP already reflect the proxy port, so no rewriting needed

### Troubleshooting

- **"Browser did not start"**: Edge may have stray processes. bmux kills them automatically, but if Edge auto-restarts, close it manually first.
- **Connection timeout**: Check that the Hyper-V firewall default inbound is set to Allow (resets on WSL restart).
- **Port conflict**: The portproxy must use a different port than Edge (19222 vs 9222) to avoid bind conflicts.
