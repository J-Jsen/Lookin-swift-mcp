# Lookin-swift-mcp

A Swift MCP server that talks directly to the **official** LookinServer
(`pod 'LookinServer'`) — no Lookin.app, no special iOS fork.

> **Prerequisite (iOS side):** your app must integrate the official
> [LookinServer](https://github.com/QMUI/LookinServer) in Debug builds —
> `pod 'LookinServer', :configurations => ['Debug']` (Swift projects:
> `:subspecs => ['Swift']`) — and be running in the foreground. Without it there
> is nothing for this server to connect to.

It plays the role Lookin.app plays: connects to the LookinServer that the iOS
app embeds, speaks its Peertalk framing, and decodes its `NSKeyedArchiver`
payloads. Because this is written in Swift, decoding uses Foundation's native
`NSKeyedUnarchiver` instead of reimplementing Apple's archive format by hand.

```
AI agent (Claude Code / Cursor / ...)
    ↓ stdio (MCP, newline-delimited JSON-RPC)
lookin-swift (this, Swift)
    ├─ simulator: TCP 127.0.0.1:47164-47169
    └─ USB device: usbmux (/var/run/usbmuxd) → device :47175-47179
         ↓ Peertalk frames + NSKeyedArchiver
LookinServer (embedded in the iOS app, official pod)
```

Connection is auto-detected: a booted simulator is tried first, then the first
USB-connected device via usbmux.

## Requirements

- macOS 13+, Swift 5.9+
- iOS app with the **official** `pod 'LookinServer', :configurations => ['Debug']`,
  running in the foreground in a booted simulator **or** on a USB-connected,
  trusted device.

## Install

### Option A — prebuilt (no Xcode/Swift needed)

One command downloads the latest release binary to `~/.lookin-swift/lookin-swift`,
clears the Gatekeeper quarantine flag, runs the self-test, and prints the config:

```bash
curl -fsSL https://raw.githubusercontent.com/J-Jsen/Lookin-swift-mcp/master/install-release.sh | bash
```

The binary is an **unsigned universal** (arm64 + x86_64) Mach-O; the script
`xattr`-clears the quarantine so macOS will run it. To do it by hand instead:

```bash
mkdir -p ~/.lookin-swift
curl -fsSL https://github.com/J-Jsen/Lookin-swift-mcp/releases/latest/download/lookin-swift -o ~/.lookin-swift/lookin-swift
chmod +x ~/.lookin-swift/lookin-swift
xattr -dr com.apple.quarantine ~/.lookin-swift/lookin-swift
```

### Option B — build from source

Builds and installs to the same stable path, then runs the self-test. Use this
if you change the Swift code:

```bash
./install.sh
```

## Register with an MCP client

After installing, point your client at the installed binary
`~/.lookin-swift/lookin-swift` (use the absolute path — most clients don't expand `~`).

**Claude Code** — `claude mcp add`:

```bash
claude mcp add --scope user lookin-swift ~/.lookin-swift/lookin-swift
```

…or edit `~/.claude.json` directly:

```jsonc
// mcpServers
"lookin-swift": {
  "command": "/Users/you/.lookin-swift/lookin-swift",
  "type": "stdio"
}
```

**Cursor** — `~/.cursor/mcp.json` (global) or `.cursor/mcp.json` (project):

```json
{
  "mcpServers": {
    "lookin-swift": {
      "command": "/Users/you/.lookin-swift/lookin-swift"
    }
  }
}
```

**Codex** — `~/.codex/config.toml`:

```toml
[mcp_servers.lookin-swift]
command = "/Users/you/.lookin-swift/lookin-swift"
```

**Claude Desktop** — `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "lookin-swift": {
      "command": "/Users/you/.lookin-swift/lookin-swift"
    }
  }
}
```

## Tools

| Tool | Status |
|------|--------|
| `lookin_get_hierarchy` | ✅ view tree: `oid` (layer), `viewOid`, `className`, `frame`, `hidden`, `alpha`, `children` — verified live |
| `lookin_get_screenshot` | ✅ per-view PNG via HierarchyDetails(203) — verified live |
| `lookin_get_attributes` | ✅ attribute groups/sections with typed values (numbers, strings, CGRect/CGPoint/insets arrays, UIColor rgba) — verified live |
| `lookin_modify_attribute` | ✅ live setter on a view/layer (InbuiltAttrModification 204): BOOL/number/string/CGPoint/CGSize/CGRect/UIColor — verified live |
| `lookin_list_devices` | ✅ booted simulators + USB devices |
| `lookin_connect_device` | ✅ select target: a UDID, `simulator`, or `auto` |

For `modify_attribute`, use `viewOid` for UIView setters (`setAlpha:`, `setHidden:`),
and `oid` (layer) for CALayer setters (`setCornerRadius:`). Debug helper:
`lookin-swift --devices` lists USB devices seen via usbmux.

`oid` in the hierarchy is the **layer** oid: screenshot(203) and attributes(210)
resolve it to a `CALayer` server-side, so a view oid would fail. The base
`Hierarchy(202)` response is built `itemsWithScreenshots:NO attrList:NO`, so
screenshots/attributes come from the separate HierarchyDetails(203) flow.

## Self-test

Validates framing + archive encode/decode offline (no device needed):

```bash
swift build && .build/debug/lookin-swift --selftest
```

## Scope notes

- Simulator and USB devices are both supported (auto-detected). If multiple
  devices are attached, the first one is used.
- `get_hierarchy` is verified end-to-end against a real device; framing and
  archive decode also have an offline self-test.
