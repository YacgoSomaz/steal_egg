extends Node
## JSON 存档。文件名固定，**目录不固定** —— 见 _resolve_save_path()。

const SAVE_FILE := "egg_runner_save.json"

## 工程内锚定的存档目录（相对工程根）。
const SAVE_DIR_IN_PROJECT := "Godot/app_userdata/偷蛋长跑"

## 解析后的绝对存档路径，惰性缓存。
var _save_path := ""

## 自检模式。打开之后 save() 变成空操作，**一个字节都不会写进玩家存档**。
##
## 为什么需要这个开关：自检要走真实代码路径（购买、撤离、被抓都会触发 save），
## 靠"跑完再还原"是不可靠的——中途出错、进程被杀、玩家同时在玩，
## 都会把测试数据留在档里。之前就真的把玩家的档写成过 coins: 999479。
## **只要测试碰得到会存档的代码，就必须先打开这个开关。**
var test_mode := false


func _ready() -> void:
	load_game()


## 存档到底放在哪。
##
## 为什么不能直接用 user://：
##   正常情况下 user:// 会解析成 %APPDATA%/Godot/app_userdata/<工程名> 这个绝对路径。
##   但本机的启动环境里 APPDATA 是**空**的，Godot 于是把它拼成
##   相对路径 "./Godot/app_userdata/偷蛋长跑"，而相对路径是跟着
##   「进程工作目录」走的 —— 换个目录启动 = 换一份存档。
##   玩家自己双击启动看到的空档，就是这么来的（表现为"进度归零"）。
##
## 所以这里显式锚定到工程目录，让存档位置和启动方式彻底无关。
## 导出成 .pck 之后 res:// 不再是真实目录，那时才退回引擎默认的 user://。
func save_path() -> String:
	if _save_path.is_empty():
		_save_path = _resolve_save_path()
	return _save_path


func _resolve_save_path() -> String:
	var res_dir := ProjectSettings.globalize_path("res://")
	if res_dir != "" and DirAccess.dir_exists_absolute(res_dir):
		return res_dir.path_join(SAVE_DIR_IN_PROJECT).path_join(SAVE_FILE)
	return "user://" + SAVE_FILE


func save() -> void:
	if test_mode:
		return
	var data := {
		"speed_level": GameState.speed_level,
		"stealth_level": GameState.stealth_level,
		"shoe_level": GameState.shoe_level,
		"gear_cloak": GameState.gear_cloak,
		"gear_jet": GameState.gear_jet,
		"catch_count": GameState.catch_count,
		"coins": GameState.coins,
		"best_distance": GameState.best_distance,
		"total_eggs": GameState.total_eggs,
		"total_caught": GameState.total_caught,
		"stored": GameState.stored,
		"farm": GameState.farm,
	}
	var path := save_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()


func load_game() -> void:
	var path := save_path()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("[存档] 没有存档，从头开始（位置 %s）" % path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	GameState.speed_level = int(d.get("speed_level", 0))
	GameState.stealth_level = int(d.get("stealth_level", 0))
	GameState.shoe_level = int(d.get("shoe_level", 0))
	GameState.gear_cloak = int(d.get("gear_cloak", 0))
	GameState.gear_jet = int(d.get("gear_jet", 0))
	GameState.catch_count = int(d.get("catch_count", 0))
	GameState.coins = float(d.get("coins", 0.0))
	GameState.best_distance = float(d.get("best_distance", 0.0))
	GameState.total_eggs = int(d.get("total_eggs", 0))
	GameState.total_caught = int(d.get("total_caught", 0))
	GameState.stored = _to_dict_array(d.get("stored", []))
	GameState.farm = _to_dict_array(d.get("farm", []))
	print("[存档] 已载入：速度 Lv%d / 隐蔽 Lv%d / 被抓 %d 次 / %.0f 金币 / 农场 %d 只"
		% [GameState.speed_level, GameState.stealth_level,
		   GameState.catch_count, GameState.coins, GameState.farm.size()])
	print("[存档] 位置：%s" % path)


## JSON 解出来是 untyped Array，直接赋给 Array[Dictionary] 会被类型检查拦下
func _to_dict_array(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for item in (raw as Array):
			if item is Dictionary:
				out.append(item)
	return out


func wipe() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path()))
	GameState.speed_level = 0
	GameState.stealth_level = 0
	GameState.shoe_level = 0
	GameState.gear_cloak = 0
	GameState.gear_jet = 0
	GameState.catch_count = 0
	GameState.coins = 0.0
	GameState.best_distance = 0.0
	GameState.total_eggs = 0
	GameState.total_caught = 0
	GameState.stored = []
	GameState.farm = []
	GameState.carried = []
	print("[存档] 已清空")
