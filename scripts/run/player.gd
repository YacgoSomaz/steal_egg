extends CharacterBody3D
## 玩家：沿跑道自由移动（WASD），Shift 蹲走更安静但更慢
## 偷蛋读条期间 frozen，站着挨最脆弱的那几秒

const CreatureDB := preload("res://scripts/data/creature_db.gd")
const SPEED_FX := preload("res://scenes/run/speed_fx.tscn")
const SPEED_FX_REF := 60.0           # 前倾到这个速度压满
const FARM_HALF_W := 24.0            # 农场区的可行走半宽（要和 farm_zone 的围栏对齐）
const FARM_END_Z := 71.0             # 农场尽头，别走出围栏

var sneaking := false
var frozen := false
var _t := 0.0
var _legs: Array = []
var _model: Node3D          # 单独一层，用来做前倾——不能直接转 body，朝向会被盖掉
var _fx: Node


func _ready() -> void:
	add_to_group("player")
	_model = Node3D.new()
	add_child(_model)
	_build()
	var fx := SPEED_FX.instantiate()
	add_child(fx)
	_fx = fx


func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.52, 0.86)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.92, 0.78, 0.62)

	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.36
	bm.height = 1.1
	body.mesh = bm
	body.position.y = 1.05
	body.material_override = mat
	_model.add_child(body)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.31
	hm.height = 0.62
	head.mesh = hm
	head.position.y = 1.82
	head.material_override = skin
	_model.add_child(head)

	# 背包：背蛋的地方，蛋越多鼓得越大
	var pack := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.5, 0.5, 0.3)
	pack.mesh = pm
	pack.position = Vector3(0, 1.15, 0.42)
	pack.material_override = skin
	_model.add_child(pack)

	for sx in [-0.19, 0.19]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.19, 0.75, 0.19)
		leg.mesh = lm
		leg.position = Vector3(sx, 0.38, 0.0)
		leg.material_override = mat
		_model.add_child(leg)
		_legs.append(leg)


func _physics_process(delta: float) -> void:
	_t += delta
	if frozen:
		velocity = Vector3.ZERO
		move_and_slide()
		_leg_swing(0.0)
		_fx.call("update", 0.0, false)
		_model.rotation.x = 0.0
		return

	# 用自定义动作，WASD 和方向键都绑了（内置 ui_* 在 Godot 4 里只有方向键）
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	sneaking = Input.is_key_pressed(KEY_SHIFT)
	var sp := GameState.get_run_speed()
	if sneaking:
		sp *= 0.55
	velocity = Vector3(input.x, 0.0, input.y) * sp
	if velocity.length() > 0.01:
		rotation.y = atan2(-velocity.x, -velocity.z)
	move_and_slide()
	# 跑道随阶位变宽，所以边界也得跟着算；相机拉远时人同步放大，不然就成蚂蚁了
	var k := CreatureDB.world_scale(CreatureDB.tier_at(maxf(0.0, -position.z), GameState.start_tier))
	var half := 12.0 * k
	if position.z > 0.0:
		half = FARM_HALF_W          # 农场区更宽，摊位一路排到 ±19.5
	position.x = clampf(position.x, -half, half)
	# 农场尽头有围栏，别走出去
	position.z = minf(position.z, FARM_END_Z)
	position.y = 0.0
	var ms := CreatureDB.model_scale(sp)
	scale = Vector3(ms, ms, ms)
	_leg_swing(velocity.length())

	var moving := velocity.length() > 0.5
	_fx.call("update", sp, moving)
	# 跑得越快压得越低——身体比数字更早告诉你"我现在很快"
	_model.rotation.x = -clampf(sp / SPEED_FX_REF, 0.0, 1.0) * 0.20 if moving else 0.0


func _leg_swing(speed: float) -> void:
	var amp := clampf(speed * 0.055, 0.0, 0.7)
	var s := sin(_t * (6.0 + speed * 0.9)) * amp
	for i in range(_legs.size()):
		var leg: Node3D = _legs[i]
		leg.rotation.x = s if i == 0 else -s
