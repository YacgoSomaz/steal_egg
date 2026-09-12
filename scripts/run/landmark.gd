extends Node3D
## 远处的巨型生物
##
## 不参与玩法，只负责回答一个问题：**再往前走，等着我的是什么东西？**
## 玩家应该远远就看见地平线上那个巨大的轮廓，然后自己决定要不要继续深入。
## 这就是「一开始就把宇宙龙摆在玩家眼前」在这一版里的落地方式。

const CreatureDB := preload("res://scripts/data/creature_db.gd")

var _t := 0.0
var _tier := 0
var _body: Node3D
var _yaw := 0.0


func setup(t: int, side: int) -> void:
	if t == _tier:
		return
	_tier = t
	for c in get_children():
		c.queue_free()
	_build(side)


func _build(side: int) -> void:
	var td: Dictionary = CreatureDB.tier_data(_tier)
	var col := Color(td.get("color", Color.WHITE))
	# 压暗 + 交给雾去糊，远看就是一坨有压迫感的剪影
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col.darkened(0.3)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = col.darkened(0.5)

	var k: float = 1.0 + float(_tier) * 0.16      # T1 ×1.16 → T10 ×2.6

	_body = Node3D.new()
	add_child(_body)

	var torso := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(14.0, 11.0, 26.0) * k
	torso.mesh = bm
	torso.position.y = 13.0 * k
	torso.material_override = mat
	_body.add_child(torso)

	var neck := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(5.0, 12.0, 5.0) * k
	neck.mesh = nm
	neck.position = Vector3(0.0, 20.0 * k, -11.0 * k)
	neck.rotation_degrees = Vector3(28.0, 0.0, 0.0)
	neck.material_override = mat
	_body.add_child(neck)

	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(8.0, 7.0, 11.0) * k
	head.mesh = hm
	head.position = Vector3(0.0, 26.0 * k, -17.0 * k)
	head.material_override = mat
	_body.add_child(head)

	for sx in [-0.32, 0.32]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 1.1 * k
		em.height = 2.2 * k
		eye.mesh = em
		eye.position = Vector3(sx * 8.0 * k, 28.0 * k, -22.0 * k)
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(1.0, 0.75, 0.25)
		eye.material_override = emat
		_body.add_child(eye)

	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(4.0, 14.0, 4.0) * k
			leg.mesh = lm
			leg.position = Vector3(sx * 5.0 * k, 7.0 * k, sz * 8.0 * k)
			leg.material_override = dark
			_body.add_child(leg)

	var tail := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(3.0, 3.0, 22.0) * k
	tail.mesh = tm
	tail.position = Vector3(0.0, 11.0 * k, 22.0 * k)
	tail.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	tail.material_override = dark
	_body.add_child(tail)

	# 侧身站着，轮廓比正面更有辨识度
	_yaw = 32.0 * float(side)
	_body.rotation_degrees = Vector3(0.0, _yaw, 0.0)


func _process(delta: float) -> void:
	_t += delta
	if _body == null:
		return
	# 极缓慢的呼吸——它在睡，但它是活的
	_body.scale.y = 1.0 + sin(_t * 0.35) * 0.022
	_body.position.y = sin(_t * 0.35) * 0.6
	_body.rotation_degrees.y = _yaw + sin(_t * 0.11) * 3.0
