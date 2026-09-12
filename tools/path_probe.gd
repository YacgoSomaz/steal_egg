extends SceneTree

# 诊断用：打印 user:// 到底解析到哪里。
#
# 为什么需要它：这个工程的三份副本（steal_egg / egg-runner / _verify_clone）
# 各自都有一份 egg_runner_save.json，说明 user:// 不是指向
# %APPDATA%/Godot/app_userdata/偷蛋长跑（三份副本本该共用同一份存档）。
# 实测 user:// 返回的是**相对路径** "./Godot/app_userdata/偷蛋长跑"，
# 相对路径会跟着「进程工作目录」跑 —— 换个目录启动 = 换一份存档。
# 那正是玩家看到的「进度归零」的最可能原因。
#
# 用法：
#   Godot.exe --path <工程> --headless --script res://tools/path_probe.gd

const SAVE := "egg_runner_save.json"

func _check(label: String, p: String) -> void:
	print("  %-46s %s" % [label, "有" if FileAccess.file_exists(p) else "无"])

func _init() -> void:
	print("--- path probe ---")
	print("exe              = ", OS.get_executable_path())
	print("res://           = ", ProjectSettings.globalize_path("res://"))
	print("user://          = ", OS.get_user_data_dir())
	print("user:// (绝对)    = ", ProjectSettings.globalize_path("user://"))
	print("APPDATA          = ", OS.get_environment("APPDATA"))
	print("PWD(继承自 shell) = ", OS.get_environment("PWD"))

	print("存档候选位置：")
	_check("user://", "user://" + SAVE)
	_check("./ 相对（工作目录）", "./Godot/app_userdata/偷蛋长跑/" + SAVE)
	_check("res:// 相对（工程根）", "res://Godot/app_userdata/偷蛋长跑/" + SAVE)
	_check("引擎目录旁", OS.get_executable_path().get_base_dir() + "/Godot/app_userdata/偷蛋长跑/" + SAVE)
	_check("%APPDATA%", OS.get_environment("APPDATA") + "/Godot/app_userdata/偷蛋长跑/" + SAVE)
	print("--- end ---")
	quit()
