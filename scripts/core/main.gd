extends Node3D
## 跑道主控：相机跟随、偷蛋读条、撤离判定、HUD
##
## 张力设计：冲得越远蛋越值钱，但**必须自己扛着蛋跑回起点**才算数。
## 回程那一路上，被你吵醒的怪全在后面追。

const CreatureDB := preload("res://scripts/data/creature_db.gd")
const LANDMARK := preload("res://scenes/run/landmark.tscn")

## 越肩视角：相机压到玩家右肩后上方，透视投影，看得见地平线上的东西。
## 越低越有压迫感，也越能看见远处的巨型生物——这是这一版选它的唯一理由。
const CAM_OFFSET := Vector3(1.6, 4.4, 8.2)
const CAM_PITCH := -17.0
const CAM_FOV := 72.0
const CAM_LERP := 7.0           # 跟随平滑，别让玩家一转向画面就抽

## 速度感三件套。注意配比：以前 zoom 给到 6 倍、模型放大 0.35，
## 结果把速度提升全抵消了——数值涨 10 倍，看着跟没涨一样。
## 现在只做「够用」的补偿，剩下的速度感交给地面条纹和 FOV。
const ZOOM_DIV := 25.0          # 相机拉远：速度/25，封顶 3.5 倍
const ZOOM_MAX := 3.5
const FOV_PER_SPEED := 0.30     # FOV 随速度扩张，制造推背感
const FOV_MAX_BOOST := 18.0

const GRAB_RANGE := 3.6
const ESCAPE_Z := -12.0
const NOISE_RADIUS := 12.0      # 偷蛋的动静会吵醒周围这么远的怪（蹲走减半）
const LANDMARK_AHEAD := 250.0   # 巨型生物摆在玩家前方这么远

@onready var _cam: Camera3D = $Camera3D
@onready var _player: Node3D = $Player
@onready var _track: Node3D = $Track
@onready var _sun: DirectionalLight3D = $Sun
@onready var _fill: DirectionalLight3D = $Fill
@onready var _info: Label = $HUD/Info
@onready var _hint: Label = $HUD/Hint
@onready var _toast_label: Label = $HUD/Toast
@onready var _bar: ProgressBar = $HUD/GrabBar

var _grab_target: Node3D = null
var _grab_progress := 0.0
var _toast := ""
var _toast_time := 0.0
var _landmarks: Array = []
var _landmark_tier := 0
var _cam_ready := false


func _ready() -> void:
	GameState.refresh_start_tier()   # 从哪一阶开门，由当前速度决定
	_setup_lights()
	GameEvents.player_caught.connect(_on_caught)
	# 调试用：--jump 直接跳到 700m 处，--diag 把生成结果打出来
	var args := OS.get_cmdline_args()
	if args.has("--jump"):
		# --jump 20000 直接跳到 20000 m 处，方便看高阶长什么样
		var d := 700.0
		var i := args.find("--jump")
		if i + 1 < args.size():
			d = absf(float(args[i + 1]))
		_player.position.z = -d
	_track.call("update", _player.position.z)
	_bar.visible = false
	if args.has("--diag"):
		await get_tree().process_frame
		_diag()


func _diag() -> void:
	var creatures := get_tree().get_nodes_in_group("creatures")
	var eggs := get_tree().get_nodes_in_group("eggs")
	var dist := maxf(0.0, -_player.position.z)
	var by_tier: Dictionary = {}
	for c in creatures:
		var t := int(c.get("tier"))
		by_tier[t] = int(by_tier.get(t, 0)) + 1
	print("[自检] 起点阶 T%d ｜ 距离 %.0f m ｜ 当前阶 T%d ｜ 沉睡怪 %d 只 ｜ 蛋 %d 颗 ｜ 阶位分布 %s" % [
		GameState.start_tier, dist, CreatureDB.tier_at(dist, GameState.start_tier),
		creatures.size(), eggs.size(), str(by_tier),
	])


func _setup_lights() -> void:
	_sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	_sun.light_energy = 1.15
	_fill.rotation_degrees = Vector3(-25.0, -140.0, 0.0)
	_fill.light_energy = 0.45
	# 越肩：透视 + 压低俯角，地平线进画面，远处的巨兽才看得见
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = CAM_FOV
	_cam.rotation_degrees = Vector3(CAM_PITCH, 0.0, 0.0)
	_cam.position = _player.position + CAM_OFFSET
	_cam_ready = true
	_build_start_marker()
	_setup_environment()
	_setup_landmarks()


## 雾 + 天空色：让远处的大东西有层次，而不是贴在纯色背景上
func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.66, 0.76)
	env.ambient_light_energy = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.80, 0.90)
	env.fog_density = 0.0022
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_landmarks() -> void:
	for i in range(2):
		var lm: Node3D = LANDMARK.instantiate() as Node3D
		add_child(lm)
		_landmarks.append(lm)
	_update_landmarks()


## 巨型生物永远在你前方固定的距离，随你前进——你跑多远，它就退多远，
## 但它的阶位会跟着涨：看得见的威胁，才叫目标
func _update_landmarks() -> void:
	if _landmarks.is_empty():
		return
	var dist := maxf(0.0, -_player.position.z) + LANDMARK_AHEAD
	var t := CreatureDB.tier_at(dist, GameState.start_tier)
	if t != _landmark_tier:
		_landmark_tier = t
		for i in range(_landmarks.size()):
			var lm: Node3D = _landmarks[i]
			lm.call("setup", t, 1 if i == 0 else -1)
	var k := CreatureDB.world_scale(t)
	var z := _player.position.z - LANDMARK_AHEAD * (1.0 + (k - 1.0) * 0.3)
	var a: Node3D = _landmarks[0]
	var b: Node3D = _landmarks[1]
	a.position = Vector3(-62.0 * k, 0.0, z)
	b.position = Vector3(70.0 * k, 0.0, z - 95.0 * k)


## 撤离区得看得见，否则玩家不知道该往哪儿跑
func _build_start_marker() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(26.0, 16.0)
	mi.mesh = pm
	mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	mi.position = Vector3(0.0, 0.06, -8.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.85, 0.45, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	add_child(mi)

	var tag := Label3D.new()
	tag.text = "起点 / 撤离"
	tag.font_size = 40
	tag.position = Vector3(0.0, 2.6, -8.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(tag)


func _process(delta: float) -> void:
	GameState.run_time += delta      # 喷气起步要看开局秒数
	GameState.tick_income(delta)
	_track.call("update", _player.position.z)
	if _cam_ready:
		var sp := GameState.get_run_speed()
		var zoom := CreatureDB.camera_zoom(sp)
		var want := _player.position + CAM_OFFSET * zoom
		_cam.position = _cam.position.lerp(want, clampf(CAM_LERP * delta, 0.0, 1.0))
		# FOV 随速度撑开：这是最便宜也最有效的"我在变快"信号
		_cam.fov = CAM_FOV + clampf(sp * FOV_PER_SPEED, 0.0, FOV_MAX_BOOST)
		# 高速时轻微抖动，速度感里"体感"的那一半
		var shake := clampf((sp - 25.0) / 60.0, 0.0, 1.0) * 0.09 * zoom
		if shake > 0.001:
			_cam.position.x += randf_range(-shake, shake)
			_cam.position.y += randf_range(-shake, shake)
	_update_landmarks()
	_handle_grab(delta)
	_check_escape()
	if _toast_time > 0.0:
		_toast_time -= delta
	_update_hud()


# ── 偷蛋 ───────────────────────────────────────
func _handle_grab(delta: float) -> void:
	if _grab_target != null:
		_player.set("frozen", true)
		_grab_progress += delta
		var need := GameState.get_grab_time()
		_bar.visible = true
		_bar.value = clampf(_grab_progress / need, 0.0, 1.0) * 100.0
		if _grab_progress >= need:
			_finish_grab()
		return

	_player.set("frozen", false)
	_bar.visible = false
	if Input.is_key_pressed(KEY_E):
		_try_grab()


func _try_grab() -> void:
	var best: Node3D = null
	var bd := GRAB_RANGE
	for e in get_tree().get_nodes_in_group("eggs"):
		if bool(e.get("taken")):
			continue
		var d := _flat_dist(e)
		if d < bd:
			bd = d
			best = e as Node3D
	if best != null:
		_grab_target = best
		_grab_progress = 0.0


func _finish_grab() -> void:
	_grab_target.call("take")
	var d: Dictionary = _grab_target.get("data")
	GameState.add_carried(d)
	var nm := str(d.get("name", "蛋"))
	GameEvents.egg_stolen.emit(int(d.get("tier", 1)), nm)
	_show_toast("得手：%s（%s）" % [nm, str(d.get("quality_name", "普通"))])
	var sneaked := bool(_player.get("sneaking"))
	_wake_nearby(_grab_target.global_position, NOISE_RADIUS * (0.5 if sneaked else 1.0))
	_grab_target = null
	_grab_progress = 0.0
	_player.set("frozen", false)


## 不只是蛋主人醒，动静范围内的也醒——但它们是被吵醒的，反应比主人慢一半
func _wake_nearby(pos: Vector3, r: float) -> void:
	for c in get_tree().get_nodes_in_group("creatures"):
		if bool(c.call("is_asleep")):
			var d := Vector2(c.global_position.x - pos.x, c.global_position.z - pos.z).length()
			if d < r:
				var base := float(c.call("get_base_wake"))
				c.call("wake", GameState.get_wake_delay(base) * 1.5)


# ── 撤离 ───────────────────────────────────────
func _check_escape() -> void:
	if GameState.carried.is_empty():
		return
	if _player.position.z > ESCAPE_Z:
		var n := GameState.store_carried()
		GameEvents.escaped.emit(n)
		SaveManager.save()
		get_tree().change_scene_to_file("res://scenes/farm.tscn")


func _on_caught(lost: Dictionary) -> void:
	if lost.is_empty():
		_show_toast("被撞飞了！速度 ×0.97")
	else:
		_show_toast("%s 被抢回去了！速度 ×0.97" % str(lost.get("name", "蛋")))


func _show_toast(text: String) -> void:
	_toast = text
	_toast_time = 2.6


# ── HUD ────────────────────────────────────────
func _update_hud() -> void:
	var dist := maxf(0.0, -_player.position.z)
	if dist > GameState.best_distance:
		GameState.best_distance = dist
	var tier := CreatureDB.tier_at(dist, GameState.start_tier)
	var td: Dictionary = CreatureDB.tier_data(tier)
	var carried_n := GameState.carried.size()

	var nt := CreatureDB.distance_to_next_tier(dist, GameState.start_tier)
	var nt_txt := "下一阶还有 %.0f m" % nt if nt > 0.0 else "已是最深阶"
	var my := GameState.get_display_speed()
	var foe := float(td.get("speed", 6.0)) * GameState.DISPLAY_SPEED_SCALE
	_info.text = "距离 %.0f m（%s）｜ T%d %s（%.0f km/h）｜ 你 %.0f km/h【%s】｜ 携带 %d 颗 ｜ 被抓 %d 次 ×%.2f ｜ %.0f 金币" % [
		dist, nt_txt, tier, str(td.get("name", "")), foe,
		my, GameState.speed_title(my), carried_n,
		GameState.catch_count, GameState.get_penalty_multiplier(), GameState.coins,
	]

	if carried_n > 0:
		_hint.text = "带着 %d 颗蛋——跑回起点撤离，路上被追上就赔进去" % carried_n
	else:
		_hint.text = "WASD 移动 ｜ Shift 蹲走（安静但慢）｜ E 偷蛋 ｜ ESC 放弃这一趟"

	_toast_label.text = _toast if _toast_time > 0.0 else ""


func _flat_dist(other: Node3D) -> float:
	var a := _player.global_position
	var b := other.global_position
	return Vector2(a.x - b.x, a.z - b.z).length()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (event as InputEventKey).keycode == KEY_ESCAPE:
		GameState.reset_run()
		get_tree().change_scene_to_file("res://scenes/farm.tscn")
