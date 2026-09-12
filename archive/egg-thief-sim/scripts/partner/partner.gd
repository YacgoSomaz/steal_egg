extends Node2D
## 伙伴：跟随玩家出战，提供被动修正与主动技能
## 占位符美术：几何体，体型与配色随阶位变化
## 这是「养成反哺偷窃」的具象化 —— 让玩家看得见自己养的东西在帮忙

@export var follow_distance: float = 52.0
@export var follow_speed: float = 3.2

var partner_name: String = ""
var tier: int = 1

var _player: Node2D = null
var _bob: float = 0.0

@onready var _body: Polygon2D = $Body


func setup(nm: String, t: int) -> void:
	partner_name = nm
	tier = t
	_body.polygon = _shape()
	_body.color = _color()
	# 阶位越高体型越大：T1 小小的，T10 快跟玩家一样大
	scale = Vector2.ONE * (0.55 + float(tier) * 0.06)


func _process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
		return
	if _player == null:
		return

	var to_player: Vector2 = _player.global_position - global_position
	var dist: float = to_player.length()
	if dist > follow_distance:
		var desired: Vector2 = _player.global_position - to_player.normalized() * follow_distance
		global_position = global_position.lerp(desired, clampf(follow_speed * delta, 0.0, 1.0))

	# 轻轻上下浮动，看起来是活的
	_bob += delta * 3.0
	_body.position.y = sin(_bob) * 2.5

	# 技能激活时发亮
	_body.color = _color().lightened(0.45) if GameState.skill_active else _color()


func _shape() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 14
	var rx := 13.0
	var ry := 10.0
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _color() -> Color:
	return Color.from_hsv(fmod(float(tier) * 0.11, 1.0), 0.45, 0.85)
