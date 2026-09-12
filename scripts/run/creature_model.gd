extends RefCounted
## 十阶怪物的程序化建模
##
## 每一阶的轮廓必须一眼分得出来。光靠颜色和体型缩放，玩家只会觉得
## 「这不就是同一只放大了吗」——所以十阶各有各的身体蓝图：
##
##   T1  草鸡     两足 · 圆身 · 尾羽 · 鸡冠
##   T2  林蜥     四足低伏 · 长尾 · 背脊
##   T3  岩龟     圆壳 · 短腿 · 缩头
##   T4  火蜥     直立 · 背棘 · 长尾 · 自发光
##   T5  冰熊     厚重 · 肩峰 · 粗腿 · 圆耳
##   T6  深海鱼龙 无腿浮游 · 背鳍 · 尾鳍 · 发光斑
##   T7  穴居魔虫 分节 · 无腿 · 大颚
##   T8  高山飞龙 大翼 · 长颈 · 头角
##   T9  云间星龙 蛇形浮游 · 发光 · 飘带
##   T10 宇宙龙   三头 · 光环 · 悬浮
##
## 零美术资源，全用 BoxMesh / SphereMesh / CylinderMesh / TorusMesh 拼。
## 返回的 Dictionary 带出动画挂钩：legs 摆腿 / segs 波动 / wings 扇翅 / halo 转环。

const CreatureDB := preload("res://scripts/data/creature_db.gd")

## 材质槽下标
const MB := 0   # 主体
const MD := 1   # 暗部（腿、爪、鳍）
const ML := 2   # 亮部（腹面、翼膜）
const ME := 3   # 眼睛
const MG := 4   # 自发光（高阶怪的"这玩意儿不科学"感）

const SLEEP_SQUASH := 0.55   # 睡着时压扁到多少（原来是 0.42，太像煎饼了）

## 各阶模型的大致高度，用来把 zZz 和头顶标签放到正确的高度。
## 手写查表而不是算 AABB：建好的模型里有 pivot 包裹的腿和翼，
## 算包围盒要处理多层变换，而这几个数字是我摆模型时就知道的。
const TOPS: Array = [0.0, 2.4, 1.4, 1.8, 2.8, 2.5, 2.6, 1.7, 3.8, 2.7, 4.4]


static func top_of(tier: int) -> float:
	var i := clampi(tier, 1, 10)
	return float(TOPS[i])


static func build(tier: int) -> Dictionary:
	var d: Dictionary = CreatureDB.tier_data(tier)
	var col: Color = Color(d.get("color", Color.WHITE))
	var root := Node3D.new()
	var legs: Array = []
	var segs: Array = []
	var wings: Array = []
	var out: Dictionary = {
		"root": root, "legs": legs, "segs": segs, "wings": wings,
		"float": false, "halo": null,
	}
	var mats: Array[StandardMaterial3D] = [
		_mat(col),
		_mat(col.darkened(0.40)),
		_mat(col.lightened(0.28)),
		_mat(Color(1.0, 0.85, 0.25)),
		_glow(col.lightened(0.50)),
	]
	match tier:
		1: _chicken(root, mats, legs, wings)
		2: _lizard(root, mats, legs, segs)
		3: _turtle(root, mats, legs)
		4: _firelizard(root, mats, legs, wings)
		5: _bear(root, mats, legs)
		6: _seadragon(root, mats, segs)
		7: _worm(root, mats, segs)
		8: _wyvern(root, mats, legs, wings)
		9: _stardragon(root, mats, segs, wings)
		10: _cosmic(root, mats, segs, wings, out)
		_: _lizard(root, mats, legs, segs)
	# T6 往后都是浮游种：没有腿（或腿只是装饰），靠上下起伏表现"它还活着"
	if tier >= 6:
		out["float"] = true
	return out


# ── 材质 ───────────────────────────────────────
static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


static func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.8
	m.roughness = 0.4
	return m


# ── 几何体辅助 ─────────────────────────────────
static func _box(parent: Node3D, mat: Material, size: Vector3, pos: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	if rot != Vector3.ZERO:
		m.rotation = rot
	m.material_override = mat
	parent.add_child(m)
	return m


static func _sph(parent: Node3D, mat: Material, r: float, pos: Vector3,
		scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	m.mesh = sm
	m.position = pos
	if scl != Vector3.ONE:
		m.scale = scl
	m.material_override = mat
	parent.add_child(m)
	return m


## 圆锥 / 圆台。默认轴是 +Y，绕 X 转 -90° 即指向 -Z（本作的正前方）
static func _cone(parent: Node3D, mat: Material, r: float, h: float, pos: Vector3,
		rot: Vector3 = Vector3.ZERO, top_r: float = 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 8
	m.mesh = cm
	m.position = pos
	if rot != Vector3.ZERO:
		m.rotation = rot
	m.material_override = mat
	parent.add_child(m)
	return m


static func _torus(parent: Node3D, mat: Material, inner: float, outer: float,
		pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 24
	tm.ring_segments = 12
	m.mesh = tm
	m.position = pos
	m.material_override = mat
	parent.add_child(m)
	return m


## 腿：返回一个挂在髋部的 pivot，网格挂在它下面一半长处，
## 这样摆腿是从髋部转，而不是从腿的中间转
static func _leg(parent: Node3D, mat: Material, pos: Vector3, len: float,
		thick: float, legs: Array) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, len, thick)
	m.mesh = bm
	m.position = Vector3(0.0, -len * 0.5, 0.0)
	m.material_override = mat
	pivot.add_child(m)
	legs.append(pivot)
	return pivot


## 翼：同样用 pivot，从肩根扇动
static func _wing(parent: Node3D, mats: Array[StandardMaterial3D], pos: Vector3,
		span: float, chord: float, side: float, wings: Array) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	# 翼骨
	_box(pivot, mats[MD], Vector3(span, 0.13, 0.16),
			Vector3(side * span * 0.5, 0.0, 0.0))
	# 翼膜（分两段，外段下垂，像真的皮膜）
	_box(pivot, mats[ML], Vector3(span * 0.55, 0.07, chord),
			Vector3(side * span * 0.30, -0.02, chord * 0.18))
	_box(pivot, mats[ML], Vector3(span * 0.5, 0.07, chord * 0.75),
			Vector3(side * span * 0.78, -0.16, chord * 0.42),
			Vector3(0.0, 0.0, side * 0.35))
	wings.append(pivot)
	return pivot


# ═══════════════════════════════════════════════
# T1 草鸡 —— 两足、圆滚、尾羽翘
# ═══════════════════════════════════════════════
static func _chicken(root: Node3D, mats: Array[StandardMaterial3D],
		legs: Array, wings: Array) -> void:
	_leg(root, mats[MD], Vector3(0.22, 0.62, 0.05), 0.62, 0.13, legs)
	_leg(root, mats[MD], Vector3(-0.22, 0.62, 0.05), 0.62, 0.13, legs)
	# 圆滚滚的身体
	_sph(root, mats[MB], 0.62, Vector3(0.0, 1.18, 0.05), Vector3(1.0, 0.95, 1.15))
	# 翅
	var wl := Node3D.new()
	wl.position = Vector3(0.58, 1.22, 0.05)
	root.add_child(wl)
	_box(wl, mats[ML], Vector3(0.14, 0.42, 0.66), Vector3(0.06, -0.04, 0.02))
	var wr := Node3D.new()
	wr.position = Vector3(-0.58, 1.22, 0.05)
	root.add_child(wr)
	_box(wr, mats[ML], Vector3(0.14, 0.42, 0.66), Vector3(-0.06, -0.04, 0.02))
	wings.append(wl)
	wings.append(wr)
	# 尾羽：三片往上翘
	_box(root, mats[MD], Vector3(0.10, 0.52, 0.30), Vector3(0.0, 1.48, 0.72), Vector3(-0.55, 0.0, 0.0))
	_box(root, mats[MD], Vector3(0.10, 0.44, 0.26), Vector3(0.14, 1.44, 0.86), Vector3(-0.75, 0.22, 0.0))
	_box(root, mats[MD], Vector3(0.10, 0.44, 0.26), Vector3(-0.14, 1.44, 0.86), Vector3(-0.75, -0.22, 0.0))
	# 颈 + 头
	_box(root, mats[MB], Vector3(0.30, 0.42, 0.30), Vector3(0.0, 1.72, -0.32))
	_sph(root, mats[MB], 0.29, Vector3(0.0, 1.98, -0.50), Vector3(1.0, 1.0, 1.1))
	# 喙、冠、眼
	_cone(root, mats[ME], 0.11, 0.34, Vector3(0.0, 1.94, -0.86),
			Vector3(-PI * 0.5, 0.0, 0.0), 0.02)
	_box(root, mats[ME], Vector3(0.09, 0.20, 0.28), Vector3(0.0, 2.26, -0.46))
	_sph(root, mats[ME], 0.07, Vector3(0.17, 2.04, -0.68))
	_sph(root, mats[ME], 0.07, Vector3(-0.17, 2.04, -0.68))


# ═══════════════════════════════════════════════
# T2 林蜥 —— 四足低伏、长尾、背脊
# ═══════════════════════════════════════════════
static func _lizard(root: Node3D, mats: Array[StandardMaterial3D],
		legs: Array, segs: Array) -> void:
	for sx in [0.68, -0.68]:
		for sz in [0.72, -0.72]:
			_leg(root, mats[MD], Vector3(sx, 0.48, sz), 0.48, 0.22, legs)
	# 低伏的长躯干
	_box(root, mats[MB], Vector3(0.92, 0.54, 2.00), Vector3(0.0, 0.80, 0.15))
	_box(root, mats[ML], Vector3(0.80, 0.20, 1.70), Vector3(0.0, 0.52, 0.15))
	# 头 + 吻
	_box(root, mats[MB], Vector3(0.60, 0.42, 0.82), Vector3(0.0, 0.90, -1.28))
	_box(root, mats[MD], Vector3(0.38, 0.26, 0.30), Vector3(0.0, 0.83, -1.80))
	_sph(root, mats[ME], 0.10, Vector3(0.24, 1.06, -1.46))
	_sph(root, mats[ME], 0.10, Vector3(-0.24, 1.06, -1.46))
	# 背脊
	for i in range(5):
		var z := -0.55 + float(i) * 0.42
		_box(root, mats[MD], Vector3(0.09, 0.26, 0.20), Vector3(0.0, 1.14, z))
	# 长尾：三节递减
	segs.append(_box(root, mats[MB], Vector3(0.56, 0.40, 0.72), Vector3(0.0, 0.82, 1.48)))
	segs.append(_box(root, mats[MB], Vector3(0.38, 0.28, 0.68), Vector3(0.0, 0.80, 2.08)))
	segs.append(_box(root, mats[MD], Vector3(0.22, 0.16, 0.62), Vector3(0.0, 0.78, 2.62)))


# ═══════════════════════════════════════════════
# T3 岩龟 —— 圆壳、短腿、能缩头
# ═══════════════════════════════════════════════
static func _turtle(root: Node3D, mats: Array[StandardMaterial3D], legs: Array) -> void:
	for sx in [0.92, -0.92]:
		for sz in [0.66, -0.66]:
			_leg(root, mats[MD], Vector3(sx, 0.42, sz), 0.42, 0.34, legs)
	# 腹甲 + 龟壳（压扁的球）
	_box(root, mats[ML], Vector3(1.60, 0.26, 2.05), Vector3(0.0, 0.40, 0.05))
	_sph(root, mats[MB], 1.00, Vector3(0.0, 0.92, 0.05), Vector3(1.12, 0.74, 1.28))
	# 壳上的甲片
	_sph(root, mats[ML], 0.30, Vector3(0.0, 1.52, 0.05), Vector3(1.5, 0.42, 1.6))
	for i in range(6):
		var a := float(i) / 6.0 * TAU
		_sph(root, mats[MD], 0.24, Vector3(
				cos(a) * 0.78, 1.38, 0.05 + sin(a) * 0.90), Vector3(1.3, 0.5, 1.3))
	# 头 + 短颈
	_box(root, mats[MB], Vector3(0.44, 0.40, 0.55), Vector3(0.0, 0.88, -1.30))
	_sph(root, mats[ME], 0.08, Vector3(0.18, 0.98, -1.50))
	_sph(root, mats[ME], 0.08, Vector3(-0.18, 0.98, -1.50))
	_box(root, mats[MD], Vector3(0.24, 0.20, 0.34), Vector3(0.0, 0.62, 1.24))


# ═══════════════════════════════════════════════
# T4 火蜥 —— 直立、背棘、自发光
# ═══════════════════════════════════════════════
static func _firelizard(root: Node3D, mats: Array[StandardMaterial3D],
		legs: Array, wings: Array) -> void:
	for sx in [0.52, -0.52]:
		for sz in [0.42, -0.42]:
			_leg(root, mats[MD], Vector3(sx, 0.88, sz), 0.88, 0.28, legs)
	# 直立的躯干
	_box(root, mats[MB], Vector3(0.92, 1.22, 1.24), Vector3(0.0, 1.52, 0.10))
	_box(root, mats[ML], Vector3(0.72, 0.90, 1.00), Vector3(0.0, 1.42, -0.10))
	_box(root, mats[MB], Vector3(0.86, 0.86, 0.86), Vector3(0.0, 1.18, 0.78))
	# 颈 + 头
	_box(root, mats[MB], Vector3(0.44, 0.76, 0.44), Vector3(0.0, 2.02, -0.52), Vector3(0.32, 0.0, 0.0))
	_box(root, mats[MB], Vector3(0.54, 0.44, 0.84), Vector3(0.0, 2.44, -1.00))
	_box(root, mats[MD], Vector3(0.36, 0.24, 0.30), Vector3(0.0, 2.34, -1.52))
	_sph(root, mats[MG], 0.09, Vector3(0.21, 2.56, -1.24))
	_sph(root, mats[MG], 0.09, Vector3(-0.21, 2.56, -1.24))
	# 背棘：从颈后一路排到尾根
	for i in range(7):
		var k := float(i) / 6.0
		var z := -0.10 + k * 1.50
		var h := 0.46 - k * 0.24
		_cone(root, mats[MG], 0.13, h, Vector3(0.0, 2.18 - k * 0.52, z),
				Vector3(-0.35, 0.0, 0.0), 0.01)
	# 尾
	_box(root, mats[MB], Vector3(0.50, 0.44, 0.80), Vector3(0.0, 1.06, 1.62))
	_box(root, mats[MB], Vector3(0.32, 0.28, 0.74), Vector3(0.0, 0.96, 2.24))
	_box(root, mats[MG], Vector3(0.18, 0.16, 0.64), Vector3(0.0, 0.90, 2.76))
	# 前肢上的小皮膜，跑起来会飘
	for sx in [0.52, -0.52]:
		var f := Node3D.new()
		f.position = Vector3(sx, 1.62, -0.30)
		root.add_child(f)
		_box(f, mats[ML], Vector3(0.10, 0.34, 0.52), Vector3(sx * 0.5, 0.0, 0.06))
		wings.append(f)


# ═══════════════════════════════════════════════
# T5 冰熊 —— 厚重、肩峰、圆耳
# ═══════════════════════════════════════════════
static func _bear(root: Node3D, mats: Array[StandardMaterial3D], legs: Array) -> void:
	for sx in [0.70, -0.70]:
		for sz in [0.60, -0.60]:
			_leg(root, mats[MD], Vector3(sx, 0.92, sz), 0.92, 0.46, legs)
			# 爪
			_box(root, mats[MD], Vector3(0.48, 0.16, 0.30), Vector3(sx, 0.10, sz - 0.22))
	# barrel 躯干 + 肩峰
	_box(root, mats[MB], Vector3(1.48, 1.32, 1.86), Vector3(0.0, 1.42, 0.10))
	_box(root, mats[MB], Vector3(1.30, 0.62, 1.00), Vector3(0.0, 2.00, -0.26))
	_box(root, mats[ML], Vector3(1.10, 0.90, 1.30), Vector3(0.0, 1.20, 0.06))
	# 头 + 吻 + 圆耳
	_box(root, mats[MB], Vector3(0.76, 0.66, 0.82), Vector3(0.0, 1.82, -1.28))
	_box(root, mats[ML], Vector3(0.44, 0.38, 0.36), Vector3(0.0, 1.70, -1.76))
	_sph(root, mats[MD], 0.20, Vector3(0.40, 2.20, -1.16), Vector3(1.0, 1.0, 0.6))
	_sph(root, mats[MD], 0.20, Vector3(-0.40, 2.20, -1.16), Vector3(1.0, 1.0, 0.6))
	_sph(root, mats[ME], 0.09, Vector3(0.24, 1.94, -1.62))
	_sph(root, mats[ME], 0.09, Vector3(-0.24, 1.94, -1.62))
	_box(root, mats[MB], Vector3(0.30, 0.28, 0.42), Vector3(0.0, 1.32, 1.14))


# ═══════════════════════════════════════════════
# T6 深海鱼龙 —— 无腿浮游、背鳍、尾鳍、发光斑
# ═══════════════════════════════════════════════
static func _seadragon(root: Node3D, mats: Array[StandardMaterial3D], segs: Array) -> void:
	# 拉长的纺锤形身体（球沿 Z 拉长）
	segs.append(_sph(root, mats[MB], 0.62, Vector3(0.0, 1.34, 0.10), Vector3(0.95, 0.95, 1.85)))
	# 吻部
	_cone(root, mats[MB], 0.42, 0.86, Vector3(0.0, 1.34, -1.52),
			Vector3(-PI * 0.5, 0.0, 0.0), 0.06)
	# 背鳍
	_box(root, mats[MG], Vector3(0.10, 0.86, 0.78), Vector3(0.0, 2.06, 0.16))
	_box(root, mats[ML], Vector3(0.08, 0.48, 0.44), Vector3(0.0, 1.02, 0.10))
	# 胸鳍
	for sx in [0.78, -0.78]:
		_box(root, mats[ML], Vector3(0.92, 0.09, 0.46),
				Vector3(sx, 1.18, -0.46), Vector3(0.0, 0.0, sx * -0.42))
	# 尾柄 + 尾鳍
	segs.append(_box(root, mats[MB], Vector3(0.34, 0.34, 0.78), Vector3(0.0, 1.30, 1.44)))
	var fluke := Node3D.new()
	fluke.position = Vector3(0.0, 1.30, 1.90)
	root.add_child(fluke)
	_box(fluke, mats[ML], Vector3(0.09, 0.80, 0.52), Vector3(0.0, 0.30, 0.10), Vector3(0.0, 0.0, 0.5))
	_box(fluke, mats[ML], Vector3(0.09, 0.80, 0.52), Vector3(0.0, -0.30, 0.10), Vector3(0.0, 0.0, -0.5))
	segs.append(fluke)
	# 侧线发光斑
	for i in range(4):
		var z := -0.70 + float(i) * 0.62
		_sph(root, mats[MG], 0.09, Vector3(0.56, 1.44, z))
		_sph(root, mats[MG], 0.09, Vector3(-0.56, 1.44, z))
	# 眼
	_sph(root, mats[ME], 0.13, Vector3(0.34, 1.50, -1.14))
	_sph(root, mats[ME], 0.13, Vector3(-0.34, 1.50, -1.14))


# ═══════════════════════════════════════════════
# T7 穴居魔虫 —— 分节、无腿、大颚
# ═══════════════════════════════════════════════
static func _worm(root: Node3D, mats: Array[StandardMaterial3D], segs: Array) -> void:
	# 头节
	var head := _sph(root, mats[MB], 0.78, Vector3(0.0, 0.86, -1.62), Vector3(1.0, 0.92, 1.05))
	segs.append(head)
	_box(root, mats[ML], Vector3(0.86, 0.44, 0.60), Vector3(0.0, 0.52, -1.72))
	# 大颚
	for sx in [0.42, -0.42]:
		_box(root, mats[MD], Vector3(0.16, 0.16, 0.86),
				Vector3(sx, 0.74, -2.32), Vector3(0.0, sx * 0.42, 0.0))
		_cone(root, mats[MD], 0.10, 0.34, Vector3(sx * 0.72, 0.74, -2.68),
				Vector3(-PI * 0.5, 0.0, 0.0), 0.02)
	_sph(root, mats[MG], 0.11, Vector3(0.30, 1.10, -1.94))
	_sph(root, mats[MG], 0.11, Vector3(-0.30, 1.10, -1.94))
	# 体节：从粗到细一路排开，波动时会像真的在蠕动
	for i in range(6):
		var k := float(i) / 5.0
		var r := 0.70 - k * 0.36
		var z := -0.72 + float(i) * 0.62
		var s := _sph(root, mats[MB] if (i % 2 == 0) else mats[MD], r,
				Vector3(0.0, 0.82 - k * 0.16, z), Vector3(1.0, 0.88, 0.95))
		segs.append(s)
	# 背上的骨刺
	for i in range(5):
		var z := -0.30 + float(i) * 0.60
		_cone(root, mats[MD], 0.11, 0.30, Vector3(0.0, 1.44, z))


# ═══════════════════════════════════════════════
# T8 高山飞龙 —— 大翼、长颈、头角
# ═══════════════════════════════════════════════
static func _wyvern(root: Node3D, mats: Array[StandardMaterial3D],
		legs: Array, wings: Array) -> void:
	for sx in [0.48, -0.48]:
		_leg(root, mats[MD], Vector3(sx, 1.20, 0.30), 1.20, 0.34, legs)
	# 躯干
	_box(root, mats[MB], Vector3(1.06, 1.12, 1.66), Vector3(0.0, 1.82, 0.12))
	_box(root, mats[ML], Vector3(0.86, 0.78, 1.30), Vector3(0.0, 1.70, 0.02))
	# 长颈：三节递升
	_box(root, mats[MB], Vector3(0.50, 0.50, 0.62), Vector3(0.0, 2.34, -0.66), Vector3(0.42, 0.0, 0.0))
	_box(root, mats[MB], Vector3(0.42, 0.42, 0.58), Vector3(0.0, 2.78, -1.14), Vector3(0.30, 0.0, 0.0))
	_box(root, mats[MB], Vector3(0.38, 0.38, 0.52), Vector3(0.0, 3.04, -1.58), Vector3(0.16, 0.0, 0.0))
	# 头 + 角
	_box(root, mats[MB], Vector3(0.52, 0.46, 0.86), Vector3(0.0, 3.08, -2.02))
	_box(root, mats[MD], Vector3(0.32, 0.26, 0.32), Vector3(0.0, 2.98, -2.54))
	for sx in [0.24, -0.24]:
		_cone(root, mats[MD], 0.09, 0.52, Vector3(sx, 3.44, -1.86),
				Vector3(0.42, 0.0, sx * -0.30), 0.02)
	_sph(root, mats[ME], 0.10, Vector3(0.22, 3.18, -2.26))
	_sph(root, mats[ME], 0.10, Vector3(-0.22, 3.18, -2.26))
	# 大翼
	_wing(root, mats, Vector3(0.56, 2.26, 0.06), 2.10, 1.30, 1.0, wings)
	_wing(root, mats, Vector3(-0.56, 2.26, 0.06), 2.10, 1.30, -1.0, wings)
	# 尾
	_box(root, mats[MB], Vector3(0.56, 0.52, 0.86), Vector3(0.0, 1.72, 1.32))
	_box(root, mats[MB], Vector3(0.38, 0.34, 0.80), Vector3(0.0, 1.60, 2.06))
	_box(root, mats[MD], Vector3(0.22, 0.20, 0.70), Vector3(0.0, 1.50, 2.72))


# ═══════════════════════════════════════════════
# T9 云间星龙 —— 蛇形浮游、发光、飘带
# ═══════════════════════════════════════════════
static func _stardragon(root: Node3D, mats: Array[StandardMaterial3D],
		segs: Array, wings: Array) -> void:
	# 头
	var head := _sph(root, mats[MB], 0.52, Vector3(0.0, 1.92, -1.94), Vector3(1.0, 0.9, 1.3))
	segs.append(head)
	_box(root, mats[ML], Vector3(0.34, 0.26, 0.56), Vector3(0.0, 1.78, -2.42))
	for sx in [0.22, -0.22]:
		_cone(root, mats[MG], 0.08, 0.62, Vector3(sx, 2.36, -1.80),
				Vector3(0.30, 0.0, sx * -0.34), 0.02)
	_sph(root, mats[MG], 0.11, Vector3(0.24, 2.02, -2.22))
	_sph(root, mats[MG], 0.11, Vector3(-0.24, 2.02, -2.22))
	# 蛇形躯干：八节，沿一条波浪线排开
	for i in range(8):
		var k := float(i) / 7.0
		var r := 0.52 - k * 0.26
		var z := -1.20 + float(i) * 0.56
		var y := 1.82 + sin(float(i) * 0.72) * 0.34 - k * 0.30
		var s := _sph(root, mats[MB] if (i % 2 == 0) else mats[ML], r,
				Vector3(0.0, y, z), Vector3(1.0, 1.0, 1.05))
		segs.append(s)
		# 背上的发光飘带
		_box(root, mats[MG], Vector3(0.07, 0.44, 0.30), Vector3(0.0, y + r + 0.24, z),
				Vector3(0.28, 0.0, 0.0))
	# 侧鳍（没有腿，靠这个维持"龙"的剪影）
	for sx in [0.62, -0.62]:
		for i in range(3):
			var z := -0.60 + float(i) * 0.90
			var fin := _box(root, mats[MG], Vector3(0.66, 0.06, 0.34),
					Vector3(sx, 1.62 - float(i) * 0.10, z), Vector3(0.0, 0.0, sx * -0.34))
			wings.append(fin)


# ═══════════════════════════════════════════════
# T10 宇宙龙 —— 三头、光环、悬浮
# ═══════════════════════════════════════════════
static func _cosmic(root: Node3D, mats: Array[StandardMaterial3D],
		segs: Array, wings: Array, out: Dictionary) -> void:
	# 庞大的躯干
	_box(root, mats[MB], Vector3(1.52, 1.66, 2.06), Vector3(0.0, 2.06, 0.14))
	_box(root, mats[MG], Vector3(1.20, 1.10, 1.50), Vector3(0.0, 2.02, 0.06))
	_box(root, mats[ML], Vector3(1.24, 0.86, 1.62), Vector3(0.0, 1.56, 0.06))
	# 三条颈 + 三个头：中央大，两侧小
	_neck_head(root, mats, 0.0, 3.28, -1.12, 1.00)
	_neck_head(root, mats, 0.86, 2.86, -0.72, 0.68)
	_neck_head(root, mats, -0.86, 2.86, -0.72, 0.68)
	# 光环：单独带出去，让它自己慢慢转，别跟着体节一起蠕动
	out["halo"] = _torus(root, mats[MG], 1.30, 1.48, Vector3(0.0, 2.62, 0.10))
	# 能量翼：两侧各三片，向外张开
	for sx in [1.0, -1.0]:
		for i in range(3):
			var z := -0.30 + float(i) * 0.62
			var w := _box(root, mats[MG], Vector3(1.30, 0.08, 0.44),
					Vector3(sx * 1.42, 2.30 - float(i) * 0.22, z),
					Vector3(0.0, 0.0, sx * (0.42 - float(i) * 0.16)))
			wings.append(w)
	# 尾
	_box(root, mats[MB], Vector3(0.74, 0.68, 0.96), Vector3(0.0, 1.94, 1.62))
	_box(root, mats[MB], Vector3(0.48, 0.44, 0.86), Vector3(0.0, 1.82, 2.46))
	_box(root, mats[MG], Vector3(0.26, 0.24, 0.74), Vector3(0.0, 1.74, 3.16))


## 一条颈 + 一个头（宇宙龙用三次）
static func _neck_head(root: Node3D, mats: Array[StandardMaterial3D],
		ox: float, oy: float, oz: float, s: float) -> void:
	var y := oy
	var z := oz
	_box(root, mats[MB], Vector3(0.44 * s, 0.44 * s, 0.56 * s), Vector3(ox, y, z), Vector3(0.40, 0.0, 0.0))
	_box(root, mats[MB], Vector3(0.40 * s, 0.40 * s, 0.52 * s), Vector3(ox, y + 0.42 * s, z - 0.46 * s), Vector3(0.26, 0.0, 0.0))
	# 头
	var hy := y + 0.62 * s
	var hz := z - 0.96 * s
	_box(root, mats[MB], Vector3(0.56 * s, 0.50 * s, 0.92 * s), Vector3(ox, hy, hz))
	_box(root, mats[ML], Vector3(0.36 * s, 0.28 * s, 0.36 * s), Vector3(ox, hy - 0.10 * s, hz - 0.58 * s))
	# 头冠的角
	for sx in [0.26, -0.26]:
		_cone(root, mats[MG], 0.08 * s, 0.56 * s, Vector3(ox + sx * s, hy + 0.42 * s, hz + 0.10 * s),
				Vector3(0.36, 0.0, sx * -0.30), 0.02)
	_sph(root, mats[MG], 0.10 * s, Vector3(ox + 0.22 * s, hy + 0.10 * s, hz - 0.36 * s))
	_sph(root, mats[MG], 0.10 * s, Vector3(ox - 0.22 * s, hy + 0.10 * s, hz - 0.36 * s))
