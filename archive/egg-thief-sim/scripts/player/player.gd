extends CharacterBody2D
## Phase 0 玩家：移动、蹲走/跑步、抓取读条、背蛋负重
## 占位符美术：几何体拼装，动画由 player_anim.gd 程序化驱动

@export var base_speed: float = 180.0
@export var sneak_speed: float = 105.0   # 要比守卫巡逻(追击×0.7)快，才绕得了后
@export var grab_time: float = 1.5

var _grab_target: Node2D = null
var _grab_progress: float = 0.0
var _move_input: Vector2 = Vector2.ZERO

@onready var _carry_slot: Node2D = $CarrySlot
@onready var _anim: Node = $PlayerAnim


func _physics_process(delta: float) -> void:
	# 抓取读条期间不能移动 —— 这是最脆弱的时刻
	if _grab_target != null:
		velocity = Vector2.ZERO
		_tick_grab(delta)
		move_and_slide()
		return

	_move_input = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var sneaking := Input.is_key_pressed(KEY_SHIFT)
	var sp := sneak_speed if sneaking else base_speed
	sp = GameState.get_effective_speed(sp)   # 速度属性 × 负重系数

	velocity = _move_input * sp + GameState.env_wind   # 环境强风会推着你走
	move_and_slide()

	# 噪音与警戒：跑步涨得快，蹲走几乎不涨，静立能平复
	if _move_input.length() > 0.0:
		var rate: float = 0.5 if sneaking else 3.0
		rate *= _get_ground_multiplier()                              # 碎骨地 ×2，草地 ×0.5
		rate *= 1.0 + 0.35 * float(GameState.carried_eggs.size())     # 每颗蛋 +35% 噪音
		rate *= GameState.get_partner_noise_multiplier()               # 伙伴被动
		if GameState.skill_active:
			rate = 0.0                                                 # 技能期间完全静音
		GameState.add_alert(rate * delta)
	else:
		GameState.add_alert(-4.0 * delta)   # 旧值 -2 太慢，从满值平复要 50 秒，等得难受


## 当前所处地面材质的噪音倍率（纯几何判定，不依赖物理查询）
func _get_ground_multiplier() -> float:
	for zone in get_tree().get_nodes_in_group("ground_zones"):
		var z := zone as Node2D
		if z == null:
			continue
		var half: Vector2 = Vector2(z.get_meta("zone_size", Vector2.ZERO)) * 0.5
		var d: Vector2 = (global_position - z.global_position).abs()
		if d.x <= half.x and d.y <= half.y:
			return float(z.get_meta("noise_multiplier", 1.0))
	return 1.0

	if Input.is_key_pressed(KEY_E):
		_try_grab()
	if Input.is_key_pressed(KEY_Q):
		_drop_one()


func _try_grab() -> void:
	if _grab_target != null:
		return
	for egg in get_tree().get_nodes_in_group("eggs"):
		if egg.global_position.distance_to(global_position) < 70.0 and not egg.is_carried:
			_grab_target = egg
			_grab_progress = 0.0
			GameEvents.egg_grab_started.emit(egg)
			return


func _tick_grab(delta: float) -> void:
	_grab_progress += delta
	if _grab_progress >= grab_time:
		var egg := _grab_target
		_grab_target = null
		_grab_progress = 0.0
		egg.pick_up(_carry_slot)
		GameState.carry_egg(egg)
		GameState.add_alert(10.0)          # 抓取瞬间硬惩罚
		GameEvents.egg_grabbed.emit(egg)


func _drop_one() -> void:
	var eggs := GameState.carried_eggs
	if eggs.is_empty():
		return
	var egg: Node2D = eggs.pop_back()
	egg.drop()
	GameState.add_alert(-5.0)


## 被抓：丢光所有蛋
func get_caught() -> void:
	var n := GameState.drop_all_eggs()
	for egg in get_tree().get_nodes_in_group("eggs"):
		if not egg.is_carried:
			continue
		egg.drop()
	GameState.reset_alert()
	GameEvents.player_caught.emit()
	print("[Phase0] 被抓住，丢掉 %d 颗蛋" % n)
