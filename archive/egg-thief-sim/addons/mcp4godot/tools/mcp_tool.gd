@tool
class_name MCPTool
extends RefCounted
## Base class for all MCP tools.
## Each tool subclass provides its name, description, input schema, read-only flag, and execution logic.

var tool_name: String
var tool_description: String
var input_schema: Dictionary  ## JSON Schema object
var is_read_only: bool = true  ## Whether this tool only reads state (no side effects)


func _init(p_name: String, p_description: String, p_schema: Dictionary, p_read_only: bool = true) -> void:
	tool_name = p_name
	tool_description = p_description
	input_schema = p_schema
	is_read_only = p_read_only


## Return the MCP tool definition dict for tools/list.
func get_definition() -> Dictionary:
	return {
		"name": tool_name,
		"description": tool_description,
		"inputSchema": input_schema,
		"readOnly": is_read_only,
	}


## Execute the tool with the given arguments.
## Override in subclass. Returns { content: Array, isError: bool }.
func execute(arguments: Dictionary) -> Dictionary:
	return {
		"content": [{"type": "text", "text": "Tool not implemented: %s" % tool_name}],
		"isError": true,
	}


## Helper: create a successful text result.
static func text_result(text: String) -> Dictionary:
	return {
		"content": [{"type": "text", "text": text}],
		"isError": false,
	}


## Helper: create an error result.
static func error_result(message: String) -> Dictionary:
	return {
		"content": [{"type": "text", "text": message}],
		"isError": true,
	}
