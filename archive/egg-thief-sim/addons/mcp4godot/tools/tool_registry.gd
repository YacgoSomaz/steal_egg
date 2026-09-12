@tool
class_name MCPToolRegistry
extends RefCounted
## Registry for MCP tools. Handles registration, lookup, and dispatch.

var _tools: Dictionary = {}  ## String -> MCPTool


## Register a tool instance.
func register_tool(tool: MCPTool) -> void:
	_tools[tool.tool_name] = tool


## Get a tool by name. Returns null if not found.
func get_tool(name: String) -> MCPTool:
	return _tools.get(name) as MCPTool


## Get all tool definitions for tools/list response.
func get_all_definitions() -> Array[Dictionary]:
	var defs: Array[Dictionary] = []
	for tool in _tools.values():
		defs.append(tool.get_definition())
	return defs


## Execute a tool by name with the given arguments.
## Returns { content: Array, isError: bool }.
func call_tool(name: String, arguments: Dictionary) -> Dictionary:
	var tool: MCPTool = _tools.get(name) as MCPTool
	if tool == null:
		return MCPTool.error_result("Unknown tool: %s" % name)
	return tool.execute(arguments)


## Get the number of registered tools.
func get_tool_count() -> int:
	return _tools.size()
