extends Node2D
## Phase 0 主控：警戒值 HUD、被抓判定、撤离判定

const EggDB := preload("res://scripts/data/egg_db.gd")

@onready var _alert_bar: ProgressBar = $HUD/AlertBar
@onready var _info: Label = $HUD/InfoLabel
@export var exit_radius: float = 60.0

@onready var _exit: Node2D = $ExitMarker
@onready var _player: Node2D = $Player
@onready var _guard: Node2D = $Guard
@onready var _nest: Node = $NestBuilder

const EGG_SCENE := preload("res://scenes/egg/egg.tscn")
const PARTNER_SCENE := preload("res://scenes/partner/partner.tscn")
const EGG_SPOTS: Array = [Vector2(620, 110), Vector2(720, 420), Vector2(470, 500)]

var _escaped := false


func _ready() -> void:
	GameEvents.alert_changed.connect(_on_alert_changed)
	GameEvents.alert_maxed.connect(_on_caught)
	_setup_guard()
	_spawn_eggs()
	_spawn_partner()


## 携带的伙伴会真的跟着你进巢穴 —— 让「养成反哺」看得见
func _spawn_partner() -> void:
	if GameState.selected_partner.is_empty() or _player == null:
		return
	var tier := 1
	for p in GameState.partners:
		if str(p.get("name", "")) == GameState.selected_partner:
			tier = int(p.get("tier", 1))
			break
	var p := PARTNER_SCENE.instantiate()
	add_child(p)
	p.global_position = _player.global_position + Vector2(-50, 0)
	p.setup(GameState.selected_partner, tier)


func _setup_guard() -> void:
	var t: Dictionary = EggDB.tier_data(GameState.current_tier)
	if _guard == null:
		return
	var gs := float(t.get("guard_speed", 70.0))
	_guard.set("chase_speed", gs)
	_guard.set("patrol_speed", gs * 0.7)


## 按当前生态阶随机生成蛋 —— 内容矩阵在这里生效
func _spawn_eggs() -> void:
	var spots: Array = _nest.get("egg_spots") if _nest else []
	if spots.is_empty():
		spots = EGG_SPOTS
	for p in spots:
		var e := EGG_SCENE.instantiate()
		add_child(e)
		e.position = p
		e.apply_data(EggDB.roll_egg(GameState.current_tier))


## 调试键：[ / ] 切换生态阶并重开本关，用来快速查看各阶地形差异
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var kc: int = (event as InputEventKey).keycode
	if kc == KEY_F:
		if GameState.try_use_skill():
			print("[Phase2] %s 释放技能！" % GameState.selected_partner)
	elif kc == KEY_BRACKETRIGHT and GameState.current_tier < GameState.unlocked_tier:
		GameState.current_tier += 1
		get_tree().reload_current_scene()
	elif kc == KEY_BRACKETLEFT and GameState.current_tier > 1:
		GameState.current_tier -= 1
		get_tree().reload_current_scene()


func _process(delta: float) -> void:
	GameState.tick_skill(delta)
	if _exit and _player and not _escaped:
		if _player.global_position.distance_to(_exit.global_position) < exit_radius:
			_on_exit()
	if _info == null:
		return
	var n := GameState.carried_eggs.size()
	var td: Dictionary = EggDB.tier_data(GameState.current_tier)
	var env := ""
	if GameState.env_name != "":
		env = " ｜ 【%s】" % GameState.env_name
		if GameState.env_oxygen >= 0.0:
			env += " 氧气 %.0fs" % GameState.env_oxygen
	_info.text = "T%d %s%s ｜ 携带 %d 颗 ｜ 负重 ×%.2f ｜ 隐匿 Lv%d ｜ 速度 Lv%d" % [
		GameState.current_tier, td.get("name", ""), env, n,
		GameState.get_load_multiplier(),
		GameState.stealth_level,
		GameState.speed_level,
	]
	if GameState.skill_active:
		_info.text += " ｜【技能生效 %.1fs】" % GameState.skill_timer
	elif GameState.skill_cooldown > 0.0:
		_info.text += " ｜ 技能冷却 %.0fs" % GameState.skill_cooldown
	elif not GameState.selected_partner.is_empty():
		_info.text += " ｜ F 释放技能"
	_info.text += " ｜ T 调参"


func _on_alert_changed(value: float, ratio: float) -> void:
	_alert_bar.value = value
	# 越接近满载越红
	_alert_bar.modulate = Color(1.0, 1.0 - ratio * 0.75, 1.0 - ratio * 0.75)


func _on_caught() -> void:
	var lost := GameState.drop_all_eggs()
	for egg in get_tree().get_nodes_in_group("eggs"):
		if egg.is_carried:
			egg.drop()
	GameState.reset_alert()
	if _player:
		_player.global_position = Vector2(80, 640)   # 被扔回入口
	print("[Phase0] 被抓！丢掉 %d 颗蛋" % lost)


func _on_exit() -> void:
	var n := GameState.carried_eggs.size()
	if n == 0:
		return
	_escaped = true
	var flawless := not GameState.was_spotted
	GameEvents.escaped.emit(n, flawless)
	print("[Phase0] 撤离成功！带回 %d 颗蛋%s" % [n, "，无痕之偷！" if flawless else ""])
	GameState.carried_eggs.clear()
	GameState.was_spotted = false
	GameState.reset_alert()

	# 回基地处理战利品：孵化 or 献祭
	await get_tree().create_timer(1.2).timeout
	GameState.store_carried_eggs()
	SaveManager.save()
	get_tree().change_scene_to_file("res://scenes/base.tscn")
