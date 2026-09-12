extends Node2D
## 程序化动画：零美术资源，用正弦驱动腿部摆动 + 身体形变
## 负重直接反映在身体压扁与前倾上 —— 表现与数值绑定

var _t := 0.0

@onready var _parent := get_parent() as CharacterBody2D
@onready var _body: Polygon2D = _parent.get_node("Body")
@onready var _head: Polygon2D = _parent.get_node("Head")
@onready var _leg_l: Polygon2D = _parent.get_node("LegL")
@onready var _leg_r: Polygon2D = _parent.get_node("LegR")


func _ready() -> void:
	_setup_polygons()


## 占位符几何体：全部代码生成，后续换美术只需替换这里
func _setup_polygons() -> void:
	_body.polygon = _ellipse(15.0, 17.0)
	_body.color = Color(0.30, 0.45, 0.62)
	_head.polygon = _ellipse(11.0, 10.0)
	_head.position = Vector2(0, -18)
	_head.color = Color(0.92, 0.80, 0.65)
	_leg_l.polygon = _rect(6.0, 16.0)
	_leg_l.position = Vector2(-6, 14)
	_leg_l.color = Color(0.25, 0.30, 0.38)
	_leg_r.polygon = _rect(6.0, 16.0)
	_leg_r.position = Vector2(6, 14)
	_leg_r.color = Color(0.25, 0.30, 0.38)


func _ellipse(rx: float, ry: float, steps: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _rect(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0),
		Vector2(w * 0.5, h), Vector2(-w * 0.5, h),
	])


func _process(delta: float) -> void:
	if _parent == null:
		return

	var moving := _parent.velocity.length() > 1.0
	if moving:
		_t += delta * 9.0
		var swing := sin(_t) * 0.5
		_leg_l.rotation = swing
		_leg_r.rotation = -swing
		_body.scale.y = 1.0 + sin(_t * 2.0) * 0.06
		_body.scale.x = 1.0 - sin(_t * 2.0) * 0.04
	else:
		_leg_l.rotation = lerpf(_leg_l.rotation, 0.0, 0.2)
		_leg_r.rotation = lerpf(_leg_r.rotation, 0.0, 0.2)

	# 负重可视化：背得越多，身体越压、越前倾
	var n := GameState.carried_eggs.size()
	_body.scale.y = 1.0 - float(n) * 0.045
	_body.rotation = float(n) * 0.022
