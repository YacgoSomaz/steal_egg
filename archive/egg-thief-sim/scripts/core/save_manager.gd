extends Node
## 存档：本地 JSON，只保存「基地养成进度」，不保存单局内的运行状态
## 存：属性等级 / 基因点 / 已解锁阶位 / 库存蛋 / 伙伴 / 孵化中 / 图鉴计数

const SAVE_PATH := "user://egg_thief_save.json"
const VERSION := 1


func _ready() -> void:
	load_game()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save() -> void:
	var data := {
		"version": VERSION,
		"stealth_level": GameState.stealth_level,
		"speed_level": GameState.speed_level,
		"gene_points": GameState.gene_points,
		"unlocked_tier": GameState.unlocked_tier,
		"selected_partner": GameState.selected_partner,
		"total_stolen": GameState.total_stolen,
		"stored_eggs": GameState.stored_eggs,
		"partners": GameState.partners,
		"hatching": GameState.hatching,
		"discovered": GameState.discovered,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[存档] 写入失败")
		return
	f.store_string(JSON.stringify(data))
	f.close()


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[存档] 没有找到存档，从头开始")
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_warning("[存档] 解析失败，已忽略")
		return false
	var d: Dictionary = parsed

	GameState.stealth_level = int(d.get("stealth_level", 1))
	GameState.speed_level = int(d.get("speed_level", 1))
	GameState.gene_points = int(d.get("gene_points", 0))
	GameState.unlocked_tier = int(d.get("unlocked_tier", 1))
	GameState.selected_partner = str(d.get("selected_partner", ""))
	GameState.total_stolen = int(d.get("total_stolen", 0))

	# JSON 解出来是 untyped Array，需要重建成 typed Array 再赋值
	GameState.stored_eggs = _to_dict_array(d.get("stored_eggs", []))
	GameState.partners = _to_dict_array(d.get("partners", []))
	GameState.hatching = _to_dict_array(d.get("hatching", []))
	GameState.discovered = d.get("discovered", {}) if d.get("discovered", {}) is Dictionary else {}

	print("[存档] 已载入：隐匿 Lv%d / 速度 Lv%d / %d 基因点 / T%d" % [
		GameState.stealth_level, GameState.speed_level,
		GameState.gene_points, GameState.unlocked_tier,
	])
	return true


func wipe() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		print("[存档] 已清除")


func _to_dict_array(src: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if src is Array:
		for item in src:
			if item is Dictionary:
				out.append(item)
	return out
