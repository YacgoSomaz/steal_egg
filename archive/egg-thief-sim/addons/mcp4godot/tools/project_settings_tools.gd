@tool
class_name ProjectSettingsTools
extends RefCounted
## Provides MCP tool instances for reading and writing Godot project settings.


## Return all project settings tool instances for registration.
func get_tools() -> Array[MCPTool]:
	return [
		ProjectSettingsListTool.new(),
		ProjectSettingsGetTool.new(),
		ProjectSettingsSetTool.new(),
	]


## --- project_settings_list ---
class ProjectSettingsListTool extends MCPTool:
	func _init() -> void:
		super._init(
			"project_settings_list",
			"List project settings, optionally filtered by prefix and custom status. By default only shows user-customized settings (is_custom=true).",
			{
				"type": "object",
				"properties": {
					"prefix": {
						"type": "string",
						"description": "Optional prefix to filter settings (e.g. 'input/', 'application/', 'display/'). If omitted, lists all settings.",
					},
					"is_custom": {
						"description": "Filter by custom status. true = only user-customized settings (default), false = only engine defaults, null = show all.",
						"default": true,
					},
					"max_results": {
						"type": "integer",
						"description": "Maximum number of results to return (default: 100)",
						"default": 100,
					},
				},
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var prefix: String = arguments.get("prefix", "")
		var is_custom_filter: Variant = arguments.get("is_custom", true)
		# MCP clients may serialize untyped parameters as strings.
		if is_custom_filter is String:
			if is_custom_filter == "null":
				is_custom_filter = null
			else:
				is_custom_filter = is_custom_filter == "true"
		var max_results: int = arguments.get("max_results", 100)

		# NO_BUILTIN_ORDER_BASE = 1 << 16 = 65536 in Godot source.
		# Settings with order >= this value are user-customized;
		# settings with order < this value are engine built-in defaults.
		const NO_BUILTIN_ORDER_BASE: int = 1 << 16

		var results: Array = []
		var count: int = 0
		var total: int = 0

		for prop in ProjectSettings.get_property_list():
			var prop_name: String = prop.get("name", "")

			# Skip empty names and internal properties (starting with _)
			if prop_name.is_empty() or prop_name.begins_with("_"):
				continue

			# Filter by prefix if specified
			if not prefix.is_empty() and not prop_name.begins_with(prefix):
				continue

			# Determine if setting is user-customized via get_order().
			# Built-in settings have order < NO_BUILTIN_ORDER_BASE.
			var is_custom: bool = ProjectSettings.get_order(prop_name) >= NO_BUILTIN_ORDER_BASE

			# Filter by custom status
			if is_custom_filter != null:
				if bool(is_custom_filter) != is_custom:
					continue

			total += 1

			# Skip if we've reached max results
			if count >= max_results:
				continue

			var prop_type: int = prop.get("type", TYPE_NIL)
			var value: Variant = ProjectSettings.get_setting(prop_name)

			results.append({
				"name": prop_name,
				"type": type_string(prop_type),
				"value": VariantSerializer.serialize(value),
				"is_custom": is_custom,
			})
			count += 1

		var result: Dictionary = {
			"prefix": prefix if not prefix.is_empty() else "(all)",
			"is_custom_filter": is_custom_filter,
			"count": results.size(),
			"total_available": total,
			"settings": results,
		}
		return MCPTool.text_result(JSON.stringify(result, "\t"))


## --- project_settings_get ---
class ProjectSettingsGetTool extends MCPTool:
	func _init() -> void:
		super._init(
			"project_settings_get",
			"Get the value of a project setting",
			{
				"type": "object",
				"properties": {
					"setting_name": {
						"type": "string",
						"description": "The project setting name (e.g. 'application/config/name', 'display/window/size/viewport_width').",
					},
					"default_value": {
						"description": "Optional default value if setting doesn't exist.",
					},
				},
				"required": ["setting_name"],
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var setting_name: String = arguments.get("setting_name", "")
		var default_value: Variant = arguments.get("default_value", null)

		if setting_name.is_empty():
			return MCPTool.error_result("Missing required parameter: setting_name")

		if not ProjectSettings.has_setting(setting_name):
			return MCPTool.error_result("Project setting '%s' does not exist" % setting_name)

		var value: Variant = ProjectSettings.get_setting(setting_name, default_value)
		var serialized := VariantSerializer.serialize(value)

		var result: Dictionary = {
			"setting_name": setting_name,
			"value": serialized,
			"value_type": type_string(typeof(value)),
		}
		return MCPTool.text_result(JSON.stringify(result, "\t"))


## --- project_settings_set ---
class ProjectSettingsSetTool extends MCPTool:
	func _init() -> void:
		super._init(
			"project_settings_set",
			"Set the value of a project setting and save to project.godot",
			{
				"type": "object",
				"properties": {
					"setting_name": {
						"type": "string",
						"description": "The project setting name (e.g. 'application/config/name', 'display/window/size/viewport_width').",
					},
					"value": {
						"description": "The value to set. Types vary by setting (string, number, boolean, array, dictionary).",
					},
				},
				"required": ["setting_name", "value"],
			},
			false  # Not read-only
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var setting_name: String = arguments.get("setting_name", "")
		var raw_value: Variant = arguments.get("value", null)

		# MCP clients may serialize untyped parameters as JSON strings.
		if raw_value is String:
			var json := JSON.new()
			if json.parse(raw_value) == OK:
				raw_value = json.data

		if setting_name.is_empty():
			return MCPTool.error_result("Missing required parameter: setting_name")
		if raw_value == null:
			return MCPTool.error_result("Missing required parameter: value")

		# Get the target type from property list
		var target_type: int = _get_setting_type(setting_name)

		# Deserialize the value from JSON to Godot type
		var deserialized: Variant = VariantSerializer.deserialize(raw_value, target_type)

		# Set the setting
		ProjectSettings.set_setting(setting_name, deserialized)

		# Save to project.godot
		var save_error: int = ProjectSettings.save()
		if save_error != OK:
			return MCPTool.error_result("Failed to save project settings (error code: %d)" % save_error)

		# Read back to confirm
		var new_value: Variant = ProjectSettings.get_setting(setting_name)

		var result: Dictionary = {
			"setting_name": setting_name,
			"value_set": VariantSerializer.serialize(deserialized),
			"value_actual": VariantSerializer.serialize(new_value),
		}
		return MCPTool.text_result("Project setting set successfully:\n" + JSON.stringify(result, "\t"))

	func _get_setting_type(setting_name: String) -> int:
		for prop in ProjectSettings.get_property_list():
			if prop["name"] == setting_name:
				return prop.get("type", TYPE_NIL)
		return TYPE_NIL
