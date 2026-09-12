@tool
class_name EditorTools
extends RefCounted
## Provides MCP tool instances for editor control: scene management, project run/stop,
## filesystem refresh, project structure, search, class documentation, project info, scene creation.


## Return all editor tool instances for registration.
func get_tools() -> Array[MCPTool]:
	return [
		SceneOpenTool.new(),
		SceneSaveTool.new(),
		SceneListTool.new(),
		SceneGetCurrentTool.new(),
		SceneCreateTool.new(),
		ProjectRunTool.new(),
		ProjectStopTool.new(),
		RefreshFilesystemTool.new(),
		ProjectStructureTool.new(),
		SearchFilesTool.new(),
		GetClassDocumentationTool.new(),
		GetProjectInfoTool.new(),
	]


## --- scene_open ---
class SceneOpenTool extends MCPTool:
	func _init() -> void:
		super._init(
			"scene_open",
			"Open a scene file in the editor",
			{
				"type": "object",
				"properties": {
					"file_path": {
						"type": "string",
						"description": "Path to the .tscn or .scn file (e.g. 'res://scenes/main.tscn')",
					},
				},
				"required": ["file_path"],
			},
			false  # changes editor state
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var file_path: String = arguments.get("file_path", "")
		if file_path.is_empty():
			return MCPTool.error_result("Missing required parameter: file_path")

		# Check if file exists
		if not FileAccess.file_exists(file_path):
			return MCPTool.error_result("Scene file not found: %s" % file_path)

		EditorInterface.open_scene_from_path(file_path)
		return MCPTool.text_result("Scene opened: %s" % file_path)


## --- scene_save ---
class SceneSaveTool extends MCPTool:
	func _init() -> void:
		super._init(
			"scene_save",
			"Save the currently active scene",
			{
				"type": "object",
				"properties": {},
			},
			false  # writes file
		)

	func execute(_arguments: Dictionary) -> Dictionary:
		var err: int = EditorInterface.save_scene()
		if err != OK:
			return MCPTool.error_result("Failed to save scene: %s" % error_string(err))
		return MCPTool.text_result("Scene saved successfully")


## --- scene_list ---
class SceneListTool extends MCPTool:
	func _init() -> void:
		super._init(
			"scene_list",
			"List all currently open scenes in the editor",
			{
				"type": "object",
				"properties": {},
			}
		)

	func execute(_arguments: Dictionary) -> Dictionary:
		var open_scenes: PackedStringArray = EditorInterface.get_open_scenes()
		var current_root := EditorInterface.get_edited_scene_root()
		var current_scene: String = current_root.scene_file_path if (current_root and current_root.scene_file_path) else ""

		var result: Dictionary = {
			"open_scenes": Array(open_scenes),
			"current_scene": current_scene,
		}
		return MCPTool.text_result(JSON.stringify(result, "\t"))


## --- scene_get_current ---
class SceneGetCurrentTool extends MCPTool:
	func _init() -> void:
		super._init(
			"scene_get_current",
			"Get information about the currently edited scene's root node",
			{
				"type": "object",
				"properties": {},
			}
		)

	func execute(_arguments: Dictionary) -> Dictionary:
		var root := EditorInterface.get_edited_scene_root()
		if root == null:
			return MCPTool.error_result("No scene is currently open")

		var info: Dictionary = {
			"name": root.name,
			"type": root.get_class(),
			"path": str(root.name),
			"scene_file_path": root.scene_file_path if root.scene_file_path else "",
			"child_count": root.get_child_count(),
		}

		# List children recursively with paths
		var children: Array = []
		for child in root.get_children():
			children.append(_get_child_info(child, str(root.name)))
		info["children"] = children

		return MCPTool.text_result(JSON.stringify(info, "\t"))

	func _get_child_info(node: Node, parent_path: String) -> Dictionary:
		var node_path: String = parent_path + "/" + str(node.name)
		var info: Dictionary = {
			"name": node.name,
			"type": node.get_class(),
			"path": node_path,
		}
		var children: Array = []
		for child in node.get_children():
			children.append(_get_child_info(child, node_path))
		if not children.is_empty():
			info["children"] = children
		return info


## --- scene_create ---
class SceneCreateTool extends MCPTool:
	func _init() -> void:
		super._init(
			"scene_create",
			"Create a new scene file and open it in the editor",
			{
				"type": "object",
				"properties": {
					"file_path": {
						"type": "string",
						"description": "Path for the new scene file (e.g. 'res://scenes/new_scene.tscn')",
					},
					"root_type": {
						"type": "string",
						"description": "Class name for the root node (e.g. 'Node2D', 'Node3D', 'Control'). Default: 'Node2D'",
						"default": "Node2D",
					},
					"root_name": {
						"type": "string",
						"description": "Name for the root node. Default: derived from file name",
						"default": "",
					},
				},
				"required": ["file_path"],
			},
			false  # creates new file
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var file_path: String = arguments.get("file_path", "")
		var root_type: String = arguments.get("root_type", "Node2D")
		var root_name: String = arguments.get("root_name", "")

		if file_path.is_empty():
			return MCPTool.error_result("Missing required parameter: file_path")

		# Check file doesn't already exist
		if FileAccess.file_exists(file_path):
			return MCPTool.error_result("File already exists: %s" % file_path)

		# Validate root type
		if not ClassDB.class_exists(root_type):
			return MCPTool.error_result("Unknown class: %s" % root_type)
		if not ClassDB.is_parent_class(root_type, "Node"):
			return MCPTool.error_result("Class '%s' is not a Node type" % root_type)

		# Derive root name from file name if not specified
		if root_name.is_empty():
			root_name = file_path.get_file().get_basename()

		# Instantiate root node
		var root_node: Node = ClassDB.instantiate(root_type) as Node
		if root_node == null:
			return MCPTool.error_result("Failed to instantiate class: %s" % root_type)
		root_node.name = root_name

		# Pack into scene
		var packed_scene := PackedScene.new()
		packed_scene.pack(root_node)
		var err: int = ResourceSaver.save(packed_scene, file_path)
		if err != OK:
			root_node.queue_free()
			return MCPTool.error_result("Failed to save scene: %s (error: %s)" % [file_path, error_string(err)])
		root_node.queue_free()

		# Refresh filesystem and open the new scene
		EditorInterface.get_resource_filesystem().scan()
		EditorInterface.open_scene_from_path(file_path)

		return MCPTool.text_result("Scene created and opened: %s (root: %s/%s)" % [file_path, root_type, root_name])


## --- project_run ---
class ProjectRunTool extends MCPTool:
	func _init() -> void:
		super._init(
			"project_run",
			"Run the current project in the editor",
			{
				"type": "object",
				"properties": {},
			},
			false  # modifies editor state
		)

	func execute(_arguments: Dictionary) -> Dictionary:
		EditorInterface.play_current_scene()
		return MCPTool.text_result("Project started")


## --- project_stop ---
class ProjectStopTool extends MCPTool:
	func _init() -> void:
		super._init(
			"project_stop",
			"Stop the currently running project",
			{
				"type": "object",
				"properties": {},
			},
			false  # modifies editor state
		)

	func execute(_arguments: Dictionary) -> Dictionary:
		EditorInterface.stop_playing_scene()
		return MCPTool.text_result("Project stopped")


## --- refresh_filesystem ---
class RefreshFilesystemTool extends MCPTool:
	func _init() -> void:
		super._init(
			"refresh_filesystem",
			"Refresh the Godot editor's filesystem. Call this after modifying files outside the editor (e.g. via external tools like Claude Code's native Edit) so Godot detects the changes.",
			{
				"type": "object",
				"properties": {},
			},
			false  # triggers scan
		)

	func execute(_arguments: Dictionary) -> Dictionary:
		EditorInterface.get_resource_filesystem().scan()
		return MCPTool.text_result("Filesystem scan triggered successfully")


## --- project_structure ---
class ProjectStructureTool extends MCPTool:
	func _init() -> void:
		super._init(
			"project_structure",
			"Get the project's file and directory structure",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "Starting directory path (default: 'res://')",
						"default": "res://",
					},
					"max_depth": {
						"type": "integer",
						"description": "Maximum recursion depth (default: 3, max: 10)",
						"default": 3,
					},
				},
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var path: String = arguments.get("path", "res://")
		var max_depth: int = arguments.get("max_depth", 3)

		# Clamp max_depth
		max_depth = clampi(max_depth, 1, 10)

		var structure := _scan_directory(path, 0, max_depth)
		if structure.is_empty():
			return MCPTool.error_result("Directory not found or empty: %s" % path)

		return MCPTool.text_result(JSON.stringify(structure, "\t"))

	func _scan_directory(path: String, current_depth: int, max_depth: int) -> Dictionary:
		var dir := DirAccess.open(path)
		if dir == null:
			return {}

		var result: Dictionary = {
			"path": path,
			"directories": [],
			"files": [],
		}

		# List files and directories
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			# Skip hidden files and .import files
			if not file_name.begins_with("."):
				if dir.current_is_dir():
					var sub_path: String = path.path_join(file_name)
					if current_depth < max_depth - 1:
						var sub_result := _scan_directory(sub_path, current_depth + 1, max_depth)
						result["directories"].append(sub_result)
					else:
						result["directories"].append({"path": sub_path, "directories": [], "files": []})
				else:
					result["files"].append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

		return result


## --- search_files ---
class SearchFilesTool extends MCPTool:
	func _init() -> void:
		super._init(
			"search_files",
			"Search for text patterns across project files (supports regex; invalid regex is treated as literal string)",
			{
				"type": "object",
				"properties": {
					"pattern": {
						"type": "string",
						"description": "Search pattern (regex supported; invalid regex treated as literal string)",
					},
					"directory": {
						"type": "string",
						"description": "Starting directory to search (default: 'res://')",
						"default": "res://",
					},
					"file_types": {
						"type": "array",
						"description": "File extensions to include (e.g. ['.gd', '.tscn', '.gdshader']). Default: ['.gd', '.gdshader', '.tscn', '.tres', '.md']",
						"default": [],
					},
					"max_results": {
						"type": "integer",
						"description": "Maximum number of results to return (default: 50)",
						"default": 50,
					},
				},
				"required": ["pattern"],
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var pattern: String = arguments.get("pattern", "")
		var directory: String = arguments.get("directory", "res://")
		var file_types: Array = arguments.get("file_types", [])
		var max_results: int = arguments.get("max_results", 50)

		if pattern.is_empty():
			return MCPTool.error_result("Missing required parameter: pattern")

		# Default file types if none specified
		if file_types.is_empty():
			file_types = [".gd", ".gdshader", ".tscn", ".tres", ".md"]

		var results: Array = []
		_search_recursive(directory, pattern, file_types, max_results, results)

		if results.is_empty():
			return MCPTool.text_result("No matches found for pattern: %s" % pattern)

		return MCPTool.text_result(JSON.stringify(results, "\t"))

	func _search_recursive(dir_path: String, pattern: String, file_types: Array, max_results: int, results: Array) -> void:
		if results.size() >= max_results:
			return

		var dir := DirAccess.open(dir_path)
		if dir == null:
			return

		dir.list_dir_begin()
		var item_name: String = dir.get_next()
		while item_name != "" and results.size() < max_results:
			# Skip hidden/import directories
			if item_name.begins_with(".") or item_name == ".import":
				item_name = dir.get_next()
				continue

			var full_path: String = dir_path.path_join(item_name)

			if dir.current_is_dir():
				_search_recursive(full_path, pattern, file_types, max_results, results)
			else:
				# Check if file matches requested types
				var matches_type: bool = false
				for ext in file_types:
					if item_name.ends_with(ext):
						matches_type = true
						break
				if not matches_type:
					item_name = dir.get_next()
					continue

				# Search within file
				_search_in_file(full_path, pattern, max_results, results)
			item_name = dir.get_next()
		dir.list_dir_end()

	func _search_in_file(file_path: String, pattern: String, max_results: int, results: Array) -> void:
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			return

		# Compile regex pattern
		var regex := RegEx.new()
		if regex.compile(pattern) != OK:
			# If pattern is not valid regex, escape special chars for literal search
			var escaped := ""
			for ch in pattern:
				if ch in "\\[]().*+?^$|{}":
					escaped += "\\" + ch
				else:
					escaped += ch

			if regex.compile(escaped) != OK:
				file.close()
				return

		var line_number: int = 0
		var matches: Array = []
		while not file.eof_reached() and results.size() + matches.size() < max_results:
			var line: String = file.get_line()
			line_number += 1
			if regex.search(line) != null:
				matches.append({
					"line": line_number,
					"text": line.strip_edges(),
				})
		file.close()

		if not matches.is_empty():
			results.append({
				"file": file_path,
				"matches": matches,
			})


## --- get_class_documentation ---
class GetClassDocumentationTool extends MCPTool:
	func _init() -> void:
		super._init(
			"get_class_documentation",
			"Get documentation for a Godot built-in class (methods, properties, signals, constants, enums)",
			{
				"type": "object",
				"properties": {
					"classname": {
						"type": "string",
						"description": "Name of the Godot class to query (e.g. 'Node2D', 'Sprite2D', 'CharacterBody2D')",
					},
					"category": {
						"type": "string",
						"description": "What to return: 'methods', 'properties', 'signals', 'constants', 'enums', 'all' (default: 'all')",
						"default": "all",
					},
				},
				"required": ["classname"],
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var gdclass: String = arguments.get("classname", "")
		var category: String = arguments.get("category", "all")

		if gdclass.is_empty():
			return MCPTool.error_result("Missing required parameter: classname")

		# Check if class exists
		if not ClassDB.class_exists(gdclass):
			return MCPTool.error_result("Class not found: %s" % gdclass)

		var result: Dictionary = {
			"class": gdclass,
			"inherits": ClassDB.get_parent_class(gdclass),
			"is_instantiable": ClassDB.can_instantiate(gdclass),
		}

		# Get inherited classes chain
		var inheritance_chain: Array = []
		var parent: String = ClassDB.get_parent_class(gdclass)
		while not parent.is_empty():
			inheritance_chain.append(parent)
			parent = ClassDB.get_parent_class(parent)
		result["inheritance_chain"] = inheritance_chain

		if category == "methods" or category == "all":
			var methods: Array = []
			for method in ClassDB.class_get_method_list(gdclass, true):
				methods.append({
					"name": method["name"],
					"return_type": type_string(method.get("return", {}).get("type", TYPE_NIL)),
					"args": _format_method_args(method),
				})
			result["methods"] = methods

		if category == "properties" or category == "all":
			var properties: Array = []
			for prop in ClassDB.class_get_property_list(gdclass, true):
				properties.append({
					"name": prop["name"],
					"type": type_string(prop.get("type", TYPE_NIL)),
					"hint": prop.get("hint", 0),
					"hint_string": prop.get("hint_string", ""),
				})
			result["properties"] = properties

		if category == "signals" or category == "all":
			var signals: Array = []
			for sig in ClassDB.class_get_signal_list(gdclass, true):
				signals.append({
					"name": sig["name"],
					"args": _format_signal_args(sig),
				})
			result["signals"] = signals

		if category == "constants" or category == "all":
			var constants: Array = []
			for const_item in ClassDB.class_get_integer_constant_list(gdclass, true):
				var const_value: int = ClassDB.class_get_integer_constant(gdclass, const_item)
				constants.append({
					"name": const_item,
					"value": const_value,
				})
			result["constants"] = constants

		if category == "enums" or category == "all":
			var enums: Array = []
			for enum_name in ClassDB.class_get_enum_list(gdclass, true):
				var enum_values: Array = []
				for enum_val in ClassDB.class_get_enum_constants(gdclass, enum_name, true):
					enum_values.append({
						"name": enum_val,
						"value": ClassDB.class_get_integer_constant(gdclass, enum_val),
					})
				enums.append({
					"name": enum_name,
					"values": enum_values,
				})
			result["enums"] = enums

		return MCPTool.text_result(JSON.stringify(result, "\t"))

	func _format_method_args(method: Dictionary) -> Array:
		var args: Array = []
		var arg_list: Array = method.get("args", [])
		for arg in arg_list:
			args.append({
				"name": arg.get("name", ""),
				"type": type_string(arg.get("type", TYPE_NIL)),
			})
		return args

	func _format_signal_args(sig: Dictionary) -> Array:
		var args: Array = []
		var arg_list: Array = sig.get("args", [])
		for arg in arg_list:
			args.append({
				"name": arg.get("name", ""),
				"type": type_string(arg.get("type", TYPE_NIL)),
			})
		return args


## --- get_project_info ---
class GetProjectInfoTool extends MCPTool:
	func _init() -> void:
		super._init(
			"get_project_info",
			"Get engine version, project settings, and system information",
			{
				"type": "object",
				"properties": {},
			}
		)

	func execute(_arguments: Dictionary) -> Dictionary:
		var result: Dictionary = {}

		# Engine info
		result["engine"] = {
			"version": Engine.get_version_info().get("string", ""),
			"architecture": Engine.get_architecture_name(),
			"is_editor": Engine.is_editor_hint(),
		}

		# Project info
		result["project"] = {
			"name": ProjectSettings.get_setting("application/config/name", ""),
			"description": ProjectSettings.get_setting("application/config/description", ""),
			"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
			"project_dir": ProjectSettings.globalize_path("res://"),
		}

		# Display/window settings
		result["window"] = {
			"size": {
				"width": ProjectSettings.get_setting("display/window/size/viewport_width", 0),
				"height": ProjectSettings.get_setting("display/window/size/viewport_height", 0),
			},
			"mode": ProjectSettings.get_setting("display/window/size/mode", 0),
			"stretch_mode": ProjectSettings.get_setting("display/window/stretch/mode", 0),
			"stretch_aspect": ProjectSettings.get_setting("display/window/stretch/aspect", 0),
		}

		# Physics settings
		result["physics"] = {
			"2d_engine": ProjectSettings.get_setting("physics/2d/engine", "DEFAULT"),
			"3d_engine": ProjectSettings.get_setting("physics/3d/engine", "DEFAULT"),
		}

		# Rendering settings
		result["rendering"] = {
			"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_engine", ""),
			"vsync_mode": ProjectSettings.get_setting("display/window/vsync/vsync_mode", 1),
		}

		# Autoloads
		var autoloads: Array = []
		for key in ProjectSettings.get_property_list():
			var prop_name: String = key.get("name", "")
			if prop_name.begins_with("autoload/"):
				var autoload_name: String = prop_name.get_slice("/", 1)
				var autoload_path: String = ProjectSettings.get_setting(prop_name, "")
				autoloads.append({
					"name": autoload_name,
					"path": autoload_path,
				})
		result["autoloads"] = autoloads

		return MCPTool.text_result(JSON.stringify(result, "\t"))