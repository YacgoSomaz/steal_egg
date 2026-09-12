extends Area2D
## Phase 0 蛋实体：可被拾取、被背在背上、掉落
## 占位符：椭圆 Polygon2D，活性发光由 modulate 表现

@export var egg_name: String = "鸡蛋"
@export var weight: float = 1.0
@export var tier: int = 1
@export var base_value: int = 1
@export var hatch_time: float = 20.0

var is_carried: bool = false
var quality_name: String = "普通"
var quality_mult: float = 1.0


@onready var _visual: Polygon2D = $Visual


func _ready() -> void:
	add_to_group("eggs")
	if _visual:
		var pts := PackedVector2Array()
		for i in range(18):
			var a := TAU * float(i) / 18.0
			# 蛋形：上窄下宽
			pts.append(Vector2(cos(a) * 11.0, sin(a) * 15.0 - cos(a) * 3.0))
		_visual.polygon = pts
		_visual.color = Color(0.96, 0.93, 0.82)


## 套用 EggDB 生成的品种数据（品种名 / 阶位 / 价值 / 品质 / 颜色）
func apply_data(data: Dictionary) -> void:
	egg_name = str(data.get("name", "蛋"))
	tier = int(data.get("tier", 1))
	base_value = int(data.get("value", 1))
	hatch_time = float(data.get("hatch_time", 20.0))
	quality_name = str(data.get("quality_name", "普通"))
	quality_mult = float(data.get("quality_mult", 1.0))
	if _visual:
		_visual.color = data.get("color", Color(1, 1, 1))
		# 闪光/变异品质额外发光
		var q := int(data.get("quality", 0))
		if q >= 2:
			_visual.color = _visual.color.lightened(0.18)


## 被玩家拿走：脱离场景树，挂到玩家的 CarrySlot 上
func pick_up(slot: Node2D) -> void:
	is_carried = true
	if get_parent():
		get_parent().remove_child(self)
	slot.add_child(self)
	position = Vector2(0, -18 - slot.get_child_count() * 10)
	scale = Vector2(0.7, 0.7)
	monitoring = false
	print("[Phase0] 拿到 %s" % egg_name)


## 掉落：回到主场景并摔在地上
func drop() -> void:
	is_carried = false
	if get_parent():
		get_parent().remove_child(self)
	var main: Node = get_tree().current_scene
	main.add_child(self)
	global_position = (get_tree().get_first_node_in_group("player") as Node2D).global_position
	global_position += Vector2(randf_range(-30, 30), randf_range(-30, 30))
	scale = Vector2(1, 1)
	monitoring = true
	GameState.add_alert(20.0)      # 蛋掉地上 = 巨大声响
	GameEvents.egg_dropped.emit(self)
	print("[Phase0] %s 掉了！" % egg_name)
