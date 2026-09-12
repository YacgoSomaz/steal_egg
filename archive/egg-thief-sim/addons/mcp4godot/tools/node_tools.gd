@tool
class_name NodeTools
extends RefCounted
## Provides MCP tool instances for node operations: get, get_children, create, delete, move, rename,
## script attach/detach.
## Shared utilities are in ToolUtils.


## Return all node tool instances for registration.
func get_tools() -> Array[MCPTool]:
	return [
		NodeGetTool.new(),
		NodeGetChildrenTool.new(),
		NodeCreateTool.new(),
		NodeDeleteTool.new(),
		NodeMoveTool.new(),
		NodeRenameTool.new(),
		ScriptAttachTool.new(),
		ScriptDetachTool.new(),
	]


## --- node_get ---
class NodeGetTool extends MCPTool:
	func _init() -> void:
		super._init(
			"node_get",
			"Get detailed information about a node in the current scene tree by its NodePath",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "NodePath of the node. Use relative path from scene root (e.g. 'Player', 'Player/Sprite2D'). Absolute paths also work.",
					},
				},
				"required": ["path"],
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var path: String = arguments.get("path", "")
		if path.is_empty():
			return MCPTool.error_result("Missing required parameter: path")

		var node := ToolUtils.get_node_by_path(path)
		if node == null:
			var root_hint: String = ToolUtils.get_edited_scene_root_path()
			var hint: String = ""
			if root_hint.is_empty():
				hint = " No scene is currently open in the editor."
			else:
				hint = " Current scene root: %s" % root_hint
			return MCPTool.error_result("Node not found at path: %s.%s" % [path, hint])

		var info := ToolUtils.get_node_info(node)
		return MCPTool.text_result(JSON.stringify(info, "\t"))


## --- node_get_children ---
class NodeGetChildrenTool extends MCPTool:
	func _init() -> void:
		super._init(
			"node_get_children",
			"List all children of a node in the scene tree",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "NodePath of the parent node. Use relative path from scene root (e.g. 'Node2D', 'Player').",
					},
					"recursive": {
						"type": "boolean",
						"description": "If true, include all descendants recursively",
						"default": false,
					},
				},
				"required": ["path"],
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var path: String = arguments.get("path", "")
		var recursive: bool = arguments.get("recursive", false)
		if path.is_empty():
			return MCPTool.error_result("Missing required parameter: path")

		var node := ToolUtils.get_node_by_path(path)
		if node == null:
			var root_hint: String = ToolUtils.get_edited_scene_root_path()
			var hint: String = ""
			if root_hint.is_empty():
				hint = " No scene is currently open in the editor."
			else:
				hint = " Current scene root: %s" % root_hint
			return MCPTool.error_result("Node not found at path: %s.%s" % [path, hint])

		var children: Array = _collect_children(node, recursive)
		return MCPTool.text_result(JSON.stringify(children, "\t"))

	func _collect_children(node: Node, recursive: bool) -> Array:
		var result: Array = []
		for child in node.get_children():
			var child_info: Dictionary = {
				"name": child.name,
				"type": child.get_class(),
				"path": ToolUtils.get_relative_path(child),
			}
			result.append(child_info)
			if recursive:
				result.append_array(_collect_children(child, true))
		return result


## --- node_create ---
class NodeCreateTool extends MCPTool:
	func _init() -> void:
		super._init(
			"node_create",
			"Create a new node and add it as a child of the specified parent node",
			{
				"type": "object",
				"properties": {
					"parent_path": {
						"type": "string",
						"description": "NodePath of the parent node to add the new node to",
					},
					"node_type": {
						"type": "string",
						"description": "Class name of the node to create (e.g. 'Node2D', 'Sprite2D', 'Label', 'RigidBody3D'), or a res:// path to a PackedScene to instantiate",
					},
					"node_name": {
						"type": "string",
						"description": "Name for the new node. If omitted, the class name will be used.",
					},
				},
				"required": ["parent_path", "node_type"],
			},
			false  # creates node
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var parent_path: String = arguments.get("parent_path", "")
		var node_type: String = arguments.get("node_type", "")
		var node_name: String = arguments.get("node_name", "")

		if parent_path.is_empty():
			return MCPTool.error_result("Missing required parameter: parent_path")
		if node_type.is_empty():
			return MCPTool.error_result("Missing required parameter: node_type")

		# Get parent node
		var parent := ToolUtils.get_node_by_path(parent_path)
		if parent == null:
			return MCPTool.error_result("Parent node not found at path: %s" % parent_path)

		var node: Node = null

		# Check if node_type is a PackedScene path (res://)
		if node_type.begins_with("res://"):
			if not FileAccess.file_exists(node_type):
				return MCPTool.error_result("Scene file not found: %s" % node_type)
			var packed_scene: PackedScene = load(node_type)
			if packed_scene == null:
				return MCPTool.error_result("Failed to load PackedScene: %s" % node_type)
			node = packed_scene.instantiate()
			if node == null:
				return MCPTool.error_result("Failed to instantiate PackedScene: %s" % node_type)
		else:
			# Validate class exists
			if not ClassDB.class_exists(node_type):
				return MCPTool.error_result("Unknown class: %s" % node_type)

			# Validate it's a Node type
			if not ClassDB.is_parent_class(node_type, "Node"):
				return MCPTool.error_result("Class '%s' is not a Node type" % node_type)

			# Instantiate the node
			node = ClassDB.instantiate(node_type) as Node
			if node == null:
				return MCPTool.error_result("Failed to instantiate class: %s" % node_type)

		# Set name
		if not node_name.is_empty():
			node.name = node_name
		else:
			# Use scene file name or class name
			if node_type.begins_with("res://"):
				node.name = node_type.get_file().get_basename()
			else:
				node.name = node_type

		# Add to parent
		parent.add_child(node)

		# Set owner for scene persistence (critical for saving to .tscn)
		var edited_root := EditorInterface.get_edited_scene_root()
		if edited_root:
			node.owner = edited_root
			# Also set owner for any auto-created sub-nodes
			ToolUtils.set_owner_recursive(node, edited_root)

		var info := ToolUtils.get_node_info(node)
		ToolUtils.mark_scene_as_unsaved()
		return MCPTool.text_result("Node created successfully:\n" + JSON.stringify(info, "\t"))


## --- node_delete ---
class NodeDeleteTool extends MCPTool:
	func _init() -> void:
		super._init(
			"node_delete",
			"Remove and free a node from the scene tree",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "NodePath of the node to delete. Use relative path from scene root.",
					},
				},
				"required": ["path"],
			},
			false  # deletes node
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var path: String = arguments.get("path", "")
		if path.is_empty():
			return MCPTool.error_result("Missing required parameter: path")

		var node := ToolUtils.get_node_by_path(path)
		if node == null:
			var root_hint: String = ToolUtils.get_edited_scene_root_path()
			var hint: String = ""
			if root_hint.is_empty():
				hint = " No scene is currently open in the editor."
			else:
				hint = " Current scene root: %s" % root_hint
			return MCPTool.error_result("Node not found at path: %s.%s" % [path, hint])

		# Don't allow deleting the root node
		var tree := Engine.get_main_loop() as SceneTree
		if tree and node == tree.root:
			return MCPTool.error_result("Cannot delete the root node")

		var node_name: String = node.name
		var parent := node.get_parent()
		if parent:
			parent.remove_child(node)
		node.queue_free()

		ToolUtils.mark_scene_as_unsaved()
		return MCPTool.text_result("Node '%s' deleted successfully" % node_name)


## --- node_move ---
class NodeMoveTool extends MCPTool:
	func _init() -> void:
		super._init(
			"node_move",
			"Move a node from its current parent to a new parent (reparent)",
			{
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "NodePath of the node to move. Use relative path from scene root.",
					},
					"new_parent_path": {
						"type": "string",
						"description": "NodePath of the new parent node. Use relative path from scene root.",
					},
					"child_index": {
						"type": "integer",
						"description": "Position among siblings (0-based). Omit to append at end.",
					},
				},
				"required": ["node_path", "new_parent_path"],
			},
			false  # modifies scene tree
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var node_path: String = arguments.get("node_path", "")
		var new_parent_path: String = arguments.get("new_parent_path", "")
		var child_index: int = arguments.get("child_index", -1)

		if node_path.is_empty():
			return MCPTool.error_result("Missing required parameter: node_path")
		if new_parent_path.is_empty():
			return MCPTool.error_result("Missing required parameter: new_parent_path")

		var node := ToolUtils.get_node_by_path(node_path)
		if node == null:
			return MCPTool.error_result("Node not found at path: %s" % node_path)

		var new_parent := ToolUtils.get_node_by_path(new_parent_path)
		if new_parent == null:
			return MCPTool.error_result("New parent node not found at path: %s" % new_parent_path)

		# Prevent moving a node to be a child of itself
		if new_parent == node or new_parent.is_ancestor_of(node):
			# Actually reparenting a parent to its child is bad, but moving up is fine
			# Check if new_parent is a descendant of node
			if node.is_ancestor_of(new_parent):
				return MCPTool.error_result("Cannot move a node to be a child of its own descendant")

		var old_parent := node.get_parent()
		if old_parent:
			old_parent.remove_child(node)

		new_parent.add_child(node)

		# Set position among siblings if specified
		if child_index >= 0 and child_index < new_parent.get_child_count():
			new_parent.move_child(node, child_index)

		# Update owner for scene persistence
		var edited_root := EditorInterface.get_edited_scene_root()
		if edited_root:
			node.owner = edited_root

		ToolUtils.mark_scene_as_unsaved()
		return MCPTool.text_result("Node '%s' moved to '%s'" % [node.name, new_parent.name])


## --- node_rename ---
class NodeRenameTool extends MCPTool:
	func _init() -> void:
		super._init(
			"node_rename",
			"Rename a node in the scene tree",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "NodePath of the node to rename. Use relative path from scene root.",
					},
					"new_name": {
						"type": "string",
						"description": "New name for the node",
					},
				},
				"required": ["path", "new_name"],
			},
			false  # modifies scene tree
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var path: String = arguments.get("path", "")
		var new_name: String = arguments.get("new_name", "")

		if path.is_empty():
			return MCPTool.error_result("Missing required parameter: path")
		if new_name.is_empty():
			return MCPTool.error_result("Missing required parameter: new_name")

		var node := ToolUtils.get_node_by_path(path)
		if node == null:
			return MCPTool.error_result("Node not found at path: %s" % path)

		var old_name: String = node.name
		node.name = new_name

		var info := ToolUtils.get_node_info(node)
		ToolUtils.mark_scene_as_unsaved()
		return MCPTool.text_result("Node renamed from '%s' to '%s':\n%s" % [old_name, new_name, JSON.stringify(info, "\t")])


## --- script_attach ---
class ScriptAttachTool extends MCPTool:
	func _init() -> void:
		super._init(
			"script_attach",
			"Attach a script to a node in the scene tree",
			{
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "NodePath of the node. Use relative path from scene root (e.g. 'Player').",
					},
					"script_path": {
						"type": "string",
						"description": "Path to the GDScript file (e.g. 'res://scripts/player.gd')",
					},
				},
				"required": ["node_path", "script_path"],
			},
			false  # modifies node
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var node_path: String = arguments.get("node_path", "")
		var script_path: String = arguments.get("script_path", "")

		if node_path.is_empty():
			return MCPTool.error_result("Missing required parameter: node_path")
		if script_path.is_empty():
			return MCPTool.error_result("Missing required parameter: script_path")

		var node := ToolUtils.get_node_by_path(node_path)
		if node == null:
			return MCPTool.error_result("Node not found at path: %s" % node_path)

		# Check if script file exists
		if not FileAccess.file_exists(script_path):
			return MCPTool.error_result("Script file not found: %s" % script_path)

		# Check if node already has a script
		if node.get_script() != null:
			return MCPTool.error_result("Node '%s' already has a script attached. Detach it first with script_detach." % node.name)

		# Load and attach the script
		var script: Resource = load(script_path)
		if script == null:
			return MCPTool.error_result("Failed to load script: %s" % script_path)

		node.set_script(script)

		ToolUtils.mark_scene_as_unsaved()
		return MCPTool.text_result("Script '%s' attached to node '%s'" % [script_path, node.name])


## --- script_detach ---
class ScriptDetachTool extends MCPTool:
	func _init() -> void:
		super._init(
			"script_detach",
			"Detach the script from a node in the scene tree",
			{
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "NodePath of the node. Use relative path from scene root (e.g. 'Player').",
					},
				},
				"required": ["node_path"],
			},
			false  # modifies node
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var node_path: String = arguments.get("node_path", "")

		if node_path.is_empty():
			return MCPTool.error_result("Missing required parameter: node_path")

		var node := ToolUtils.get_node_by_path(node_path)
		if node == null:
			return MCPTool.error_result("Node not found at path: %s" % node_path)

		# Check if node has a script
		if node.get_script() == null:
			return MCPTool.error_result("Node '%s' does not have a script attached" % node.name)

		var script_path: String = ""
		var script: Script = node.get_script()
		if script and script.resource_path:
			script_path = script.resource_path

		node.set_script(null)
		ToolUtils.mark_scene_as_unsaved()

		if script_path.is_empty():
			return MCPTool.text_result("Script detached from node '%s'" % node.name)
		else:
			return MCPTool.text_result("Script '%s' detached from node '%s'" % [script_path, node.name])
