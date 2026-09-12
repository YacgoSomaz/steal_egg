extends Control
## 农场：把偷回来的蛋变成钱，把钱变成速度和隐蔽
##
## 第二层抉择就在中间那一栏：养着（细水长流）还是卖掉（立刻套现）。
## 养着滚雪球，卖掉解燃眉之急——而「治疗降速」永远在等着花你的钱。

const CreatureDB := preload("res://scripts/data/creature_db.gd")

var _coins: Label
var _stat: Label
var _speed_btn: Button
var _stealth_btn: Button
var _heal_btn: Button
var _shoe_btn: Button
var _cloak_btn: Button
var _jet_btn: Button
var _stored_list: VBoxContainer
var _farm_list: VBoxContainer


func _ready() -> void:
	_build()
	_refresh()


func _process(delta: float) -> void:
	GameState.tick_income(delta)
	_coins.text = "金币 %.0f　（+%.1f / 秒）" % [GameState.coins, GameState.get_income_per_sec()]
	_speed_btn.disabled = GameState.coins < GameState.get_speed_cost() or GameState.speed_level >= 20
	_stealth_btn.disabled = GameState.coins < GameState.get_stealth_cost() or GameState.stealth_level >= 20
	_heal_btn.disabled = GameState.catch_count <= 0 or GameState.coins < GameState.get_heal_cost()
	_shoe_btn.disabled = GameState.shoe_level >= 20 or GameState.coins < GameState.get_shoe_cost()
	_cloak_btn.disabled = GameState.gear_cloak >= 5 or GameState.coins < GameState.get_gear_cost("cloak")
	_jet_btn.disabled = GameState.gear_jet >= 5 or GameState.coins < GameState.get_gear_cost("jet")


# ── UI ─────────────────────────────────────────
func _build() -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 22)
	m.add_theme_constant_override("margin_top", 18)
	m.add_theme_constant_override("margin_right", 22)
	m.add_theme_constant_override("margin_bottom", 18)
	add_child(m)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	m.add_child(root)

	_coins = Label.new()
	_coins.add_theme_font_size_override("font_size", 22)
	root.add_child(_coins)

	_stat = Label.new()
	root.add_child(_stat)
	root.add_child(HSeparator.new())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var up := _col("用钱变强")
	_speed_btn = Button.new()
	_speed_btn.pressed.connect(func():
		if GameState.upgrade_speed():
			_refresh()
	)
	up.add_child(_speed_btn)
	_stealth_btn = Button.new()
	_stealth_btn.pressed.connect(func():
		if GameState.upgrade_stealth():
			_refresh()
	)
	up.add_child(_stealth_btn)
	_heal_btn = Button.new()
	_heal_btn.pressed.connect(func():
		if GameState.heal_penalty():
			_refresh()
	)
	up.add_child(_heal_btn)

	up.add_child(HSeparator.new())

	_shoe_btn = Button.new()
	_shoe_btn.pressed.connect(func():
		if GameState.upgrade_shoe():
			_refresh()
	)
	up.add_child(_shoe_btn)

	_cloak_btn = Button.new()
	_cloak_btn.pressed.connect(func():
		if GameState.upgrade_gear("cloak"):
			_refresh()
	)
	up.add_child(_cloak_btn)

	_jet_btn = Button.new()
	_jet_btn.pressed.connect(func():
		if GameState.upgrade_gear("jet"):
			_refresh()
	)
	up.add_child(_jet_btn)

	var note := Label.new()
	note.text = "四种速度来源，算法各不相同：\n" \
		+ "锻炼　乘算 ×1.09／级，后期收益暴涨\n" \
		+ "跑鞋　加算 +2.5 基础速度，前期救命\n" \
		+ "披风　苏醒延迟 +15%／级，偷完更从容\n" \
		+ "喷气　起步 2.5 秒内 ×1.25／级，开局甩开\n" \
		+ "被抓　乘算 ×0.97／次，可花钱抹掉"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	up.add_child(note)
	cols.add_child(up)

	var st := _col("带回来的蛋")
	var st_scroll := ScrollContainer.new()
	st_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stored_list = VBoxContainer.new()
	_stored_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_scroll.add_child(_stored_list)
	st.add_child(st_scroll)
	cols.add_child(st)

	var fm := _col("农场（产钱中）")
	var fm_scroll := ScrollContainer.new()
	fm_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_farm_list = VBoxContainer.new()
	_farm_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fm_scroll.add_child(_farm_list)
	fm.add_child(fm_scroll)
	cols.add_child(fm)

	root.add_child(HSeparator.new())

	var go := Button.new()
	go.text = "出 击"
	go.custom_minimum_size = Vector2(0, 54)
	go.add_theme_font_size_override("font_size", 20)
	go.pressed.connect(_on_go)
	root.add_child(go)

	root.add_child(_debug_row())


func _col(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 16)
	box.add_child(head)
	return box


## 调试行：T1 草鸡养不出什么花来，给个快进键让人直接看到高阶内容
func _debug_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_dbg_btn("+1000 金币", _dbg_coins.bind(1000.0)))
	row.add_child(_dbg_btn("+50000 金币", _dbg_coins.bind(50000.0)))
	row.add_child(_dbg_btn("属性 +5", _dbg_levels))
	row.add_child(_dbg_btn("降速 +9%", _dbg_hurt))
	row.add_child(_dbg_btn("清空存档", _dbg_wipe))
	return row


func _dbg_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		cb.call()
		_refresh()
	)
	return b


func _dbg_coins(amount: float) -> void:
	GameState.coins += amount


func _dbg_levels() -> void:
	GameState.speed_level = mini(20, GameState.speed_level + 5)
	GameState.stealth_level = mini(20, GameState.stealth_level + 5)


func _dbg_hurt() -> void:
	GameState.apply_penalty()
	GameState.apply_penalty()
	GameState.apply_penalty()


func _dbg_wipe() -> void:
	SaveManager.wipe()


# ── 刷新 ───────────────────────────────────────
func _refresh() -> void:
	GameState.refresh_start_tier()
	_stat.text = "速度 %.0f km/h【%s】（锻炼 Lv%d，×%.2f）｜ 实际 ×%.2f（被抓 %d 次）｜ 隐蔽 Lv%d（苏醒延迟 ×%.2f）｜ 最远 %.0f m ｜ 偷蛋 %d ｜ 被抓 %d ｜ 下趟从 T%d 开门" % [
		GameState.get_display_speed(), GameState.speed_title(GameState.get_display_speed()),
		GameState.speed_level, GameState.get_level_multiplier(),
		GameState.get_penalty_multiplier(), GameState.catch_count,
		GameState.stealth_level, 1.0 + 0.09 * float(GameState.stealth_level),
		GameState.best_distance, GameState.total_eggs, GameState.total_caught,
		GameState.start_tier,
	]
	_speed_btn.text = "锻炼 Lv%d → %d　（速度 ×1.09）　%.0f 金币" % [
		GameState.speed_level, GameState.speed_level + 1, GameState.get_speed_cost()]
	_stealth_btn.text = "隐蔽 Lv%d → %d　（苏醒延迟 +9%%）　%.0f 金币" % [
		GameState.stealth_level, GameState.stealth_level + 1, GameState.get_stealth_cost()]
	_shoe_btn.text = "跑鞋 Lv%d → %d　（基础 +%.1f）　%.0f 金币" % [
		GameState.shoe_level, GameState.shoe_level + 1, GameState.SHOE_BONUS,
		GameState.get_shoe_cost()]
	_cloak_btn.text = "披风 Lv%d → %d　（苏醒延迟 +15%%）　%.0f 金币" % [
		GameState.gear_cloak, GameState.gear_cloak + 1, GameState.get_gear_cost("cloak")]
	_jet_btn.text = "喷气 Lv%d → %d　（起步 ×%.2f）　%.0f 金币" % [
		GameState.gear_jet, GameState.gear_jet + 1,
		1.0 + GameState.JET_PER_LEVEL * float(GameState.gear_jet + 1),
		GameState.get_gear_cost("jet")]
	if GameState.catch_count > 0:
		_heal_btn.text = "治疗：抹掉 %d 次被抓（×%.2f → ×%.2f）　　%.0f 金币" % [
			mini(GameState.HEAL_CATCHES, GameState.catch_count),
			GameState.get_penalty_multiplier(),
			GameState.PENALTY_GROWTH ** float(maxi(0, GameState.catch_count - GameState.HEAL_CATCHES)),
			GameState.get_heal_cost()]
	else:
		_heal_btn.text = "目前没有被抓记录"

	_rebuild_stored()
	_rebuild_farm()
	SaveManager.save()


func _rebuild_stored() -> void:
	for c in _stored_list.get_children():
		c.queue_free()
	if GameState.stored.is_empty():
		var l := Label.new()
		l.text = "（空的，出去偷几颗回来）"
		_stored_list.add_child(l)
		return
	for i in range(GameState.stored.size()):
		var e: Dictionary = GameState.stored[i]
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s T%d（%s）" % [
			str(e.get("name", "?")), int(e.get("tier", 1)), str(e.get("quality_name", "普通"))]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var raise_btn := Button.new()
		raise_btn.text = "养 +%.1f/s" % [float(e.get("income", 0.0)) * float(e.get("quality_mult", 1.0))]
		raise_btn.pressed.connect(_on_raise.bind(i))
		row.add_child(raise_btn)
		var sell_btn := Button.new()
		sell_btn.text = "卖 %.0f" % float(e.get("value", 0.0))
		sell_btn.pressed.connect(_on_sell.bind(i))
		row.add_child(sell_btn)
		_stored_list.add_child(row)


func _on_raise(idx: int) -> void:
	if GameState.raise_stored(idx):
		_refresh()


func _on_sell(idx: int) -> void:
	if GameState.sell_stored(idx):
		_refresh()


func _rebuild_farm() -> void:
	for c in _farm_list.get_children():
		c.queue_free()
	if GameState.farm.is_empty():
		var l := Label.new()
		l.text = "（还没养任何东西）"
		_farm_list.add_child(l)
		return
	for c in GameState.farm:
		var l := Label.new()
		l.text = "%s T%d（%s）　+%.1f/s" % [
			str(c.get("name", "?")), int(c.get("tier", 1)),
			str(c.get("quality_name", "普通")),
			float(c.get("income", 0.0)) * float(c.get("quality_mult", 1.0))]
		_farm_list.add_child(l)


func _on_go() -> void:
	GameState.reset_run()
	GameState.refresh_start_tier()
	print("[农场] 出击：从 T%d 开门" % GameState.start_tier)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
