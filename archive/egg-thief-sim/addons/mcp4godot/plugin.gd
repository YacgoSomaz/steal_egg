@tool
extends EditorPlugin
## MCP4Godot Plugin
## Provides an MCP (Model Context Protocol) server that allows AI clients
## to control the Godot editor via Streamable HTTP connection.

var _dock: Control
var _http_server: MCPHTTPServer
var _mcp_handler: MCPHandler
var _tool_registry: MCPToolRegistry
var _i18n: MCPI18n

const AUTO_START_SETTING := "mcp4godot/auto_start"
const PORT_SETTING := "mcp4godot/port"
const DEFAULT_PORT := 9877


func _get_plugin_icon() -> Texture2D:
	return preload("res://addons/mcp4godot/icon.svg")


func _enter_tree() -> void:
	# 0. Initialize i18n (must be first so other components can use tr() with our domain)
	_i18n = MCPI18n.new()
	_i18n.setup()

	# 1. Build tool registry
	_tool_registry = MCPToolRegistry.new()
	_register_all_tools()

	# 2. Create MCP handler (protocol layer) — RefCounted
	_mcp_handler = MCPHandler.new()
	_mcp_handler.tool_registry = _tool_registry
	_mcp_handler.set_translation_domain(MCPI18n.get_domain_name())
	_mcp_handler.log_message.connect(_on_log_message)
	_mcp_handler.client_connected.connect(_on_client_connected)
	_mcp_handler.client_disconnected.connect(_on_client_disconnected)
	_mcp_handler.client_initialized.connect(_on_client_initialized)
	_mcp_handler.tool_called.connect(_on_tool_called)

	# 3. Create HTTP transport server
	_http_server = MCPHTTPServer.new()
	_http_server.mcp_handler = _mcp_handler
	_http_server.set_translation_domain(MCPI18n.get_domain_name())
	add_child(_http_server)
	_http_server.status_changed.connect(_on_transport_status)
	_http_server.log_message.connect(_on_log_message)
	_http_server.session_created.connect(_on_session_created)

	# 4. Create and add dock
	_dock = preload("res://addons/mcp4godot/ui/mcp_dock.tscn").instantiate()
	_dock.set_translation_domain(MCPI18n.get_domain_name())
	_dock.start_requested.connect(_on_start_requested)
	_dock.stop_requested.connect(_on_stop_requested)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	# This project can opt in through project.godot. The HTTP transport itself
	# is bound to 127.0.0.1, so it remains local to this machine.
	if bool(ProjectSettings.get_setting(AUTO_START_SETTING, false)):
		call_deferred("_start_configured_server")


func _exit_tree() -> void:
	if _http_server:
		_http_server.stop_server()
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	if _i18n:
		_i18n.cleanup()
		_i18n = null


func _on_start_requested(port: int) -> void:
	_http_server.start_server(port)


func _start_configured_server() -> void:
	if not _http_server:
		return
	var port := int(ProjectSettings.get_setting(PORT_SETTING, DEFAULT_PORT))
	if _http_server.start_server(port) and _dock:
		_dock.set_server_running(port)


func _on_stop_requested() -> void:
	_http_server.stop_server()


func _on_transport_status(status: String) -> void:
	if _dock:
		_dock.on_status_changed(status)


func _on_log_message(message: String) -> void:
	if _dock:
		_dock.on_log_message(message)


func _on_client_connected(event: Dictionary) -> void:
	if _dock:
		_dock.on_client_connected(event)


func _on_client_disconnected(event: Dictionary) -> void:
	if _dock:
		_dock.on_client_disconnected(event)


func _on_client_initialized(event: Dictionary) -> void:
	if _dock:
		_dock.on_client_initialized(event)


func _on_tool_called(event: Dictionary) -> void:
	if _dock:
		_dock.on_tool_called(event)


func _on_session_created(event: Dictionary) -> void:
	if _dock:
		_dock.on_session_created(event)


func _register_all_tools() -> void:
	var node_tools := NodeTools.new()
	for tool in node_tools.get_tools():
		_tool_registry.register_tool(tool)

	var property_tools := PropertyTools.new()
	for tool in property_tools.get_tools():
		_tool_registry.register_tool(tool)

	var editor_tools := EditorTools.new()
	for tool in editor_tools.get_tools():
		_tool_registry.register_tool(tool)

	var file_tools := FileTools.new()
	for tool in file_tools.get_tools():
		_tool_registry.register_tool(tool)

	var script_tools := ScriptTools.new()
	for tool in script_tools.get_tools():
		_tool_registry.register_tool(tool)

	var project_settings_tools := ProjectSettingsTools.new()
	for tool in project_settings_tools.get_tools():
		_tool_registry.register_tool(tool)
