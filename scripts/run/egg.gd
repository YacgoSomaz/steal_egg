extends Node3D
## 蛋：躺在沉睡巨兽身边，拿走它就会把主人吵醒

var data: Dictionary = {}
var owner_creature: Node3D = null
var taken := false
var _t := 0.0
var _mesh: MeshInstance3D


func setup(d: Dictionary, owner_ref: Node3D) -> void:
	data = d
	owner_creature = owner_ref
	add_to_group("eggs")
	_build()


func _build() -> void:
	_mesh = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.42
	m.height = 1.15
	_mesh.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(data.get("color", Color(0.95, 0.92, 0.82)))
	_mesh.material_override = mat
	add_child(_mesh)


func _process(delta: float) -> void:
	if taken:
		return
	_t += delta
	# 轻微浮动 + 自转，让玩家远远就能看见"这有个蛋"
	_mesh.position.y = 0.6 + sin(_t * 2.0) * 0.09
	_mesh.rotation.y += delta * 0.6


func take() -> void:
	taken = true
	visible = false
	if owner_creature != null and owner_creature.has_method("wake"):
		# 蛋没了 → 这只从此不追回来不罢休
		if owner_creature.has_method("on_egg_stolen"):
			owner_creature.call("on_egg_stolen")
		# 什么时候醒，取决于玩家点了多少隐蔽——这是隐蔽唯一的用武之地
		var base := float(owner_creature.call("get_base_wake"))
		owner_creature.call("wake", GameState.get_wake_delay(base))
