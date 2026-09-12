extends CharacterBody3D
## 沉睡的巨兽
##
## 不动它的蛋，它就一直睡。动了，它追你——但只追 25 秒 / 70 单位就放弃回巢，
## 否则一堆怪永远挂在屁股后面，游戏没法玩。
## 追上你：抢走身上最贵那颗 + 永久降速，然后心满意足地回去睡。

const CreatureDB := preload("res://scripts/data/creature_db.gd")
const CreatureModel := preload("res://scripts/run/creature_model.gd")

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
var _segs: Array = []      # 分节躯干 / 尾鳍，会波浪式摆动
var _wings: Array = []     # 翼 / 鳍，会扇动
var _halo: Node3D = null   # T10 光环，自己慢慢转
var _model: Node3D = null
var _floaty := false       # 浮游种：没有腿，靠上下起伏表现"活着"
var _display := false      # 陈列模式：站着慢慢转，纯给人看外形
var _pen_center := Vector3.ZERO
var _pen_radius := 0.0
var _wander_to := Vector3.ZERO
var _t := 0.0


## 畜栏模式：在围栏里慢慢晃。农场里那些养着的生物用这个，
## 站着不动打转看着像标本，走起来才像"这是我养活的"。
func set_pen(center: Vector3, radius: float) -> void:
	_display = true
	_pen_center = center
	_pen_radius = radius
	_wander_to = center
	_state = State.CHASE
	scale.y = _base_scale
	if _zzz:
		_zzz.visible = false
	if _tag:
		_tag.visible = false


## 陈列模式（--gallery 用）：不会追人、不会睡回去，就站在原地慢慢转，
## 方便一眼看清这阶长什么样。
func set_display(on: bool) -> void:
	_display = on
	if on:
		_state = State.CHASE      # 借用站立姿态
		scale.y = _base_scale
		if _zzz:
			_zzz.visible = false
		if _tag:
			_tag.modulate = Color(1.0, 0.95, 0.6)


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


# ── 建模 ───────────────────────────────────────
## 十阶各有各的身体蓝图（见 creature_model.gd），这里只负责挂上去
## 外加 zZz 和头顶标签。
func _build() -> void:
	var m: Dictionary = CreatureModel.build(tier)
	_model = m.get("root") as Node3D
	_legs = m.get("legs") as Array
	_segs = m.get("segs") as Array
	_wings = m.get("wings") as Array
	_halo = m.get("halo") as Node3D
	_floaty = bool(m.get("float", false))
	if _model != null:
		add_child(_model)

	# 标签和 zZz 要挂在模型头顶，不然 T8 飞龙那种会被戳穿
	var top := CreatureModel.top_of(tier)

	_zzz = Label3D.new()
	_zzz.text = "zZz"
	_zzz.font_size = 48
	_zzz.position = Vector3(0, top + 0.35, 0)
	_zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_zzz)

	# 头顶标出阶位和速度——不标出来，玩家根本感知不到"这只比那只快"
	_tag = Label3D.new()
	_tag.text = "T%d %s　%.1f" % [tier, str(_data.get("name", "?")), float(_data.get("speed", 6.0))]
	_tag.font_size = int(34.0 / _base_scale)
	_tag.position = Vector3(0, top + 1.05, 0)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.modulate = Color(0.85, 0.88, 0.95)
	add_child(_tag)


# ── 每帧 ───────────────────────────────────────
func _physics_process(delta: float) -> void:
	_t += delta
	if _display:
		scale.y = _base_scale
		position.y = 0.0
		if _pen_radius > 0.0:
			# 畜栏里的：玩家跑远了就别算了，农场最多二十只，一直全渲染会拖帧
			var pl := _get_player()
			if pl != null and _flat_dist(pl) > 240.0:
				if visible:
					visible = false
				return
			if not visible:
				visible = true
			_wander(delta)
		else:
			# 陈列模式：站着慢慢自转，让人能看清全身轮廓
			rotation.y += delta * 0.35
			_animate(0.0)
		return
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
	# 浮游种没有"趴下"这回事，它们只是浮得低一点
	var s := 0.88 if _floaty else CreatureModel.SLEEP_SQUASH
	scale.y = _base_scale * (s + sin(_t * 1.6) * 0.03)
	_animate(0.0)


func _tick_waking(delta: float) -> void:
	_wake_timer -= delta
	var k := clampf(1.0 - _wake_timer / maxf(0.01, _wake_total), 0.0, 1.0)
	var s0 := 0.88 if _floaty else CreatureModel.SLEEP_SQUASH
	scale.y = _base_scale * (s0 + (1.0 - s0) * k)
	_animate(0.0)
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
	# 撤离线就是追兵的终点。农场区是安全区——追到这里必须回头。
	# 少了这一条，玩家扛着蛋跑回家，还会在店铺门口被撞：
	# 那不但"回家不安全"，还会把已经入库的蛋再抢走一次，玩家只会觉得是 bug。
	if player.global_position.z > CreatureDB.SAFE_LINE:
		_give_up()
		return
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
	var sp := float(_data.get("speed", 6.0))
	velocity = to.normalized() * sp
	move_and_slide()
	# 物理上也不许越线：万一某阶怪速度太大一步跨过，也要被拽回来。
	# 只在越过时改 z，正常追击（z < SAFE_LINE）完全不受影响。
	if global_position.z > CreatureDB.SAFE_LINE:
		global_position.z = CreatureDB.SAFE_LINE
	rotation.y = atan2(-to.x, -to.z)
	# 腿摆动的频率直接跟速度挂钩：高阶怪腿快得几乎看不清，一眼就知道惹不起
	_animate(sp)
	# 抓取半径也要卡在安全区外，否则 T10 那种 8.7 米的判定
	# 能隔着撤离线把站在店门口的玩家抓住
	if _flat_dist(player) < 1.9 * _base_scale and player.global_position.z <= CreatureDB.SAFE_LINE:
		_catch_player()


## 追到撤离线了，放弃回巢。注意要把 _lost_egg 也清掉——
## 否则它会一直带着"蛋没抢回来"的状态，下次玩家再靠近就又是无限制追击
func _give_up() -> void:
	_lost_egg = false
	_chase_time = 0.0
	_state = State.RETURN


## 一个入口把整套动作跑完：摆腿 / 体节波动 / 扇翼 / 浮游起伏 / 转光环。
## 所有频率都跟速度挂钩——高阶怪不只是数值快，是看着就快。
func _animate(speed: float) -> void:
	_leg_swing(speed)
	_seg_wave(speed)
	_wing_flap(speed)
	if _floaty and _model != null:
		# 浮游种没有腿，靠上下起伏表示"它醒着，而且在动"
		_model.position.y = sin(_t * (1.2 + speed * 0.06)) * (0.10 + speed * 0.008)
	if _halo != null:
		_halo.rotation.y += (0.6 + speed * 0.03) * get_physics_process_delta_time()
		_halo.rotation.x = sin(_t * 0.5) * 0.18


## 在围栏里随机踱步：走到一个点就换下一个，走到边界会被拉回来
func _wander(delta: float) -> void:
	var to := _wander_to - position
	to.y = 0.0
	if to.length() < 0.8 or randf() < delta * 0.15:
		var a := randf() * TAU
		var r := sqrt(randf()) * _pen_radius
		_wander_to = _pen_center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		return
	var sp := 1.4 + float(tier) * 0.06
	velocity = to.normalized() * sp
	move_and_slide()
	rotation.y = atan2(-to.x, -to.z)
	_animate(sp)


func _leg_swing(speed: float) -> void:
	var s := sin(_t * (4.0 + speed * 0.55)) * 0.42
	for i in range(_legs.size()):
		var leg: Node3D = _legs[i]
		leg.rotation.x = s if (i % 2 == 0) else -s


## 分节躯干 / 尾鳍：相位逐节延迟，看起来像一条波从前往后传过去
func _seg_wave(speed: float) -> void:
	if _segs.is_empty():
		return
	var f := 2.2 + speed * 0.30
	for i in range(_segs.size()):
		var s: Node3D = _segs[i]
		if s == null:
			continue
		var ph := float(i) * 0.62
		s.rotation.y = sin(_t * f - ph) * 0.16
		s.position.x = sin(_t * f * 0.7 - ph) * 0.09


## 翼 / 鳍：追击时扇得急，睡着时只是微微起伏
func _wing_flap(speed: float) -> void:
	if _wings.is_empty():
		return
	var amp := 0.10 + clampf(speed * 0.012, 0.0, 0.42)
	var f := 1.8 + speed * 0.22
	for i in range(_wings.size()):
		var w: Node3D = _wings[i]
		if w == null:
			continue
		var side := 1.0 if w.position.x >= 0.0 else -1.0
		w.rotation.z = sin(_t * f) * amp * side


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
