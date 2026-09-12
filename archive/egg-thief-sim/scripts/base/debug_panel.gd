extends HBoxContainer
## 调试面板：一键解锁内容，方便跳过前期直接体验各生态阶
## 正式发布时，删掉 base.gd 里创建它的那两行即可

signal changed()

const EggDB := preload("res://scripts/data/egg_db.gd")


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var hint := Label.new()
	hint.text = "调试："
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)
	_btn("解锁全部阶位", _unlock_all)
	_btn("+100 基因点", _add_points)
	_btn("属性拉满", _max_stats)
	_btn("给 5 颗蛋", _give_eggs)
	_btn("清空存档", _wipe)


func _btn(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	add_child(b)


func _unlock_all() -> void:
	GameState.unlocked_tier = 10
	GameState.gene_points += 500
	changed.emit()


func _add_points() -> void:
	GameState.gene_points += 100
	changed.emit()


func _max_stats() -> void:
	GameState.stealth_level = GameState.MAX_LEVEL
	GameState.speed_level = GameState.MAX_LEVEL
	changed.emit()


func _give_eggs() -> void:
	for _i in 5:
		var d: Dictionary = EggDB.roll_egg(GameState.unlocked_tier)
		GameState.stored_eggs.append({
			"name": d.get("name", "蛋"),
			"tier": d.get("tier", 1),
			"value": d.get("value", 1),
			"hatch_time": d.get("hatch_time", 20.0),
			"quality_name": d.get("quality_name", "普通"),
			"quality_mult": d.get("quality_mult", 1.0),
		})
	changed.emit()


func _wipe() -> void:
	SaveManager.wipe()
	changed.emit()
