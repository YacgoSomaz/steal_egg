@tool
class_name ToolUtils
extends RefCounted
## Shared utility functions used across multiple tool files.
## Centralizes node path resolution and node info extraction to avoid code duplication.


## Safely get a node by path string.
## If the path is not found, tries to resolve relative to the edited scene root.
static func get_node_by_path(path: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var root := tree.root
	if root == null:
		return null

	# Try direct path first (e.g. "/root/Node2D/Sprite")
	var node: Node = root.get_node_or_null(path)
	if node != null:
		return node

	# If not found, try resolving relative to the edited scene root
	var edited_root := EditorInterface.get_edited_scene_root()
	if edited_root != null:
		var root_path: String = str(edited_root.get_path())

		# Check if path matches the root node name itself (e.g. "Node2D" == root name)
		if path == str(edited_root.name):
			return edited_root

		# If path doesn't start with /root/, try prepending the scene root path
		if not path.begins_with("/root/"):
			var full_path: String = root_path + "/" + path
			node = root.get_node_or_null(full_path)
			if node != null:
				return node

	return null


## Get the scene root name for error messages.
static func get_edited_scene_root_path() -> String:
	var edited_root := EditorInterface.get_edited_scene_root()
	if edited_root == null:
		return ""
	return str(edited_root.name)


## Get node info as a serializable dictionary.
static func get_node_info(node: Node) -> Dictionary:
	var info: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"path": get_relative_path(node),
		"child_count": node.get_child_count(),
		"visible": node.is_visible_in_tree() if node is CanvasItem else null,
		"scene_file_path": node.scene_file_path if node.scene_file_path else "",
	}
	# Add owner info if available
	if node.owner:
		info["owner_path"] = get_relative_path(node.owner)
	return info


## Get a human-readable relative path for a node (relative to edited scene root).
## Falls back to the full absolute path if the scene root is not available.
static func get_relative_path(node: Node) -> String:
	var edited_root := EditorInterface.get_edited_scene_root()
	if edited_root == null:
		return str(node.get_path())
	var root_path: String = str(edited_root.get_path())
	var node_path: String = str(node.get_path())
	if node_path.begins_with(root_path + "/"):
		return node_path.substr(root_path.length() + 1)
	if node_path == root_path:
		return str(edited_root.name)
	return node_path


## Set owner recursively for scene persistence.
## Critical for nodes to be saved when the scene is saved.
static func set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		set_owner_recursive(child, owner)


## Mark the current scene as unsaved so the editor shows the (*) indicator
## and prompts to save on exit. Must be called after any scene tree modification.
static func mark_scene_as_unsaved() -> void:
	EditorInterface.mark_scene_as_unsaved()
