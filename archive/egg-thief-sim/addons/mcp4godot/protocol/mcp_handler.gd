@tool
class_name MCPHandler
extends RefCounted
## MCP protocol router.
## Handles the full MCP lifecycle: initialize, tools/list, tools/call, ping, shutdown.
## Routes incoming JSON-RPC messages and dispatches them to appropriate handlers.
##
## This class is a RefCounted utility — it processes messages synchronously and returns
## results directly. It does NOT use signals for responses, making it compatible with
## both WebSocket (async) and HTTP (sync) transports.

signal log_message(message: String) ## Emitted for generic text log entries.

signal client_connected(event: Dictionary) ## Emitted when a client connects.
signal client_disconnected(event: Dictionary) ## Emitted when a client disconnects.
signal client_initialized(event: Dictionary) ## Emitted during client init handshake (initializing/ready).
signal tool_called(event: Dictionary) ## Emitted after a tool is executed.

## Reference to the tool registry, set by the plugin.
var tool_registry: MCPToolRegistry

## Per-session connection state.
var _client_states: Dictionary = {}  ## session_key -> { state: ClientState, client_info, capabilities }


## Process a raw JSON-RPC message and return the response as a JSON string.
## For notifications, returns empty string "" (no response needed).
## For requests, returns the full JSON-RPC response string.
## This is the primary entry point for both HTTP and WebSocket transports.
func process_message(session_key: String, raw: String) -> String:
	var parsed: Dictionary = MCPJsonRPC.parse_message(raw)

	if not parsed.valid:
		var error_resp: Dictionary = MCPJsonRPC.make_error(null, MCPJsonRPC.PARSE_ERROR, parsed.error)
		return MCPJsonRPC.stringify(error_resp)

	# Route to appropriate handler
	var response: Dictionary = _route_message(session_key, parsed)

	# Notifications don't get a response
	if parsed.is_notification:
		return ""

	# Return the serialized response
	if not response.is_empty():
		return MCPJsonRPC.stringify(response)

	return ""


## Called when a new client/session connects (WebSocket or HTTP).
func on_client_connected(session_key: String) -> void:
	_client_states[session_key] = {
		"state": MCPTypes.ClientState.CONNECTED,
		"client_info": {},
		"capabilities": {},
	}
	client_connected.emit({
		"session_key": session_key,
		"timestamp": Time.get_time_string_from_system(),
	})


## Called when a client/session disconnects.
func on_client_disconnected(session_key: String) -> void:
	_client_states.erase(session_key)
	client_disconnected.emit({
		"session_key": session_key,
		"timestamp": Time.get_time_string_from_system(),
	})


## Route a parsed JSON-RPC message to the appropriate handler.
func _route_message(session_key: String, parsed: Dictionary) -> Dictionary:
	var method: String = parsed.method
	var params: Dictionary = parsed.params
	var msg_id: Variant = parsed.id

	# Check initialization state (initialize is always allowed)
	if method != MCPTypes.METHOD_INITIALIZE:
		if not _is_client_ready(session_key):
			if method == MCPTypes.METHOD_INITIALIZED:
				pass  # Will be handled below
			else:
				return MCPJsonRPC.make_error(
					msg_id, MCPJsonRPC.SERVER_NOT_INITIALIZED,
					"Server not initialized. Send 'initialize' request first."
				)

	match method:
		MCPTypes.METHOD_INITIALIZE:
			return _handle_initialize(session_key, params, msg_id)
		MCPTypes.METHOD_INITIALIZED:
			_handle_initialized(session_key, params)
			return {}  # No response for notifications
		MCPTypes.METHOD_TOOLS_LIST:
			return _handle_tools_list(msg_id, params)
		MCPTypes.METHOD_TOOLS_CALL:
			return _handle_tools_call(msg_id, params)
		MCPTypes.METHOD_RESOURCES_LIST:
			return _handle_resources_list(msg_id)
		MCPTypes.METHOD_PROMPTS_LIST:
			return _handle_prompts_list(msg_id)
		MCPTypes.METHOD_PING:
			return _handle_ping(msg_id)
		MCPTypes.METHOD_SHUTDOWN:
			return _handle_shutdown(session_key, msg_id)
		_:
			return MCPJsonRPC.make_error(msg_id, MCPJsonRPC.METHOD_NOT_FOUND, "Method not found: %s" % method)


## Handle the 'initialize' request.
func _handle_initialize(session_key: String, params: Dictionary, msg_id: Variant) -> Dictionary:
	if not _client_states.has(session_key):
		_client_states[session_key] = {
			"state": MCPTypes.ClientState.CONNECTED,
			"client_info": {},
			"capabilities": {},
		}
	_client_states[session_key].client_info = params.get("clientInfo", {})
	_client_states[session_key].capabilities = params.get("capabilities", {})
	_client_states[session_key].state = MCPTypes.ClientState.INITIALIZING

	var client_name: String = params.get("clientInfo", {}).get("name", "unknown")
	var client_version: String = params.get("clientInfo", {}).get("version", "?")

	client_initialized.emit({
		"session_key": session_key,
		"client_name": client_name,
		"client_version": client_version,
		"state": "initializing",
		"timestamp": Time.get_time_string_from_system(),
	})

	var result: Dictionary = {
		"protocolVersion": MCPTypes.PROTOCOL_VERSION,
		"capabilities": {
			"tools": {"listChanged": true},
			"resources": {},
			"prompts": {},
		},
		"serverInfo": {
			"name": MCPTypes.SERVER_NAME,
			"version": MCPTypes.SERVER_VERSION,
		},
	}
	return MCPJsonRPC.make_response(msg_id, result)


## Handle the 'notifications/initialized' notification.
func _handle_initialized(session_key: String, _params: Dictionary) -> void:
	if _client_states.has(session_key):
		_client_states[session_key].state = MCPTypes.ClientState.READY

		var client_info: Dictionary = _client_states[session_key].get("client_info", {})
		client_initialized.emit({
			"session_key": session_key,
			"client_name": client_info.get("name", "unknown"),
			"client_version": client_info.get("version", "?"),
			"state": "ready",
			"timestamp": Time.get_time_string_from_system(),
		})


## Handle the 'tools/list' request.
func _handle_tools_list(msg_id: Variant, _params: Dictionary) -> Dictionary:
	var tools: Array = tool_registry.get_all_definitions()
	return MCPJsonRPC.make_response(msg_id, {"tools": tools})


## Handle the 'tools/call' request.
func _handle_tools_call(msg_id: Variant, params: Dictionary) -> Dictionary:
	var tool_name: String = params.get("name", "")
	var arguments: Dictionary = params.get("arguments", {})

	if tool_name.is_empty():
		return MCPJsonRPC.make_error(msg_id, MCPJsonRPC.INVALID_PARAMS, "Missing required field: name")

	var result: Dictionary = tool_registry.call_tool(tool_name, arguments)

	tool_called.emit({
		"tool_name": tool_name,
		"arguments": arguments,
		"result": result,
		"is_error": result.get("isError", false),
		"timestamp": Time.get_time_string_from_system(),
	})

	return MCPJsonRPC.make_response(msg_id, result)


## Handle the 'resources/list' request.
func _handle_resources_list(msg_id: Variant) -> Dictionary:
	return MCPJsonRPC.make_response(msg_id, {"resources": []})


## Handle the 'prompts/list' request.
func _handle_prompts_list(msg_id: Variant) -> Dictionary:
	return MCPJsonRPC.make_response(msg_id, {"prompts": []})


## Handle the 'ping' request.
func _handle_ping(msg_id: Variant) -> Dictionary:
	return MCPJsonRPC.make_response(msg_id, {})


## Handle the 'shutdown' request.
func _handle_shutdown(session_key: String, msg_id: Variant) -> Dictionary:
	if _client_states.has(session_key):
		_client_states[session_key].state = MCPTypes.ClientState.CONNECTED
	log_message.emit(tr("LOG_CLIENT_SHUTDOWN") % session_key)
	return MCPJsonRPC.make_response(msg_id, {})


## Check if a client has completed the initialization handshake.
func _is_client_ready(session_key: String) -> bool:
	if not _client_states.has(session_key):
		return false
	return _client_states[session_key].state == MCPTypes.ClientState.READY
