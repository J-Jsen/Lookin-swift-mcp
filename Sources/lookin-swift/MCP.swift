import Foundation

/// Minimal MCP server over stdio.
///
/// MCP's stdio transport is newline-delimited JSON-RPC 2.0: each line on stdin
/// is one request object, each response is one line on stdout. That is simple
/// enough to hand-roll, so we avoid pulling in an SDK (keeps the package
/// dependency-free and offline-buildable).
///
/// ponytail: implements exactly the three methods a tool server needs —
/// initialize, tools/list, tools/call — plus the initialized notification.
/// Anything else gets a "method not found" error.

struct Tool {
    let name: String
    let description: String
    /// JSON schema for the tool's arguments (as a JSON-serialisable dictionary).
    let inputSchema: [String: Any]
    /// Returns MCP `content` array items. Throws to produce an error result.
    let handler: ([String: Any]) throws -> [[String: Any]]
}

final class MCPServer {
    private var tools: [Tool] = []
    private let serverName: String
    private let serverVersion: String

    init(name: String, version: String) {
        self.serverName = name
        self.serverVersion = version
    }

    func register(_ tool: Tool) {
        tools.append(tool)
    }

    /// Blocking run loop: reads stdin line by line until EOF.
    func run() {
        while let line = readLine(strippingNewline: true) {
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            handle(msg)
        }
    }

    private func handle(_ msg: [String: Any]) {
        let method = msg["method"] as? String
        let id = msg["id"]

        switch method {
        case "initialize":
            respond(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": serverName, "version": serverVersion],
            ])
        case "notifications/initialized", "initialized":
            break // notification, no response
        case "tools/list":
            respond(id: id, result: ["tools": tools.map { [
                "name": $0.name,
                "description": $0.description,
                "inputSchema": $0.inputSchema,
            ] }])
        case "tools/call":
            handleToolCall(id: id, params: msg["params"] as? [String: Any] ?? [:])
        default:
            if id != nil {
                respondError(id: id, code: -32601, message: "Method not found: \(method ?? "nil")")
            }
        }
    }

    private func handleToolCall(id: Any?, params: [String: Any]) {
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        guard let tool = tools.first(where: { $0.name == name }) else {
            respondError(id: id, code: -32602, message: "Unknown tool: \(name)")
            return
        }
        do {
            let content = try tool.handler(args)
            respond(id: id, result: ["content": content])
        } catch {
            // MCP convention: tool errors go in the result with isError, not JSON-RPC error.
            respond(id: id, result: [
                "content": [["type": "text", "text": "Error: \(error.localizedDescription)"]],
                "isError": true,
            ])
        }
    }

    // MARK: - Output

    private func respond(id: Any?, result: [String: Any]) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id = id { msg["id"] = id }
        write(msg)
    }

    private func respondError(id: Any?, code: Int, message: String) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        msg["id"] = id ?? NSNull()
        write(msg)
    }

    private func write(_ msg: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: msg, options: [.withoutEscapingSlashes]) else {
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }
}

/// Convenience for a text content item.
func textContent(_ text: String) -> [String: Any] {
    ["type": "text", "text": text]
}
