@tool
class_name MCPJsonRPC
extends RefCounted
## JSON-RPC 2.0 message parsing and construction utilities.
## All methods are static — this is a stateless utility class.

## JSON-RPC 2.0 standard error codes.
const PARSE_ERROR: int = -32700
const INVALID_REQUEST: int = -32600
const METHOD_NOT_FOUND: int = -32601
const INVALID_PARAMS: int = -32602
const INTERNAL_ERROR: int = -32603

## MCP-specific error codes.
const SERVER_NOT_INITIALIZED: int = -32002
const SERVER_ERROR_START: int = -32000


## Parse a raw JSON-RPC message string.
## Returns a Dictionary with keys: valid, id, method, params, is_notification, error.
static func parse_message(raw: String) -> Dictionary:
	var result: Dictionary = {
		"valid": false,
		"id": null,
		"method": "",
		"params": {},
		"is_notification": false,
		"error": "",
	}

	# Parse JSON
	var json := JSON.new()
	var err: int = json.parse(raw)
	if err != OK:
		result.error = "Parse error: %s at line %d" % [json.get_error_message(), json.get_error_line()]
		return result

	var data: Variant = json.data
	if data == null or not data is Dictionary:
		result.error = "Invalid request: expected JSON object"
		return result

	var msg: Dictionary = data

	# Check jsonrpc version
	if not msg.has("jsonrpc") or msg["jsonrpc"] != "2.0":
		result.error = "Invalid request: missing or wrong jsonrpc version"
		return result

	# Check method
	if not msg.has("method") or not msg["method"] is String:
		result.error = "Invalid request: missing or invalid method"
		return result

	result.method = msg["method"]

	# Check id (notifications have no id)
	if msg.has("id"):
		result.id = msg["id"]
		result.is_notification = false
	else:
		result.id = null
		result.is_notification = true

	# Extract params
	if msg.has("params"):
		if msg["params"] is Dictionary:
			result.params = msg["params"]
		elif msg["params"] is Array:
			# Positional params — store as array under special key
			result.params = {"_positional": msg["params"]}
		else:
			result.error = "Invalid params: must be object or array"
			return result

	result.valid = true
	return result


## Construct a JSON-RPC success response.
static func make_response(id: Variant, result: Variant) -> Dictionary:
	return {
		"jsonrpc": "2.0",
		"id": id,
		"result": result,
	}


## Construct a JSON-RPC error response.
static func make_error(id: Variant, code: int, message: String, data: Variant = null) -> Dictionary:
	var error_obj: Dictionary = {
		"code": code,
		"message": message,
	}
	if data != null:
		error_obj["data"] = data
	return {
		"jsonrpc": "2.0",
		"id": id,
		"error": error_obj,
	}


## Construct a JSON-RPC notification (no id, no response expected).
static func make_notification(method: String, params: Dictionary = {}) -> Dictionary:
	var msg: Dictionary = {
		"jsonrpc": "2.0",
		"method": method,
	}
	if not params.is_empty():
		msg["params"] = params
	return msg


## Serialize a Dictionary to JSON string.
static func stringify(data: Variant) -> String:
	return JSON.stringify(data)
