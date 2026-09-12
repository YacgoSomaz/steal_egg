extends CanvasLayer
## 手感实时调参面板（调试用，正式版可一键摘掉）
##
## 存在意义：守卫视野 240px / 70°、抓蛋 1.5s、警戒 15/s 这类参数
## 用数学推不出来，只能靠真人试玩。与其反复改代码重启，不如边玩边拧。
##
## 操作：
##   T        开关面板
##   1 - 7    选中要调的那一行
##   ,  /  .  减小 / 增大（不用左右方向键，那会带着人物一起走）
##   R        全部恢复默认
##   P        把当前配置打成一行日志，复制给我就能固化进代码
##
## 调完的值自动存 user://tune.json，重启不丢。

## persist=false 的行不写入存档：守卫追击速度的基准由 egg_db 的生态阶表决定，
## 存成绝对值会把十阶的难度曲线拍平，所以只在本次游戏内可调。
const ROWS: Array = [
	{"label": "守卫视野距离", "obj": "guard", "prop": "view_distance", "step": 20.0, "min": 60.0, "max": 600.0},
	{"label": "守卫视野角度", "obj": "guard", "prop": "view_angle", "step": 5.0, "min": 20.0, "max": 180.0},
	{"label": "被看见警戒/秒", "obj": "guard", "prop": "spot_alert_rate", "step": 2.0, "min": 1.0, "max": 60.0},
	{"label": "守卫追击速度", "obj": "guard", "prop": "chase_speed", "step": 10.0, "min": 40.0, "max": 400.0, "persist": false},
	{"label": "玩家跑速", "obj": "player", "prop": "base_speed", "step": 10.0, "min": 60.0, "max": 400.0},
	{"label": "玩家蹲行速度", "obj": "player", "prop": "sneak_speed", "step": 10.0, "min": 30.0, "max": 300.0},
	{"label": "抓蛋读条秒", "obj": "player", "prop": "grab_time", "step": 0.25, "min": 0.25, "max": 6.0},
]

const SAVE_PATH := "user://tune.json"

var _sel := 0
var _values: Dictionary = {}      # prop -> 当前值
var _defaults: Dictionary = {}    # prop -> 本关基准值（R 还原用）
var _label: Label


func _ready() -> void:
	layer = 128
	_build_ui()
	# 晚一帧再取值：本脚本的 _ready 早于 main.gd，那时守卫速度还没按生态阶设好
	call_deferred("_late_init")


func _late_init() -> void:
	_load_or_default()
	_apply_all()
	_refresh_text()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-330, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.10, 0.88)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	panel.add_child(_label)
	visible = false


# ── 数值 ───────────────────────────────────────
func _default_values() -> Dictionary:
	var d: Dictionary = {}
	for r in ROWS:
		var obj := _first_of(str(r["obj"]))
		d[str(r["prop"])] = obj.get(r["prop"]) if obj else float(r["min"])
	return d


func _load_or_default() -> void:
	# 先把「本关的真实基准」存下来，R 还原时才有得还原
	_defaults = _default_values()
	_values = _defaults.duplicate()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		for k in (parsed as Dictionary):
			if _values.has(k) and _persists(k):
				_values[k] = float((parsed as Dictionary)[k])


func _persists(prop: String) -> bool:
	for r in ROWS:
		if str(r["prop"]) == prop:
			return bool(r.get("persist", true))
	return true


func _save() -> void:
	var out: Dictionary = {}
	for prop in _values:
		if _persists(prop):
			out[prop] = _values[prop]
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(out))
	f.close()


func _first_of(which: String) -> Node:
	if which == "guard":
		return get_tree().get_first_node_in_group("guards")
	return get_tree().get_first_node_in_group("player")


func _targets(which: String) -> Array:
	if which == "guard":
		return get_tree().get_nodes_in_group("guards")
	return get_tree().get_nodes_in_group("player")


func _apply(prop: String, value: float) -> void:
	for r in ROWS:
		if str(r["prop"]) != prop:
			continue
		for o in _targets(str(r["obj"])):
			if o == null:
				continue
			o.set(prop, value)
			# 守卫巡逻速度跟着追击速度一起走，保持 0.7 的比例
			if prop == "chase_speed":
				o.set("patrol_speed", value * 0.7)
		return


func _apply_all() -> void:
	for prop in _values:
		_apply(prop, float(_values[prop]))


func _clamp_row(r: Dictionary, v: float) -> float:
	return clampf(v, float(r["min"]), float(r["max"]))


func _adjust(dir: float) -> void:
	var r: Dictionary = ROWS[_sel]
	var prop := str(r["prop"])
	var v := float(_values.get(prop, float(r["min"]))) + float(r["step"]) * dir
	v = _clamp_row(r, v)
	_values[prop] = v
	_apply(prop, v)
	_save()
	_refresh_text()


func _reset() -> void:
	_values = _defaults.duplicate()
	_apply_all()
	_save()
	_refresh_text()


func _dump() -> void:
	var parts: Array[String] = []
	for r in ROWS:
		var prop := str(r["prop"])
		parts.append("%s=%s" % [prop, _fmt(float(_values.get(prop, 0.0)))])
	print("[手感配置] " + " ".join(parts))


func _fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.001:
		return "%d" % int(roundf(v))
	return "%.2f" % v


func _refresh_text() -> void:
	var lines: Array[String] = []
	lines.append("[调参] T关 ｜ 1-7选行 ｜ , . 调整 ｜ R还原 ｜ P输出")
	for i in range(ROWS.size()):
		var r: Dictionary = ROWS[i]
		var prop := str(r["prop"])
		var mark := ">" if i == _sel else " "
		lines.append("%s%d %s：%s" % [mark, i + 1, str(r["label"]), _fmt(float(_values.get(prop, 0.0)))])
	_label.text = "\n".join(lines)


# ── 输入 ───────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var kc: int = (event as InputEventKey).keycode
	if kc == KEY_T:
		visible = not visible
		_refresh_text()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if kc >= KEY_1 and kc <= KEY_7:
		_sel = kc - KEY_1
		_refresh_text()
		get_viewport().set_input_as_handled()
	elif kc == KEY_COMMA:
		_adjust(-1.0)
		get_viewport().set_input_as_handled()
	elif kc == KEY_PERIOD:
		_adjust(1.0)
		get_viewport().set_input_as_handled()
	elif kc == KEY_R:
		_reset()
		get_viewport().set_input_as_handled()
	elif kc == KEY_P:
		_dump()
		get_viewport().set_input_as_handled()
