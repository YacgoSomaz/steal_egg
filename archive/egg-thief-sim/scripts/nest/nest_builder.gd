extends Node2D
## 程序化生成巢穴：边界墙、掩体、地面材质区
## 占位符美术：全部几何体代码生成，后续换美术不影响逻辑
## 掩体会挡住守卫视线（RayCast 被 StaticBody2D 挡下），这是潜行的核心

@export var room_size := Vector2(1280, 720)
@export var wall_thickness := 32.0

const NestDB := preload("res://scripts/data/nest_db.gd")

const COVER_COLOR := Color(0.30, 0.38, 0.30)
const WALL_COLOR := Color(0.22, 0.20, 0.24)

var egg_spots: Array = []   # 由 layout 决定，交给 main.gd 生成蛋


func _ready() -> void:
	var layout: Dictionary = NestDB.layout_for(GameState.current_tier)
	egg_spots = layout.get("egg_spots", [])
	_build_background(layout)
	_build_ground_zones(layout)
	_build_walls()
	_build_covers(layout)


func _build_background(layout: Dictionary) -> void:
	var bg := Polygon2D.new()
	bg.name = "Background"
	bg.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(room_size.x, 0),
		Vector2(room_size.x, room_size.y), Vector2(0, room_size.y),
	])
	bg.color = layout.get("bg", Color(0.8, 0.8, 0.8))
	bg.z_index = -10
	add_child(bg)


# ── 地面材质区（影响噪音）────────────────────────
func _build_ground_zones(layout: Dictionary) -> void:
	for z in layout.get("zones", []):
		_add_ground_zone(
			z.get("pos", Vector2.ZERO),
			z.get("size", Vector2(200, 200)),
			z.get("color", Color(0.5, 0.5, 0.5)),
			float(z.get("mult", 1.0)),
		)


func _add_ground_zone(center: Vector2, size: Vector2, color: Color, mult: float) -> void:
	var zone := Area2D.new()
	zone.name = "GroundZone_%d" % get_child_count()
	zone.position = center
	zone.collision_layer = 0
	zone.collision_mask = 0
	zone.monitoring = false
	zone.monitorable = false
	zone.set_meta("noise_multiplier", mult)
	zone.set_meta("zone_size", size)
	zone.add_to_group("ground_zones")
	add_child(zone)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	zone.add_child(shape)

	var vis := Polygon2D.new()
	vis.polygon = _rect_polygon(size)
	vis.color = Color(color.r, color.g, color.b, 0.35)
	zone.add_child(vis)


# ── 边界墙 ─────────────────────────────────────
func _build_walls() -> void:
	var t := wall_thickness
	var specs := [
		[Vector2(room_size.x * 0.5, t * 0.5), Vector2(room_size.x, t)],
		[Vector2(room_size.x * 0.5, room_size.y - t * 0.5), Vector2(room_size.x, t)],
		[Vector2(t * 0.5, room_size.y * 0.5), Vector2(t, room_size.y)],
		[Vector2(room_size.x - t * 0.5, room_size.y * 0.5), Vector2(t, room_size.y)],
	]
	for s in specs:
		_add_solid(s[0], s[1], WALL_COLOR)


# ── 掩体 ───────────────────────────────────────
func _build_covers(layout: Dictionary) -> void:
	for c in layout.get("covers", []):
		_add_solid(c.get("pos", Vector2.ZERO), c.get("size", Vector2(80, 80)), COVER_COLOR)


# ── 工具 ───────────────────────────────────────
func _add_solid(center: Vector2, size: Vector2, color: Color) -> void:
	var body := StaticBody2D.new()
	body.name = "Solid_%d" % get_child_count()
	body.position = center
	add_child(body)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)

	var vis := Polygon2D.new()
	vis.polygon = _rect_polygon(size)
	vis.color = color
	body.add_child(vis)


func _rect_polygon(size: Vector2) -> PackedVector2Array:
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	return PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh),
	])
