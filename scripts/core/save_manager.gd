extends Node
## JSON 存档：user://egg_runner_save.json

const SAVE_PATH := "user://egg_runner_save.json"


func _ready() -> void:
	load_game()


func save() -> void:
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
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()


func load_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		print("[存档] 没有存档，从头开始")
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


## JSON 解出来是 untyped Array，直接赋给 Array[Dictionary] 会被类型检查拦下
func _to_dict_array(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for item in (raw as Array):
			if item is Dictionary:
				out.append(item)
	return out


func wipe() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
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
