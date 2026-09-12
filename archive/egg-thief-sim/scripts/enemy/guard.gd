extends CharacterBody2D
## Phase 0 守卫：巡逻 + 视野锥 + 追击
## 视野锥是每帧重算的 Polygon2D，半径直接受玩家「隐匿」属性缩放

enum State { PATROL, CHASE }

@export var patrol_points: Array[Vector2] = []
@export var view_distance: float = 240.0
@export var view_angle: float = 70.0
@export var patrol_speed: float = 70.0
@export var chase_speed: float = 95.0
@export var spot_alert_rate: float = 15.0   # 被看见时警戒增速；这个数只能靠试玩定

var _state := State.PATROL
var _target_index := 0
var _seeing_player := false
var _stuck_time := 0.0

@onready var _cone: Polygon2D = $ViewCone
@onready var _ray: RayCast2D = $ViewRay
@onready var _body: Polygon2D = $Body


func _ready() -> void:
	add_to_group("guards")
	_setup_polygons()
	if _ray:
		_ray.add_exception(self)      # 射线别打到自己身上
	if patrol_points.is_empty():
		patrol_points = [
			global_position + Vector2(-160, 0),
			global_position + Vector2(160, 0),
		]


## 占位符几何体
func _setup_polygons() -> void:
	if _body:
		var pts := PackedVector2Array()
		for i in range(16):
			var a := TAU * float(i) / 16.0
			pts.append(Vector2(cos(a) * 20.0, sin(a) * 15.0))
		_body.polygon = pts
		_body.color = Color(0.72, 0.30, 0.28)
	var eye := Polygon2D.new()
	eye.name = "Eye"
	eye.polygon = PackedVector2Array([
		Vector2(6, -5), Vector2(16, 0), Vector2(6, 5),
	])
	eye.color = Color(1, 0.9, 0.4)
	add_child(eye)


func _physics_process(delta: float) -> void:
	var player := _get_player()
	_seeing_player = _can_see(player) if player else false

	if _seeing_player:
		_state = State.CHASE
		GameState.was_spotted = true
		GameState.add_alert(spot_alert_rate * delta)   # 被看见：警戒飞涨
		GameEvents.guard_spotted_player.emit(self)
	else:
		_state = State.PATROL

	_move(delta)
	_face_direction()
	_update_cone()


func _move(delta: float) -> void:
	var before := global_position
	if _state == State.CHASE:
		var player := _get_player()
		if player:
			velocity = global_position.direction_to(player.global_position) * _effective_chase_speed()
	else:
		if patrol_points.is_empty():
			velocity = Vector2.ZERO
			return
		var target: Vector2 = patrol_points[_target_index]
		var dir := global_position.direction_to(target)
		velocity = dir * patrol_speed
		if global_position.distance_to(target) < 12.0:
			_target_index = (_target_index + 1) % patrol_points.size()
	move_and_slide()

	# 撞上掩体或墙卡住就换目标点，避免守卫原地抖动
	if global_position.distance_to(before) < 0.4:
		_stuck_time += delta
		if _stuck_time > 0.35:
			_target_index = (_target_index + 1) % patrol_points.size()
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0


## T8 伙伴（高山龙）威压：守卫追击速度 −20%；T10 宇宙龙全面免疫即包含此效果
func _effective_chase_speed() -> float:
	if GameState.has_partner_passive("intimidate") or GameState.has_partner_passive("cosmic"):
		return chase_speed * 0.8
	return chase_speed


func _face_direction() -> void:
	if velocity.length() > 1.0:
		global_rotation = velocity.angle()


func _get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


func _can_see(player: Node2D) -> bool:
	if player == null:
		return false
	var to: Vector2 = player.global_position - global_position
	var dist: float = to.length()
	var max_dist: float = view_distance * GameState.get_perception_multiplier() * GameState.env_vision_mult * GameState.get_skill_vision_multiplier()   # 隐匿 + 环境 + 技能
	if dist > max_dist:
		return false
	var half: float = deg_to_rad(view_angle) * 0.5
	var ang_diff: float = absf(wrapf(to.angle() - global_rotation, -PI, PI))
	if ang_diff > half:
		return false
	# 遮挡判定
	_ray.target_position = to.rotated(-global_rotation)
	_ray.force_raycast_update()
	if _ray.is_colliding():
		var collider: Node = _ray.get_collider() as Node
		if collider != player and not (collider is TileMapLayer):
			return false
	return true


func _update_cone() -> void:
	var max_dist := view_distance * GameState.get_perception_multiplier()
	var half := deg_to_rad(view_angle) * 0.5
	var steps := 24
	var pts: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	for i in range(steps + 1):
		var a := -half + (float(i) / float(steps)) * (half * 2.0)
		pts.append(Vector2.RIGHT.rotated(a) * max_dist)
	_cone.polygon = pts
	_cone.modulate = Color(1, 0.35, 0.3, 0.28) if _state == State.CHASE else Color(1, 0.85, 0.4, 0.22)
