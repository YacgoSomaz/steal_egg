@tool
class_name MCPTypes
extends RefCounted
## MCP protocol constants and type definitions.

## Protocol version supported by this server.
const PROTOCOL_VERSION: String = "2025-03-26"

## Server identity.
const SERVER_NAME: String = "mcp4godot"
const SERVER_VERSION: String = "1.0.0"

## MCP method names.
const METHOD_INITIALIZE: String = "initialize"
const METHOD_INITIALIZED: String = "notifications/initialized"
const METHOD_TOOLS_LIST: String = "tools/list"
const METHOD_TOOLS_CALL: String = "tools/call"
const METHOD_RESOURCES_LIST: String = "resources/list"
const METHOD_RESOURCES_READ: String = "resources/read"
const METHOD_PROMPTS_LIST: String = "prompts/list"
const METHOD_PING: String = "ping"
const METHOD_SHUTDOWN: String = "shutdown"

## MCP notification names.
const NOTIFICATION_TOOLS_LIST_CHANGED: String = "notifications/tools/list_changed"

## Client connection states.
enum ClientState {
	CONNECTED,      ## Connection open, MCP not initialized
	INITIALIZING,   ## initialize request received, awaiting initialized notification
	READY,          ## Fully initialized, can handle all requests
}

## Default HTTP port.
const DEFAULT_PORT: int = 9877
