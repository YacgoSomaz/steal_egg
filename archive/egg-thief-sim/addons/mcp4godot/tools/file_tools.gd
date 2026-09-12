@tool
class_name FileTools
extends RefCounted
## Provides MCP tool instances for file system operations: read, write, delete, list, exists, copy, move, folder_create.


## Return all file tool instances for registration.
func get_tools() -> Array[MCPTool]:
	return [
		FileReadTool.new(),
		FileWriteTool.new(),
		FileDeleteTool.new(),
		FileListTool.new(),
		FileExistsTool.new(),
		FileCopyTool.new(),
		FileMoveTool.new(),
		FolderCreateTool.new(),
	]


## --- file_read ---
class FileReadTool extends MCPTool:
	func _init() -> void:
		super._init(
			"file_read",
			"Read the contents of a file in the project",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "File path (e.g. 'res://scripts/player.gd')",
					},
				},
				"required": ["path"],
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var path: String = arguments.get("path", "")
		if path.is_empty():
			return MCPTool.error_result("Missing required parameter: path")

		if not FileAccess.file_exists(path):
			return MCPTool.error_result("File not found: %s" % path)

		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return MCPTool.error_result("Failed to open file: %s (error: %s)" % [path, error_string(FileAccess.get_open_error())])

		var content: String = file.get_as_text()
		file.close()

		return MCPTool.text_result(content)


## --- file_write ---
class FileWriteTool extends MCPTool:
	func _init() -> void:
		super._init(
			"file_write",
			"Write content to a file, creating it if it does not exist",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "File path (e.g. 'res://scripts/new_script.gd')",
					},
					"content": {
						"type": "string",
						"description": "Content to write to the file",
					},
				},
				"required": ["path", "content"],
			},
			false  # write tool
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var path: String = arguments.get("path", "")
		var content: String = arguments.get("content", "")

		if path.is_empty():
			return MCPTool.error_result("Missing required parameter: path")

		# Ensure the parent directory exists
		var dir_path: String = path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			var err: int = DirAccess.make_dir_recursive_absolute(dir_path)
			if err != OK:
				return MCPTool.error_result("Failed to create directory: %s (error: %s)" % [dir_path, error_string(err)])

		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return MCPTool.error_result("Failed to open file for writing: %s (error: %s)" % [path, error_string(FileAccess.get_open_error())])

		file.store_string(content)
		file.close()

		# Refresh the editor's resource filesystem so it picks up the new file
		EditorInterface.get_resource_filesystem().scan()

		return MCPTool.text_result("File written successfully: %s (%d bytes)" % [path, content.length()])


## --- file_delete ---
class FileDeleteTool extends MCPTool:
	func _init() -> void:
		super._init(
			"file_delete",
			"Delete a file from the project",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "File path to delete",
					},
				},
				"required": ["path"],
			},
			false  # delete tool
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var path: String = arguments.get("path", "")
		if path.is_empty():
			return MCPTool.error_result("Missing required parameter: path")

		if not FileAccess.file_exists(path):
			return MCPTool.error_result("File not found: %s" % path)

		var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if err != OK:
			return MCPTool.error_result("Failed to delete file: %s (error: %s)" % [path, error_string(err)])

		# Refresh the editor's resource filesystem
		EditorInterface.get_resource_filesystem().scan()

		return MCPTool.text_result("File deleted successfully: %s" % path)


## --- file_list ---
class FileListTool extends MCPTool:
	func _init() -> void:
		super._init(
			"file_list",
			"List files and directories at a given path",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "Directory path (default: 'res://')",
						"default": "res://",
					},
					"recursive": {
						"type": "boolean",
						"description": "If true, list files recursively (default: false)",
						"default": false,
					},
					"max_depth": {
						"type": "integer",
						"description": "Maximum recursion depth when recursive is true (default: 10, max: 10)",
						"default": 10,
					},
				},
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var path: String = arguments.get("path", "res://")
		var recursive: bool = arguments.get("recursive", false)
		var max_depth: int = arguments.get("max_depth", 10)

		var dir := DirAccess.open(path)
		if dir == null:
			return MCPTool.error_result("Directory not found or cannot be opened: %s" % path)

		if recursive:
			var result := _scan_directory(path, 0, clampi(max_depth, 1, 10))
			return MCPTool.text_result(JSON.stringify(result, "\t"))
		else:
			var directories: Array = []
			var files: Array = []

			dir.list_dir_begin()
			var item_name: String = dir.get_next()
			while item_name != "":
				if not item_name.begins_with("."):
					if dir.current_is_dir():
						directories.append(item_name + "/")
					else:
						files.append(item_name)
				item_name = dir.get_next()
			dir.list_dir_end()

			var result: Dictionary = {
				"path": path,
				"directories": directories,
				"files": files,
			}
			return MCPTool.text_result(JSON.stringify(result, "\t"))

	func _scan_directory(dir_path: String, current_depth: int, max_depth: int) -> Dictionary:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			return {"path": dir_path, "directories": [], "files": []}

		var result: Dictionary = {
			"path": dir_path,
			"directories": [],
			"files": [],
		}

		dir.list_dir_begin()
		var item_name: String = dir.get_next()
		while item_name != "":
			if not item_name.begins_with("."):
				var full_path: String = dir_path.path_join(item_name)
				if dir.current_is_dir():
					if current_depth < max_depth - 1:
						var sub_result := _scan_directory(full_path, current_depth + 1, max_depth)
						result["directories"].append(sub_result)
					else:
						result["directories"].append({"path": full_path, "directories": [], "files": []})
				else:
					result["files"].append(item_name)
			item_name = dir.get_next()
		dir.list_dir_end()

		return result


## --- file_exists ---
class FileExistsTool extends MCPTool:
	func _init() -> void:
		super._init(
			"file_exists",
			"Check whether a file or directory exists at the given path",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "Path to check",
					},
				},
				"required": ["path"],
			}
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var path: String = arguments.get("path", "")
		if path.is_empty():
			return MCPTool.error_result("Missing required parameter: path")

		var file_exists: bool = FileAccess.file_exists(path)
		var dir_exists: bool = DirAccess.dir_exists_absolute(path)

		var result: Dictionary = {
			"path": path,
			"exists": file_exists or dir_exists,
			"is_file": file_exists,
			"is_directory": dir_exists,
		}
		return MCPTool.text_result(JSON.stringify(result, "\t"))


## --- file_copy ---
class FileCopyTool extends MCPTool:
	func _init() -> void:
		super._init(
			"file_copy",
			"Copy a file to a new location",
			{
				"type": "object",
				"properties": {
					"source_path": {
						"type": "string",
						"description": "Source file path (e.g. 'res://scripts/player.gd')",
					},
					"dest_path": {
						"type": "string",
						"description": "Destination file path (e.g. 'res://scripts/player_backup.gd')",
					},
				},
				"required": ["source_path", "dest_path"],
			},
			false  # write tool
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var source_path: String = arguments.get("source_path", "")
		var dest_path: String = arguments.get("dest_path", "")

		if source_path.is_empty():
			return MCPTool.error_result("Missing required parameter: source_path")
		if dest_path.is_empty():
			return MCPTool.error_result("Missing required parameter: dest_path")

		if not FileAccess.file_exists(source_path):
			return MCPTool.error_result("Source file not found: %s" % source_path)

		# Ensure the parent directory of dest exists
		var dest_dir: String = dest_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dest_dir):
			var err: int = DirAccess.make_dir_recursive_absolute(dest_dir)
			if err != OK:
				return MCPTool.error_result("Failed to create directory: %s (error: %s)" % [dest_dir, error_string(err)])

		var err: int = DirAccess.copy_absolute(ProjectSettings.globalize_path(source_path), ProjectSettings.globalize_path(dest_path))
		if err != OK:
			return MCPTool.error_result("Failed to copy file: %s -> %s (error: %s)" % [source_path, dest_path, error_string(err)])

		# Refresh the editor's resource filesystem
		EditorInterface.get_resource_filesystem().scan()

		return MCPTool.text_result("File copied successfully: %s -> %s" % [source_path, dest_path])


## --- file_move ---
class FileMoveTool extends MCPTool:
	func _init() -> void:
		super._init(
			"file_move",
			"Move or rename a file to a new location",
			{
				"type": "object",
				"properties": {
					"source_path": {
						"type": "string",
						"description": "Source file path (e.g. 'res://scripts/old_name.gd')",
					},
					"dest_path": {
						"type": "string",
						"description": "Destination file path (e.g. 'res://scripts/new_name.gd')",
					},
				},
				"required": ["source_path", "dest_path"],
			},
			false  # write tool
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var source_path: String = arguments.get("source_path", "")
		var dest_path: String = arguments.get("dest_path", "")

		if source_path.is_empty():
			return MCPTool.error_result("Missing required parameter: source_path")
		if dest_path.is_empty():
			return MCPTool.error_result("Missing required parameter: dest_path")

		if not FileAccess.file_exists(source_path):
			return MCPTool.error_result("Source file not found: %s" % source_path)

		# Ensure the parent directory of dest exists
		var dest_dir: String = dest_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dest_dir):
			var err: int = DirAccess.make_dir_recursive_absolute(dest_dir)
			if err != OK:
				return MCPTool.error_result("Failed to create directory: %s (error: %s)" % [dest_dir, error_string(err)])

		var err: int = DirAccess.rename_absolute(ProjectSettings.globalize_path(source_path), ProjectSettings.globalize_path(dest_path))
		if err != OK:
			return MCPTool.error_result("Failed to move file: %s -> %s (error: %s)" % [source_path, dest_path, error_string(err)])

		# Refresh the editor's resource filesystem
		EditorInterface.get_resource_filesystem().scan()

		return MCPTool.text_result("File moved successfully: %s -> %s" % [source_path, dest_path])


## --- folder_create ---
class FolderCreateTool extends MCPTool:
	func _init() -> void:
		super._init(
			"folder_create",
			"Create a new directory, including any missing parent directories",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "Directory path to create (e.g. 'res://scripts/enemies')",
					},
				},
				"required": ["path"],
			},
			false  # write tool
		)

	func execute(arguments: Dictionary) -> Dictionary:
		var path: String = arguments.get("path", "")
		if path.is_empty():
			return MCPTool.error_result("Missing required parameter: path")

		if DirAccess.dir_exists_absolute(path):
			return MCPTool.error_result("Directory already exists: %s" % path)

		var err: int = DirAccess.make_dir_recursive_absolute(path)
		if err != OK:
			return MCPTool.error_result("Failed to create directory: %s (error: %s)" % [path, error_string(err)])

		# Refresh the editor's resource filesystem
		EditorInterface.get_resource_filesystem().scan()

		return MCPTool.text_result("Directory created successfully: %s" % path)
