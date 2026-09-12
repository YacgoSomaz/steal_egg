extends Control
## 基地（Phase 1）：孵化 / 献祭 / 属性升级 / 选择伙伴

const EggDB := preload("res://scripts/data/egg_db.gd")
const DebugPanel := preload("res://scripts/base/debug_panel.gd")
## UI 全部程序化生成，零美术资源
## 这里承载第二层抉择：偷回来的蛋，是「养着」还是「吃了」

var _points_label: Label
var _stealth_info: Label
var _speed_info: Label
var _stealth_btn: Button
var _speed_btn: Button
var _egg_list: VBoxContainer
var _hatch_list: VBoxContainer
var _partner_list: VBoxContainer
var _partner_info: Label
var _tier_info: Label
var _tier_btn: Button
var _dex_label: Label
var _dex_list: VBoxContainer


func _ready() -> void:
	_build_ui()
	_refresh_all()


func _process(delta: float) -> void:
	if GameState.hatching.is_empty():
		return
	var born := GameState.tick_hatch(delta)
	if born.is_empty():
		_refresh_hatch()
	else:
		for n in born:
			print("[基地] %s 孵出来了！" % n)
		_refresh_all()


# ── UI 骨架 ────────────────────────────────────
func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 20)
	root.add_child(_points_label)

	root.add_child(HSeparator.new())

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	root.add_child(cols)

	var attr_col := _make_col("属性")
	_stealth_info = Label.new()
	_speed_info = Label.new()
	_stealth_btn = Button.new()
	_speed_btn = Button.new()
	_stealth_btn.pressed.connect(_on_upgrade_stealth)
	_speed_btn.pressed.connect(_on_upgrade_speed)
	_tier_info = Label.new()
	_tier_btn = Button.new()
	_tier_btn.pressed.connect(_on_unlock_tier)
	attr_col.add_child(_stealth_info)
	attr_col.add_child(_stealth_btn)
	attr_col.add_child(_speed_info)
	attr_col.add_child(_speed_btn)
	attr_col.add_child(HSeparator.new())
	attr_col.add_child(_tier_info)
	attr_col.add_child(_tier_btn)
	cols.add_child(attr_col)

	var egg_col := _make_col("库存的蛋")
	_egg_list = VBoxContainer.new()
	egg_col.add_child(_egg_list)
	cols.add_child(egg_col)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)

	var hatch_col := _make_col("孵化槽")
	_hatch_list = VBoxContainer.new()
	hatch_col.add_child(_hatch_list)
	right.add_child(hatch_col)

	var partner_col := _make_col("伙伴（点击携带）")
	_partner_list = VBoxContainer.new()
	partner_col.add_child(_partner_list)

	# 当前携带伙伴的被动说明——不做出来玩家根本不知道孵伙伴有什么用
	_partner_info = Label.new()
	_partner_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_partner_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_partner_info.add_theme_color_override("font_color", Color(0.20, 0.42, 0.28))
	partner_col.add_child(_partner_info)
	right.add_child(partner_col)

	var dex_col := _make_col("图鉴")
	_dex_label = Label.new()
	dex_col.add_child(_dex_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dex_list = VBoxContainer.new()
	_dex_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_dex_list)
	dex_col.add_child(scroll)
	right.add_child(dex_col)

	root.add_child(HSeparator.new())

	var go := Button.new()
	go.text = "出 击"
	go.custom_minimum_size = Vector2(0, 46)
	go.add_theme_font_size_override("font_size", 18)
	go.pressed.connect(_on_go)
	root.add_child(go)

	var dbg := DebugPanel.new()
	dbg.changed.connect(_refresh_all)
	root.add_child(dbg)


func _make_col(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 16)
	box.add_child(head)
	return box


# ── 刷新 ───────────────────────────────────────
func _refresh_all() -> void:
	_points_label.text = "基因点：%d" % GameState.gene_points
	_refresh_attr()
	_refresh_tier()
	_refresh_eggs()
	_refresh_hatch()
	_refresh_partners()
	_refresh_dex()
	SaveManager.save()


func _refresh_attr() -> void:
	var sc := GameState.get_upgrade_cost(GameState.stealth_level)
	var pc := GameState.get_upgrade_cost(GameState.speed_level)
	_stealth_info.text = "隐匿 Lv%d　（守卫感知 ×%.2f）" % [
		GameState.stealth_level, GameState.get_perception_multiplier(),
	]
	_speed_info.text = "速度 Lv%d　（移速 ×%.2f）" % [
		GameState.speed_level, GameState.get_speed_multiplier(),
	]
	_stealth_btn.text = "升级隐匿（%s）" % (str(sc) + " 点" if sc > 0 else "已满级")
	_speed_btn.text = "升级速度（%s）" % (str(pc) + " 点" if pc > 0 else "已满级")
	_stealth_btn.disabled = sc < 0 or GameState.gene_points < sc
	_speed_btn.disabled = pc < 0 or GameState.gene_points < pc


func _refresh_eggs() -> void:
	_clear(_egg_list)
	if GameState.stored_eggs.is_empty():
		var l := Label.new()
		l.text = "（空）去偷几颗回来"
		_egg_list.add_child(l)
		return
	for i in GameState.stored_eggs.size():
		var data: Dictionary = GameState.stored_eggs[i]
		var row := HBoxContainer.new()
		var name_l := Label.new()
		name_l.text = "%s（%s，T%d，献祭 +%d）" % [
			data.get("name", "蛋"), data.get("quality_name", "普通"),
			data.get("tier", 1), data.get("value", 1),
		]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)

		var hb := Button.new()
		hb.text = "孵化"
		hb.disabled = GameState.hatching.size() >= GameState.HATCH_SLOTS
		hb.pressed.connect(func(): _on_hatch(i))
		row.add_child(hb)

		var sb := Button.new()
		sb.text = "献祭"
		sb.pressed.connect(func(): _on_sacrifice(i))
		row.add_child(sb)

		_egg_list.add_child(row)


func _refresh_hatch() -> void:
	_clear(_hatch_list)
	if GameState.hatching.is_empty():
		var l := Label.new()
		l.text = "（%d 个空槽）" % GameState.HATCH_SLOTS
		_hatch_list.add_child(l)
		return
	for h in GameState.hatching:
		var row := VBoxContainer.new()
		var l := Label.new()
		l.text = "%s（%s）　%.1fs" % [
			h.get("name", "蛋"), h.get("quality_name", "普通"), float(h.get("remaining", 0.0)),
		]
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = float(h.get("total", 1.0))
		bar.value = bar.max_value - float(h.get("remaining", 0.0))
		bar.custom_minimum_size = Vector2(180, 14)
		bar.show_percentage = false
		row.add_child(bar)
		_hatch_list.add_child(row)


func _refresh_dex() -> void:
	_clear(_dex_list)
	_dex_label.text = "已发现 %d / 160" % GameState.discovered_count()
	for tier in range(1, 11):
		var species: Array = EggDB.species_of_tier(tier)
		var seen: Array = []
		for s in species:
			var nm := str(s.get("name", ""))
			for q in EggDB.QUALITIES:
				if GameState.discovered.has("%s|%s" % [nm, str(q.get("name", ""))]):
					if not seen.has(nm):
						seen.append(nm)
					break
		var td: Dictionary = EggDB.tier_data(tier)
		var head := Label.new()
		head.text = "T%d %s　%d/%d" % [tier, td.get("name", ""), seen.size(), species.size()]
		_dex_list.add_child(head)
		for nm in seen:
			var item := Label.new()
			item.text = "　" + str(nm)
			_dex_list.add_child(item)


func _refresh_tier() -> void:
	var cur: Dictionary = EggDB.tier_data(GameState.unlocked_tier)
	var nxt: Dictionary = GameState.next_tier_data()
	if nxt.is_empty():
		_tier_info.text = "已解锁全部生态阶（T%d %s）" % [
			GameState.unlocked_tier, cur.get("name", ""),
		]
		_tier_btn.visible = false
		return
	_tier_info.text = "当前最高：T%d %s ｜ 属性上限 Lv%d" % [
		GameState.unlocked_tier, cur.get("name", ""), GameState.get_max_level(),
	]
	_tier_btn.visible = true
	_tier_btn.text = "解锁 T%d %s（%d 点，需隐匿%d/速度%d）" % [
		nxt.get("tier", 0), nxt.get("name", ""), nxt.get("unlock_cost", 0),
		nxt.get("stealth_req", 1), nxt.get("speed_req", 1),
	]
	_tier_btn.disabled = not GameState.can_unlock_next_tier()


func _on_unlock_tier() -> void:
	if GameState.unlock_next_tier():
		_refresh_all()


func _refresh_partners() -> void:
	_clear(_partner_list)
	if GameState.partners.is_empty():
		var l := Label.new()
		l.text = "（还没有伙伴）"
		_partner_list.add_child(l)
		_update_partner_info()
		return
	# 空选项：不带伙伴
	_add_partner_btn("（不带）", "", 0, "不携带任何伙伴")
	var seen: Array[String] = []
	for p in GameState.partners:
		var nm := str(p.get("name", "?"))
		if nm in seen:
			continue
		seen.append(nm)
		var count := 0
		var best_q := "普通"
		var best_m := 0.0
		var tier := 1
		for q in GameState.partners:
			if str(q.get("name", "")) == nm:
				count += 1
				tier = int(q.get("tier", 1))
				var m := float(q.get("quality_mult", 1.0))
				if m > best_m:
					best_m = m
					best_q = str(q.get("quality_name", "普通"))
		var d: Dictionary = EggDB.partner_passive_of(tier)
		_add_partner_btn("%s ×%d（%s）" % [nm, count, best_q], nm, tier, str(d.get("desc", "")))
	_update_partner_info()


## 每阶伙伴的被动不同，必须在界面上说清楚，否则孵化系统等于没做
func _update_partner_info() -> void:
	var t := GameState.get_partner_tier()
	if t <= 0:
		_partner_info.text = "当前：无。孵化的生物跟你出击才会生效。"
		return
	var d: Dictionary = EggDB.partner_passive_of(t)
	_partner_info.text = "当前：%s（T%d）\n被动：%s" % [GameState.selected_partner, t, str(d.get("desc", ""))]


func _add_partner_btn(text: String, key: String, tier: int, passive_desc: String) -> void:
	var b := Button.new()
	b.text = ("▶ " if GameState.selected_partner == key else "") + text
	if tier > 0:
		b.tooltip_text = "T%d 被动：%s" % [tier, passive_desc]
	b.pressed.connect(func():
		GameState.selected_partner = key
		_refresh_partners()
		SaveManager.save()
	)
	_partner_list.add_child(b)


func _clear(box: Node) -> void:
	for c in box.get_children():
		c.queue_free()


# ── 交互 ───────────────────────────────────────
func _on_upgrade_stealth() -> void:
	if GameState.upgrade_stealth():
		print("[基地] 隐匿提升到 Lv%d" % GameState.stealth_level)
		_refresh_all()


func _on_upgrade_speed() -> void:
	if GameState.upgrade_speed():
		print("[基地] 速度提升到 Lv%d" % GameState.speed_level)
		_refresh_all()


func _on_hatch(index: int) -> void:
	if GameState.start_hatch(index):
		_refresh_all()


func _on_sacrifice(index: int) -> void:
	var pts := GameState.sacrifice_egg(index)
	if pts > 0:
		print("[基地] 献祭获得 %d 基因点" % pts)
		_refresh_all()


func _on_go() -> void:
	GameState.was_spotted = false
	GameState.reset_alert()
	GameState.current_tier = GameState.unlocked_tier   # 默认去最高已解锁阶位
	get_tree().change_scene_to_file("res://scenes/main.tscn")
