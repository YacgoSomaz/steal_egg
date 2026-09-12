extends CharacterBody3D
## 沉睡的巨兽
##
## 不动它的蛋，它就一直睡。动了，它追你——但只追 25 秒 / 70 单位就放弃回巢，
## 否则一堆怪永远挂在屁股后面，游戏没法玩。
## 追上你：抢走身上最贵那颗 + 永久降速，然后心满意足地回去睡。

const CreatureDB := preload("res://scripts/data/creature_db.gd")

enum State { ASLEEP, WAKING, CHASE, RETURN }

const CHASE_TIMEOUT := 25.0
const GIVE_UP_DIST := 70.0
## 蛋被偷的那只会一直追到撤离点——除非你把距离拉到这个数，那是真的甩没影了
const LOST_EGG_GIVE_UP := 1500.0

@export var tier: int = 1

var _state := State.ASLEEP
var _wake_timer := 0.0
var _wake_total := 1.0
var _chase_time := 0.0
var _lost_egg := false      # 蛋被偷了 → 不追回来不罢休
var _home := Vector3.ZERO
var _data: Dictionary = {}
var _base_scale := 1.0
var _zzz: Label3D
var _tag: Label3D
var _legs: Array = []
var _t := 0.0


func setup(t: int) -> void:
	tier = t
	_data = CreatureDB.tier_data(t)
	_base_scale = float(_data.get("scale", 1.0))
	add_to_group("creatures")
	_build()
	scale = Vector3(_base_scale, _base_scale * 0.42, _base_scale)


func is_asleep() -> bool:
	return _state == State.ASLEEP


## delay = 从「蛋没了」到「站起来」之间有多久。这个值由玩家的隐蔽属性决定，
## 是隐蔽这条属性唯一的用武之地，也是偷蛋者唯一的逃跑窗口。
func wake(delay: float = -1.0) -> void:
	if _state != State.ASLEEP:
		return
	_state = State.WAKING
	_wake_timer = delay if delay > 0.0 else float(_data.get("wake", 1.0))
	_wake_total = _wake_timer
	if _zzz:
		_zzz.text = "!"
		_zzz.modulate = Color(1.0, 0.35, 0.28)
		_zzz.visible = true
	GameEvents.creature_woke.emit(self)


func set_home(p: Vector3) -> void:
	_home = p


## 本阶的基础苏醒延迟，实际用时由玩家的隐蔽属性放大
func get_base_wake() -> float:
	return float(_data.get("wake", 1.0))


## 蛋被偷了。从此它不吃「追 25 秒就放弃」那套，会一直咬到你撤离为止。
## 同时脱离 chunk —— 否则玩家跑远、chunk 被回收时，追兵会凭空消失。
func on_egg_stolen() -> void:
	_lost_egg = true
	var scene := get_tree().current_scene
	if scene != null and get_parent() != scene:
		reparent(scene)


# ── 建模（零美术资源，全几何体）──────────────────
func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(_data.get("color", Color.WHITE))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(_data.get("color", Color.WHITE)).darkened(0.35)

	var torso := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 1.0, 2.4)
	torso.mesh = bm
	torso.position.y = 0.95
	torso.material_override = mat
	add_child(torso)

	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(1.0, 0.9, 1.1)
	head.mesh = hm
	head.position = Vector3(0, 1.4, -1.6)
	head.material_override = mat
	add_child(head)

	for sx in [-0.28, 0.28]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.14
		em.height = 0.28
		eye.mesh = em
		eye.position = Vector3(sx, 1.55, -2.1)
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(1.0, 0.85, 0.3)
		eye.material_override = emat
		add_child(eye)

	for sx in [-0.62, 0.62]:
		for sz in [-0.85, 0.85]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.36, 0.8, 0.36)
			leg.mesh = lm
			leg.position = Vector3(sx, 0.4, sz)
			leg.material_override = dark
			add_child(leg)
			_legs.append(leg)

	_zzz = Label3D.new()
	_zzz.text = "zZz"
	_zzz.font_size = 48
	_zzz.position = Vector3(0, 2.8, 0)
	_zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_zzz)

	# 头顶标出阶位和速度——不标出来，玩家根本感知不到"这只比那只快"
	_tag = Label3D.new()
	_tag.text = "T%d %s　%.1f" % [tier, str(_data.get("name", "?")), float(_data.get("speed", 6.0))]
	_tag.font_size = int(34.0 / _base_scale)
	_tag.position = Vector3(0, 3.6, 0)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.modulate = Color(0.85, 0.88, 0.95)
	add_child(_tag)


# ── 每帧 ───────────────────────────────────────
func _physics_process(delta: float) -> void:
	_t += delta
	var player := _get_player()
	# 远处还在睡的：不跑逻辑也不渲染。单局几十只怪，不省这个会白烧 CPU 和 draw call
	if _state == State.ASLEEP and player != null:
		if _flat_dist(player) > 700.0:
			if visible:
				visible = false
			return
		elif not visible:
			visible = true
	match _state:
		State.ASLEEP:
			_tick_asleep()
		State.WAKING:
			_tick_waking(delta)
		State.CHASE:
			_tick_chase(delta, player)
		State.RETURN:
			_tick_return(delta)
	position.y = 0.0


## 睡着的怪不会被路过吵醒——它们是「沉睡」的，只有蛋被动了才会醒。
## 这一点很重要：否则玩家在读条时被围住，等于必死。
func _tick_asleep() -> void:
	scale.y = _base_scale * (0.42 + sin(_t * 1.6) * 0.03)


func _tick_waking(delta: float) -> void:
	_wake_timer -= delta
	var k := clampf(1.0 - _wake_timer / maxf(0.01, _wake_total), 0.0, 1.0)
	scale.y = _base_scale * (0.42 + 0.58 * k)
	# 后一半时间开始抖，等于给玩家一个"它要起来了，快跑"的信号
	if k > 0.5:
		position.x = _home.x + sin(_t * 38.0) * 0.09 * k
	if _wake_timer <= 0.0:
		_state = State.CHASE
		_chase_time = 0.0
		position.x = _home.x
		if _zzz:
			_zzz.visible = false
		if _tag:
			_tag.modulate = Color(1.0, 0.45, 0.38)


func _tick_chase(delta: float, player: Node3D) -> void:
	_chase_time += delta
	scale.y = _base_scale
	if player == null:
		_state = State.RETURN
		return
	# 放弃距离按自己的速度缩放，否则高阶怪一步就跨出旧阈值，等于没有
	var give_up: float = maxf(GIVE_UP_DIST, float(_data.get("speed", 6.0)) * 8.0)
	if _lost_egg:
		if _flat_dist(player) > LOST_EGG_GIVE_UP:
			_state = State.RETURN
			return
	elif _chase_time > CHASE_TIMEOUT or _flat_dist(player) > give_up:
		_state = State.RETURN
		return
	var to := player.global_position - global_position
	to.y = 0.0
	var sp := float(_data.get("speed", 6.5))
	velocity = to.normalized() * sp
	move_and_slide()
	rotation.y = atan2(-to.x, -to.z)
	# 腿摆动的频率直接跟速度挂钩：高阶怪腿快得几乎看不清，一眼就知道惹不起
	_leg_swing(sp)
	if _flat_dist(player) < 1.9 * _base_scale:
		_catch_player()


func _leg_swing(speed: float) -> void:
	var s := sin(_t * (4.0 + speed * 0.55)) * 0.42
	for i in range(_legs.size()):
		var leg: Node3D = _legs[i]
		leg.rotation.x = s if (i % 2 == 0) else -s


func _tick_return(delta: float) -> void:
	scale.y = _base_scale
	var to := _home - global_position
	to.y = 0.0
	if to.length() > 800.0:
		queue_free()          # 家那头的 chunk 早回收了，就地解散
		return
	if to.length() < 1.2:
		_state = State.ASLEEP
		global_position = _home
		rotation.y = 0.0
		if _zzz:
			_zzz.text = "zZz"
			_zzz.modulate = Color(1.0, 1.0, 1.0)
			_zzz.visible = true
		if _tag:
			_tag.modulate = Color(0.85, 0.88, 0.95)
		return
	velocity = to.normalized() * float(_data.get("speed", 6.5)) * 0.85
	move_and_slide()
	rotation.y = atan2(-to.x, -to.z)


func _catch_player() -> void:
	var lost := GameState.lose_best_egg()
	GameState.apply_penalty()
	GameEvents.player_caught.emit(lost)
	_lost_egg = false         # 抢回来了，满意，回去睡
	_state = State.RETURN
	_chase_time = 0.0
	SaveManager.save()


func _flat_dist(other: Node3D) -> float:
	var a := global_position
	var b := other.global_position
	return Vector2(a.x - b.x, a.z - b.z).length()


func _get_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D
