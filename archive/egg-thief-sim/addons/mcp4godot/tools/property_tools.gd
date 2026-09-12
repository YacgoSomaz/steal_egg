@tool
class_name PropertyTools
extends RefCounted
## Provides MCP tool instances for property/method access: get, set, list, method_call.
## Shared utilities are in ToolUtils.


## Return all property tool instances for registration.
func get_tools() -> Array[MCPTool]:
	return [
		PropertyGetTool.new(),
		PropertySetTool.new(),
		PropertyListTool.new(),
		MethodCallTool.new(),
		ResourceCreateTool.new(),
	]


## --- property_get ---
class PropertyGetTool extends MCPTool:
	func _init() -> void:
		super._init(
			"property_get",
			"Get the value of a property on a node",
			{
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "NodePath of the node. Use relative path from scene root (e.g. 'Player', 'Player/Sprite2D').",
					},
					"property": {
						"type": "string",
						"description": "Property name (e.g. 'position', 'modulate', 'text', 'position:x')",
					},
				},
				"required": ["node_path", "property"],
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var node_path: String = arguments.get("node_path", "")
		var property: String = arguments.get("property", "")

		if node_path.is_empty():
			return MCPTool.error_result("Missing required parameter: node_path")
		if property.is_empty():
			return MCPTool.error_result("Missing required parameter: property")

		var node := ToolUtils.get_node_by_path(node_path)
		if node == null:
			var root_hint: String = ToolUtils.get_edited_scene_root_path()
			var hint: String = ""
			if root_hint.is_empty():
				hint = " No scene is currently open."
			else:
				hint = " Current scene root: %s" % root_hint
			return MCPTool.error_result("Node not found at path: %s.%s" % [node_path, hint])

		# Check if property exists
		if not _property_exists(node, property):
			return MCPTool.error_result("Property '%s' not found on node '%s' (type: %s)" % [property, node.name, node.get_class()])

		var value: Variant = node.get_indexed(property)
		var serialized := VariantSerializer.serialize(value)

		var result: Dictionary = {
			"node": node.name,
			"property": property,
			"value": serialized,
			"value_type": type_string(typeof(value)),
		}
		return MCPTool.text_result(JSON.stringify(result, "\t"))

	func _property_exists(node: Node, property: String) -> bool:
		# Check indexed property (e.g. "position:x")
		var split := property.split(":")
		if split.size() > 1:
			return _property_exists(node, split[0])

		# Check direct property
		for prop in node.get_property_list():
			if prop["name"] == property:
				return true
		return false


## --- property_set ---
class PropertySetTool extends MCPTool:
	func _init() -> void:
		super._init(
			"property_set",
			"Set the value of a property on a node",
			{
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "NodePath of the node. Use relative path from scene root (e.g. 'Player', 'Player/Sprite2D').",
					},
					"property": {
						"type": "string",
						"description": "Property name",
					},
					"value": {
						"description": "The value to set. Types vary by property (string, number, object, array). Vector types use {x,y} or {x,y,z}. Color uses {r,g,b,a}.",
					},
				},
				"required": ["node_path", "property", "value"],
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var node_path: String = arguments.get("node_path", "")
		var property: String = arguments.get("property", "")
		var raw_value: Variant = arguments.get("value", null)

		# MCP clients may serialize untyped parameters as JSON strings.
		# Try to parse string values as JSON to recover structured types.
		if raw_value is String:
			var json := JSON.new()
			if json.parse(raw_value) == OK:
				raw_value = json.data

		if node_path.is_empty():
			return MCPTool.error_result("Missing required parameter: node_path")
		if property.is_empty():
			return MCPTool.error_result("Missing required parameter: property")
		if raw_value == null:
			return MCPTool.error_result("Missing required parameter: value")

		var node := ToolUtils.get_node_by_path(node_path)
		if node == null:
			var root_hint: String = ToolUtils.get_edited_scene_root_path()
			var hint: String = ""
			if root_hint.is_empty():
				hint = " No scene is currently open."
			else:
				hint = " Current scene root: %s" % root_hint
			return MCPTool.error_result("Node not found at path: %s.%s" % [node_path, hint])

		# Try to determine the expected type for the property
		var target_type: int = _get_property_type(node, property)

		# Deserialize the value from JSON to Godot type
		var deserialized: Variant = VariantSerializer.deserialize(raw_value, target_type)

		# Set the property
		node.set_indexed(property, deserialized)

		# Read back the value to confirm
		var new_value: Variant = node.get_indexed(property)

		var result: Dictionary = {
			"node": node.name,
			"property": property,
			"value_set": VariantSerializer.serialize(deserialized),
			"value_actual": VariantSerializer.serialize(new_value),
		}
		ToolUtils.mark_scene_as_unsaved()
		return MCPTool.text_result("Property set successfully:\n" + JSON.stringify(result, "\t"))

	func _get_property_type(node: Node, property: String) -> int:
		# For indexed properties like "position:x", check the base property
		var split := property.split(":")
		var base_prop: String = split[0]

		for prop in node.get_property_list():
			if prop["name"] == base_prop:
				# If it's an indexed sub-property (e.g. position:x), return float
				if split.size() > 1:
					return TYPE_FLOAT
				return prop.get("type", TYPE_NIL)
		return TYPE_NIL


## --- property_list ---
class PropertyListTool extends MCPTool:
	func _init() -> void:
		super._init(
			"property_list",
			"List all properties of a node with their current values and types",
			{
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "NodePath of the node. Use relative path from scene root (e.g. 'Player', 'Player/Sprite2D').",
					},
					"include_internal": {
						"type": "boolean",
						"description": "Include internal/editor-only properties",
						"default": false,
					},
				},
				"required": ["node_path"],
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var node_path: String = arguments.get("node_path", "")
		var include_internal: bool = arguments.get("include_internal", false)

		if node_path.is_empty():
			return MCPTool.error_result("Missing required parameter: node_path")

		var node := ToolUtils.get_node_by_path(node_path)
		if node == null:
			var root_hint: String = ToolUtils.get_edited_scene_root_path()
			var hint: String = ""
			if root_hint.is_empty():
				hint = " No scene is currently open."
			else:
				hint = " Current scene root: %s" % root_hint
			return MCPTool.error_result("Node not found at path: %s.%s" % [node_path, hint])

		var properties: Array = []
		for prop in node.get_property_list():
			var usage: int = prop.get("usage", 0)

			# Skip internal/storage properties unless requested
			if not include_internal:
				# PROPERTY_USAGE_STORAGE = 8, PROPERTY_USAGE_INTERNAL = 64
				if usage & 64:  # Internal flag
					continue

			var prop_name: String = prop["name"]
			var prop_type: int = prop.get("type", 0)
			var value: Variant = null

			# Try to get the value safely
			if node.get(prop_name) != null or prop_type != TYPE_OBJECT:
				value = VariantSerializer.serialize(node.get(prop_name))

			properties.append({
				"name": prop_name,
				"type": type_string(prop_type),
				"value": value,
			})

		return MCPTool.text_result(JSON.stringify(properties, "\t"))


## --- method_call ---
class MethodCallTool extends MCPTool:
	func _init() -> void:
		super._init(
			"method_call",
			"Call a method on a node with the given arguments",
			{
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "NodePath of the node. Use relative path from scene root (e.g. 'Player', 'Player/Sprite2D').",
					},
					"method": {
						"type": "string",
						"description": "Method name to call",
					},
					"args": {
						"type": "array",
						"description": "Array of arguments to pass to the method",
						"items": {},
						"default": [],
					},
				},
				"required": ["node_path", "method"],
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var node_path: String = arguments.get("node_path", "")
		var method: String = arguments.get("method", "")
		var args: Array = arguments.get("args", [])

		if node_path.is_empty():
			return MCPTool.error_result("Missing required parameter: node_path")
		if method.is_empty():
			return MCPTool.error_result("Missing required parameter: method")

		var node := ToolUtils.get_node_by_path(node_path)
		if node == null:
			var root_hint: String = ToolUtils.get_edited_scene_root_path()
			var hint: String = ""
			if root_hint.is_empty():
				hint = " No scene is currently open."
			else:
				hint = " Current scene root: %s" % root_hint
			return MCPTool.error_result("Node not found at path: %s.%s" % [node_path, hint])

		# Check if method exists
		if not node.has_method(method):
			return MCPTool.error_result("Method '%s' not found on node '%s' (type: %s)" % [method, node.name, node.get_class()])

		# Deserialize args
		var deserialized_args: Array = []
		for arg in args:
			# MCP clients may serialize untyped parameters as JSON strings
			var parsed_arg: Variant = arg
			if arg is String:
				var json := JSON.new()
				if json.parse(arg) == OK:
					parsed_arg = json.data
			deserialized_args.append(VariantSerializer.deserialize(parsed_arg))

		# Call the method
		var result_value: Variant = node.callv(method, deserialized_args)

		var result: Dictionary = {
			"node": node.name,
			"method": method,
			"result": VariantSerializer.serialize(result_value),
			"result_type": type_string(typeof(result_value)),
		}
		return MCPTool.text_result(JSON.stringify(result, "\t"))


## --- resource_create ---
class ResourceCreateTool extends MCPTool:
	func _init() -> void:
		super._init(
			"resource_create",
			"Create a new resource instance and assign it to a node property (like Inspector's 'New' button)",
			{
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "NodePath of the node. Use relative path from scene root (e.g. 'Player').",
					},
					"property": {
						"type": "string",
						"description": "Property name to assign the resource to (e.g. 'stats', 'texture').",
					},
					"class_name": {
						"type": "string",
						"description": "Resource class name to instantiate (e.g. 'PlayerStats', 'Curve', 'GradientTexture2D'). For custom scripts with class_name, use the declared class name.",
					},
					"unique": {
						"type": "boolean",
						"description": "If true, mark the resource as local to scene (Inspector's 'Make Unique'). Default: false.",
						"default": false,
					},
					"save_path": {
						"type": "string",
						"description": "Optional path to save the resource as a .tres file (e.g. 'res://my_stats.tres'). If omitted, the resource is created inline.",
						"default": "",
					},
				},
				"required": ["node_path", "property", "class_name"],
			},
			false  # Not read-only
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var node_path: String = arguments.get("node_path", "")
		var property: String = arguments.get("property", "")
		var resource_class: String = arguments.get("class_name", "")
		var unique: bool = arguments.get("unique", false)
		var save_path: String = arguments.get("save_path", "")

		if node_path.is_empty():
			return MCPTool.error_result("Missing required parameter: node_path")
		if property.is_empty():
			return MCPTool.error_result("Missing required parameter: property")
		if resource_class.is_empty():
			return MCPTool.error_result("Missing required parameter: class_name")

		var node := ToolUtils.get_node_by_path(node_path)
		if node == null:
			var root_hint: String = ToolUtils.get_edited_scene_root_path()
			var hint: String = ""
			if root_hint.is_empty():
				hint = " No scene is currently open."
			else:
				hint = " Current scene root: %s" % root_hint
			return MCPTool.error_result("Node not found at path: %s.%s" % [node_path, hint])

		# Check if property exists
		if not _property_exists(node, property):
			return MCPTool.error_result("Property '%s' not found on node '%s' (type: %s)" % [property, node.name, node.get_class()])

		# Try to instantiate the resource class
		var resource: Resource = null

		if ClassDB.class_exists(resource_class):
			# Built-in or registered class
			var instance: Variant = ClassDB.instantiate(resource_class)
			if instance == null:
				return MCPTool.error_result("Failed to instantiate class '%s'" % resource_class)
			resource = instance as Resource
			if resource == null:
				return MCPTool.error_result("Class '%s' is not a Resource type (got %s)" % [resource_class, instance.get_class()])
		else:
			# Custom class — try to find the script and create an instance
			var script: Script = _find_script_for_class(resource_class)
			if script == null:
				return MCPTool.error_result("Class '%s' not found in ClassDB and no matching script found" % resource_class)
			var instance: Variant = script.new()
			if instance == null:
				return MCPTool.error_result("Failed to instantiate script for class '%s'" % resource_class)
			resource = instance as Resource
			if resource == null:
				return MCPTool.error_result("Script for '%s' does not produce a Resource (got %s)" % [resource_class, instance.get_class()])

		# Try to find and load the script for custom classes (class_name declared in .gd)
		# This allows custom resources like PlayerStats to get their script attached
		# (already done above for non-ClassDB classes, but ensure it's set for built-in too)
		if resource.script == null:
			var script: Script = _find_script_for_class(resource_class)
			if script != null:
				resource.script = script

		# Mark as unique (local to scene) if requested
		if unique:
			resource.resource_local_to_scene = true

		# Save to file if save_path provided
		if not save_path.is_empty():
			var save_err: int = ResourceSaver.save(resource, save_path)
			if save_err != OK:
				return MCPTool.error_result("Failed to save resource to '%s' (error: %s)" % [save_path, error_string(save_err)])
			# Reload from disk so the node references the saved file, not an inline copy
			var saved_resource := load(save_path)
			if saved_resource is Resource:
				resource = saved_resource
			else:
				return MCPTool.error_result("Saved resource at '%s' could not be loaded back" % save_path)

		# Assign to property
		node.set(property, resource)

		# Mark scene as unsaved
		ToolUtils.mark_scene_as_unsaved()

		var result: Dictionary = {
			"node": node.name,
			"property": property,
			"resource_type": resource.get_class(),
			"unique": unique,
			"saved_to": save_path if not save_path.is_empty() else "(inline)",
		}
		return MCPTool.text_result("Resource created and assigned successfully:\n" + JSON.stringify(result, "\t"))

	## Check if a property exists on a node
	func _property_exists(node: Node, property: String) -> bool:
		for prop in node.get_property_list():
			if prop["name"] == property:
				return true
		return false

	## Find the GDScript that declares a class_name matching the given name.
	## Scans loaded scripts to find one whose global_name matches.
	static func _find_script_for_class(class_name_str: String) -> Script:
		# Check if the class is already a built-in or registered type with a script
		if ClassDB.can_instantiate(class_name_str):
			# Try loading via class_name — ResourceLoader may resolve it
			var existing := load("res://" + class_name_str.to_snake_case() + ".gd")
			if existing is Script:
				return existing

		# Search for scripts with matching class_name
		var script_list: Array = EditorInterface.get_script_editor().get_open_scripts()
		for scr in script_list:
			if scr is Script and scr.get_global_name() == class_name_str:
				return scr

		# Try common naming patterns
		var paths: PackedStringArray = [
			"res://%s.gd" % class_name_str.to_snake_case(),
			"res://%s.gd" % class_name_str.to_pascal_case(),
			"res://scripts/%s.gd" % class_name_str.to_snake_case(),
		]
		for p in paths:
			if FileAccess.file_exists(p):
				var loaded := load(p)
				if loaded is Script:
					return loaded

		return null
