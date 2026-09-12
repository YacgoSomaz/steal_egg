@tool
class_name ScriptTools
extends RefCounted
## Provides MCP tool instances for script analysis: read_script_outline, script_validate.


## Return all script tool instances for registration.
func get_tools() -> Array[MCPTool]:
	return [
		ReadScriptOutlineTool.new(),
		ScriptValidateTool.new(),
	]


## --- read_script_outline ---
class ReadScriptOutlineTool extends MCPTool:
	func _init() -> void:
		super._init(
			"read_script_outline",
			"Parse a GDScript file and return a structured outline of its classes, functions, variables, signals, enums, and constants with line numbers",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "Path to the .gd file (e.g. 'res://scripts/player.gd')",
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

		if not path.ends_with(".gd"):
			return MCPTool.error_result("Not a GDScript file: %s" % path)

		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return MCPTool.error_result("Failed to open file: %s" % path)

		var lines: PackedStringArray = file.get_as_text().split("\n")
		file.close()

		var result := _parse_outline(lines)
		result["file"] = path
		result["total_lines"] = lines.size()

		return MCPTool.text_result(JSON.stringify(result, "\t"))

	func _parse_outline(lines: PackedStringArray) -> Dictionary:
		var result: Dictionary = {
			"is_tool": false,
			"class_name": "",
			"extends_class": "",
			"classes": [],
			"functions": [],
			"variables": [],
			"signals": [],
			"enums": [],
			"constants": [],
		}

		var current_class_indent: int = -1
		var brace_depth: int = 0

		for i in range(lines.size()):
			var line: String = lines[i]
			var stripped: String = line.strip_edges(true, false)

			# Skip empty lines and comments
			if stripped.is_empty() or stripped.begins_with("#"):
				continue

			# Calculate indentation (tab = 1 level)
			var indent: int = _count_indent(line)

			# Track brace depth for inner class boundaries
			brace_depth += _count_char(stripped, "{") - _count_char(stripped, "}")

			# Top-level only (indent 0)
			if indent == 0:
				# @tool
				if stripped.begins_with("@tool"):
					result["is_tool"] = true

				# class_name
				elif stripped.begins_with("class_name"):
					var parts := stripped.split(" ")
					if parts.size() >= 2:
						result["class_name"] = parts[1].replace(":", "")

				# extends
				elif stripped.begins_with("extends"):
					var parts := stripped.split(" ")
					if parts.size() >= 2:
						result["extends_class"] = parts[1]

				# Inner class: class_name:
				elif stripped.begins_with("class ") and ":" in stripped:
					var class_info := _parse_class_declaration(stripped, i + 1)
					if not class_info.is_empty():
						result["classes"].append(class_info)

				# Signal
				elif stripped.begins_with("signal "):
					result["signals"].append(_parse_signal(stripped, i + 1))

				# Enum
				elif stripped.begins_with("enum "):
					result["enums"].append(_parse_enum(stripped, i + 1))

				# Const
				elif stripped.begins_with("const "):
					result["constants"].append(_parse_const(stripped, i + 1))

				# Variable (var)
				elif stripped.begins_with("var ") or stripped.begins_with("@") and "var " in stripped:
					result["variables"].append(_parse_variable(stripped, i + 1))

				# Function
				elif stripped.begins_with("func ") or (stripped.begins_with("static ") and "func " in stripped):
					result["functions"].append(_parse_function(stripped, i + 1))

		return result

	func _count_indent(line: String) -> int:
		var count: int = 0
		for ch in line:
			if ch == "\t":
				count += 1
			elif ch == " ":
				# Treat 4 spaces as 1 tab level
				count += 1
			else:
				break
		return count

	func _count_char(s: String, ch: String) -> int:
		var count: int = 0
		for c in s:
			if c == ch[0]:
				count += 1
		return count

	func _parse_class_declaration(stripped: String, line_num: int) -> Dictionary:
		# "class InnerClassName extends BaseClass:" or "class InnerClassName:"
		var regex := RegEx.new()
		regex.compile("class\\s+(\\w+)(?:\\s+extends\\s+(\\w+))?\\s*:")
		var match := regex.search(stripped)
		if match == null:
			return {}
		var info: Dictionary = {
			"name": match.get_string(1),
			"line": line_num,
		}
		if match.get_string(2) != "":
			info["extends"] = match.get_string(2)
		return info

	func _parse_signal(stripped: String, line_num: int) -> Dictionary:
		# "signal my_signal(arg1: int, arg2: String)" or "signal my_signal"
		var regex := RegEx.new()
		regex.compile("signal\\s+(\\w+)(?:\\(([^)]*)\\))?")
		var match := regex.search(stripped)
		if match == null:
			return {"name": stripped.replace("signal ", "").split("(")[0], "line": line_num}
		var info: Dictionary = {
			"name": match.get_string(1),
			"line": line_num,
		}
		var args_str: String = match.get_string(2)
		if not args_str.is_empty():
			info["args"] = args_str.split(",")
		return info

	func _parse_enum(stripped: String, line_num: int) -> Dictionary:
		# "enum State {IDLE, RUN, JUMP}" or "enum State {IDLE = 0, RUN = 1, JUMP = 2}"
		var regex := RegEx.new()
		regex.compile("enum\\s+(\\w+)\\s*\\{([^}]*)\\}")
		var match := regex.search(stripped)
		if match == null:
			return {"name": stripped.replace("enum ", "").split("{")[0].strip_edges(), "line": line_num}
		var info: Dictionary = {
			"name": match.get_string(1),
			"line": line_num,
			"values": [],
		}
		var values_str: String = match.get_string(2)
		for val in values_str.split(","):
			var v: String = val.strip_edges()
			if not v.is_empty():
				# Remove any "= value" part for the name
				var name_only: String = v.split("=")[0].strip_edges()
				info["values"].append(name_only)
		return info

	func _parse_const(stripped: String, line_num: int) -> Dictionary:
		# "const MAX_HEALTH: int = 100" or "const MAX_HEALTH = 100"
		var regex := RegEx.new()
		regex.compile("const\\s+(\\w+)(?::\\s*(\\w+))?(?:\\s*=\\s*(.+))?")
		var match := regex.search(stripped)
		if match == null:
			return {"name": stripped.replace("const ", "").split(":")[0].split("=")[0].strip_edges(), "line": line_num}
		var info: Dictionary = {
			"name": match.get_string(1),
			"line": line_num,
		}
		if match.get_string(2) != "":
			info["type"] = match.get_string(2)
		if match.get_string(3) != "":
			info["value"] = match.get_string(3).strip_edges()
		return info

	func _parse_variable(stripped: String, line_num: int) -> Dictionary:
		# Handle annotations like @export, @onready
		var clean := stripped
		var annotations: Array = []
		while clean.begins_with("@"):
			var space_idx: int = clean.find(" ")
			if space_idx < 0:
				break
			annotations.append(clean.left(space_idx))
			clean = clean.substr(space_idx + 1).strip_edges()

		# "var speed: float = 200.0" or "var speed = 200.0" or "var speed: float"
		var regex := RegEx.new()
		regex.compile("var\\s+(\\w+)(?::\\s*(\\w+))?(?:\\s*=\\s*(.+))?")
		var match := regex.search(clean)
		if match == null:
			return {"name": clean.replace("var ", "").split(":")[0].split("=")[0].strip_edges(), "line": line_num}
		var info: Dictionary = {
			"name": match.get_string(1),
			"line": line_num,
		}
		if match.get_string(2) != "":
			info["type"] = match.get_string(2)
		if match.get_string(3) != "":
			info["default"] = match.get_string(3).strip_edges()
		if not annotations.is_empty():
			info["annotations"] = annotations
		return info

	func _parse_function(stripped: String, line_num: int) -> Dictionary:
		# "func _ready() -> void:" or "static func create() -> Node:" or "func foo():"
		var is_static: bool = stripped.begins_with("static ")
		var clean := stripped
		if is_static:
			clean = stripped.replace("static ", "")

		var regex := RegEx.new()
		regex.compile("func\\s+(\\w+)\\(([^)]*)\\)(?:\\s*->\\s*(\\w+))?\\s*:")
		var match := regex.search(clean)
		if match == null:
			# Fallback: extract just the name
			var name_start: int = clean.find("func ") + 5
			var name_end: int = clean.find("(", name_start)
			if name_end < 0:
				name_end = clean.find(":", name_start)
			var func_name: String = clean.substr(name_start, name_end - name_start).strip_edges() if name_end > name_start else "unknown"
			return {"name": func_name, "line": line_num, "is_static": is_static}
		var info: Dictionary = {
			"name": match.get_string(1),
			"line": line_num,
			"is_static": is_static,
		}
		var args_str: String = match.get_string(2)
		if not args_str.is_empty():
			info["args"] = args_str
		if match.get_string(3) != "":
			info["return_type"] = match.get_string(3)
		return info


## --- script_validate ---
class ScriptValidateTool extends MCPTool:
	func _init() -> void:
		super._init(
			"script_validate",
			"Validate a GDScript file for syntax and type errors using Godot's built-in script validator",
			{
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "Path to the .gd file to validate (e.g. 'res://scripts/player.gd')",
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

		if not path.ends_with(".gd"):
			return MCPTool.error_result("Not a GDScript file: %s" % path)

		# Two-phase validation:
		# 1. Static parse check: load script + reload (detects syntax and type errors)
		# 2. External syntax check: run Godot headless with --log-file (captures detailed errors)
		var static_result := _run_static_parse_check(path)
		var external_result := _run_external_syntax_check(path)

		var combined: String = ""
		var static_line: String = static_result.get("result_text", "").strip_edges()
		var external_line: String = external_result.get("result_text", "").strip_edges()

		if static_line == "" and external_line == "":
			combined = "No errors found"
		elif static_line == "No static parse errors" and external_line == "No syntax errors":
			combined = "No errors found"
		elif static_line != "No static parse errors" or external_line != "No syntax errors":
			combined = "[Static Check]\n%s\n\n[Syntax Check]\n%s" % [static_line, external_line]

		var is_valid: bool = static_result.get("ok", false) and external_result.get("ok", false)

		var result: Dictionary = {
			"path": path,
			"valid": is_valid,
			"result": combined,
			"static_check": static_result,
			"syntax_check": external_result,
		}
		return MCPTool.text_result(JSON.stringify(result, "\t"))

	## Static parse check using ResourceLoader.load + script.reload()
	## Detects syntax and type errors, runs synchronously in the editor process.
	static func _run_static_parse_check(path: String) -> Dictionary:
		var script: GDScript = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if script == null:
			return {
				"ok": false,
				"phase": "static",
				"result_text": "Static check failed: unable to load script",
			}
		var reload_error: int = script.reload()
		if reload_error != OK:
			return {
				"ok": false,
				"phase": "static",
				"error_code": reload_error,
				"result_text": "Static parse error: %s (code %d)" % [error_string(reload_error), reload_error],
			}
		return {
			"ok": true,
			"phase": "static",
			"result_text": "No static parse errors",
		}

	## External syntax check using OS.create_instance() with --headless --check-only --log-file
	## Runs Godot as a child process; captures output via log file.
	## Uses OS.delay_msec() for synchronous polling since MCP execute() cannot await.
	static func _run_external_syntax_check(path: String) -> Dictionary:
		var abs_path: String = ProjectSettings.globalize_path(path)
		var log_path: String = OS.get_cache_dir().path_join("mcp_validate.log")

		# Clean up any previous log file
		if FileAccess.file_exists(log_path):
			DirAccess.remove_absolute(log_path)

		var args: PackedStringArray = [
			"--headless",
			"--script",
			abs_path,
			"--check-only",
			"--log-file",
			log_path,
		]

		var pid: int = OS.create_instance(args)
		if pid <= 0:
			return {
				"ok": false,
				"phase": "syntax",
				"result_text": "Syntax check failed: unable to create child process",
			}

		# Synchronous poll with timeout (max 8 seconds)
		var max_wait_msec: int = 8000
		var start_msec: int = Time.get_ticks_msec()
		var timed_out: bool = false

		while Time.get_ticks_msec() - start_msec < max_wait_msec:
			if not OS.is_process_running(pid):
				break
			OS.delay_msec(100)

		if OS.is_process_running(pid):
			OS.kill(pid)
			timed_out = true

		# Read the log file for error details
		var log_text: String = ""
		if FileAccess.file_exists(log_path):
			var file := FileAccess.open(log_path, FileAccess.READ)
			if file != null:
				log_text = file.get_as_text().strip_edges()
				file.close()
			DirAccess.remove_absolute(log_path)

		if timed_out and log_text == "":
			return {
				"ok": false,
				"phase": "syntax",
				"timed_out": true,
				"result_text": "Syntax check timed out (8s), no log generated",
			}

		# Parse errors from log output
		var errors: Array = []
		for line in log_text.split("\n"):
			var stripped: String = line.strip_edges()
			if stripped.is_empty():
				continue
			if "error" in stripped.to_lower() or "script" in stripped.to_lower():
				errors.append(stripped)

		if log_text == "" or errors.is_empty():
			return {
				"ok": not timed_out,
				"phase": "syntax",
				"timed_out": timed_out,
				"result_text": "No syntax errors",
			}

		return {
			"ok": false,
			"phase": "syntax",
			"timed_out": timed_out,
			"errors": errors,
			"result_text": "\n".join(PackedStringArray(errors)),
		}
