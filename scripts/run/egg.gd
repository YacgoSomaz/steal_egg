extends Node3D
## 蛋：躺在沉睡巨兽身边，拿走它就会把主人吵醒
##
## ⭐ 蛋的外观**按品质分档**。这不是装饰——品质是按跑道长度抽的，
## 玩家必须能"远远看见那颗蛋不一样"，才会产生"再往前跑一点"的冲动。
## 只改数值不改外观的话，稀有度曲线在玩家眼里根本不存在。

const CreatureDB := preload("res://scripts/data/creature_db.gd")

var data: Dictionary = {}
var owner_creature: Node3D = null
var taken := false
var _t := 0.0
var _mesh: MeshInstance3D
var _quality := 0
var _base_y := 0.6
var _mat: StandardMaterial3D
var _glow: MeshInstance3D = null


func setup(d: Dictionary, owner_ref: Node3D) -> void:
	data = d
	owner_creature = owner_ref
	add_to_group("eggs")
	_build()


func _build() -> void:
	_quality = CreatureDB.quality_index(str(data.get("quality_name", "普通")))

	_mesh = MeshInstance3D.new()
	var m := SphereMesh.new()
	# 越稀有越大一点，轮廓上就能分出来
	var big := 1.0 + float(_quality) * 0.12
	m.radius = 0.42 * big
	m.height = 1.15 * big
	_mesh.mesh = m

	# 品质越高，颜色越往「绿 → 金 → 紫」偏，并且开始自发光
	var base := Color(data.get("color", Color(0.95, 0.92, 0.82)))
	match _quality:
		0:
			pass
		1:
			base = base.lerp(Color(0.55, 1.0, 0.65), 0.35)
		2:
			base = base.lerp(Color(1.0, 0.92, 0.45), 0.55)
		3:
			base = base.lerp(Color(0.85, 0.45, 1.0), 0.65)

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = base
	if _quality >= 1:
		_mat.emission_enabled = true
		_mat.emission = base
		_mat.emission_energy_multiplier = 0.35 + float(_quality) * 0.5
	_mesh.material_override = _mat
	add_child(_mesh)

	# 闪光 / 变异：外面再套一层半透明光晕，隔着几十米也认得出
	if _quality >= 2:
		_glow = MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 0.62 * big
		gm.height = 1.5 * big
		_glow.mesh = gm
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(base.r, base.g, base.b, 0.22)
		gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.material_override = gmat
		add_child(_glow)

		# 头顶直接标出来，玩家不用凑近看颜色
		var tag := Label3D.new()
		tag.text = str(data.get("quality_name", ""))
		tag.font_size = 30
		tag.position = Vector3(0.0, 1.5, 0.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = base
		tag.outline_size = 8
		add_child(tag)


func _process(delta: float) -> void:
	if taken:
		return
	_t += delta
	# 轻微浮动 + 自转，让玩家远远就能看见"这有个蛋"。
	# 稀有蛋浮得更高、转得更快，动感上也不一样。
	var bob := 0.09 + float(_quality) * 0.03
	_mesh.position.y = _base_y + sin(_t * (2.0 + float(_quality) * 0.5)) * bob
	_mesh.rotation.y += delta * (0.6 + float(_quality) * 0.35)
	# 稀有蛋的光晕一呼一吸：静止的发光看着像贴图，呼吸起来才像"活的"
	if _glow != null:
		var pulse := 1.0 + sin(_t * 2.6) * 0.10
		_glow.scale = Vector3(pulse, pulse, pulse)
		if _mat != null:
			_mat.emission_energy_multiplier = \
					0.35 + float(_quality) * 0.5 + sin(_t * 2.6) * 0.25


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
