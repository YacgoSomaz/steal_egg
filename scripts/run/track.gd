extends Node3D
## 无限跑道：按 chunk 生成，走到哪生成到哪，走远的回收
##
## 难度不靠数值硬堆，靠「距离 → tier」这一条映射：
## 走得越远，睡在那儿的怪越高级、越快、越值钱。剩下的交给玩家自己贪。

const CreatureDB := preload("res://scripts/data/creature_db.gd")
const CREATURE := preload("res://scenes/run/creature.tscn")
const EGG := preload("res://scenes/run/egg.tscn")

const CHUNK_LEN := 100.0          # T1 的基准长度，往后按 world_scale 拉长
const HALF_W := 13.0              # T1 的基准半宽，同上
## 起点这么近不放怪，给玩家喘口气。
## 原来写 40，加上下面那条 `run_dist > SAFE_DIST * 0.5` 的守卫，
## 第 0 段（run_dist=0）一只怪都不放，第一只怪落在第 1 段里 ——
## 也就是 140 米开外，玩家要空跑十几秒才有事可做。现在压到 14。
const SAFE_DIST := 14.0
const NESTS_PER_CHUNK := 2
const DASH_STEP := 5.0            # 地面横向条纹间距——**不**随世界尺度缩放

## 跑道一次生成到底，全程常驻，一块都不回收。
## 之前边跑边回收，玩家一折返路就没了。既然单局长度封顶 4000，全留着也才 20 来段。
var _chunks: Array = []
var _head_z := 0.0
var _done := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20260912


func update(_player_z: float) -> void:
	if _done:
		return
	while -_head_z < CreatureDB.MAX_RUN_DIST:
		_build_next()
	_build_end_wall(_head_z)
	_done = true


func _build_next() -> void:
	var idx := _chunks.size()
	var z_start := _head_z
	var run_dist := maxf(0.0, -z_start)
	var tier := CreatureDB.tier_at(run_dist, GameState.start_tier)
	var k := CreatureDB.world_scale(tier)
	var z_end := z_start - CHUNK_LEN * k
	if -z_end > CreatureDB.MAX_RUN_DIST:
		z_end = -CreatureDB.MAX_RUN_DIST
	var root := Node3D.new()
	root.name = "Chunk_%d" % idx
	add_child(root)

	var td: Dictionary = CreatureDB.tier_data(tier)
	_build_ground(root, z_start, z_end, k, td)
	_build_dashes(root, z_start, z_end, HALF_W * k)
	_build_rails(root, z_start, z_end, k)
	# 巢数按 chunk 长度等比放大，否则高阶区一段路又长又空。
	# 注意：第 0 段也必须放，否则起点附近空一大截。
	var nests := maxi(2, int(round(float(NESTS_PER_CHUNK) * k)))
	for _n in range(nests):
		_spawn_nest(root, z_start, z_end, tier, k)
	# 第一段额外钉一只在起点眼皮底下：随机分布下最近的那只可能落在
	# 四五十米开外，玩家开局还是要空跑一段。这一只保证两三秒内就有事做。
	if idx == 0:
		_spawn_nest(root, z_start, z_end, tier, k, -(SAFE_DIST + 4.0))

	_chunks.append({"node": root, "z_start": z_start, "z_end": z_end})
	_head_z = z_end


## 地面横向条纹：**速度感的主要来源**。
## 间距固定不缩放，所以速度涨 10 倍，条纹掠过频率就真的快 10 倍——
## 之前把世界、相机、模型一起放大，等于把速度感抵消掉了，这是那次改动的教训。
func _build_dashes(root: Node3D, z0: float, z1: float, half_w: float) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := half_w * 0.88
	var thick := 0.45
	var y := 0.03
	var z := z0 - DASH_STEP
	while z > z1:
		im.surface_add_vertex(Vector3(-w, y, z))
		im.surface_add_vertex(Vector3(w, y, z))
		im.surface_add_vertex(Vector3(w, y, z - thick))
		im.surface_add_vertex(Vector3(-w, y, z))
		im.surface_add_vertex(Vector3(w, y, z - thick))
		im.surface_add_vertex(Vector3(-w, y, z - thick))
		z -= DASH_STEP
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.16)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	root.add_child(mi)


## 尽头：一堵挡路的墙，明确告诉玩家"到头了，该往回跑"
func _build_end_wall(z: float) -> void:
	var td: Dictionary = CreatureDB.tier_data(CreatureDB.MAX_TIER)
	var k := CreatureDB.world_scale(CreatureDB.MAX_TIER)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(HALF_W * k * 2.2, 30.0 * k, 6.0 * k)
	wall.mesh = bm
	wall.position = Vector3(0.0, 15.0 * k, z - 3.0 * k)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(td.get("color", Color.WHITE)).darkened(0.55)
	wall.material_override = m
	add_child(wall)

	var tag := Label3D.new()
	tag.text = "尽头 — 折返"
	tag.font_size = 64
	tag.position = Vector3(0.0, 34.0 * k, z)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(tag)


func _build_ground(root: Node3D, z0: float, z1: float, k: float, td: Dictionary) -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF_W * 2.0 * k, absf(z1 - z0))
	g.mesh = pm
	g.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	g.position = Vector3(0.0, 0.0, (z0 + z1) * 0.5)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(td.get("bg", Color(0.5, 0.5, 0.5)))
	g.material_override = gm
	root.add_child(g)


## 两侧的栏杆：给玩家一个明确的"跑道"边界感
func _build_rails(root: Node3D, z0: float, z1: float, k: float) -> void:
	for sx in [-HALF_W * k, HALF_W * k]:
		var rail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5 * k, 0.9 * k, absf(z1 - z0))
		rail.mesh = bm
		rail.position = Vector3(sx, 0.45 * k, (z0 + z1) * 0.5)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.30, 0.26, 0.24)
		rail.material_override = m
		root.add_child(rail)


## z_forced < 0 时用它当坐标，否则在段落内随机取
func _spawn_nest(root: Node3D, z0: float, z1: float, tier: int, k: float,
		z_forced: float = 0.0) -> void:
	var span := absf(z1 - z0)
	var z := z_forced if z_forced < 0.0 else z0 - _rng.randf_range(span * 0.12, span * 0.88)
	if -z < SAFE_DIST:
		# 太贴起点了：往外挪几米，而不是整只跳过。
		# 跳过的话，运气不好时第一段会一只不剩，又回到"起点空一片"的老问题。
		z = -(SAFE_DIST + _rng.randf_range(0.0, 8.0))
	var x := _rng.randf_range(-10.0, 10.0) * k

	# 巢里的怪可能比本阶高一点点，也可能低一点点 —— 让每段路都有惊喜
	var ct: int = clampi(tier + _rng.randi_range(-1, 1), 1, 10)
	var cd: Dictionary = CreatureDB.tier_data(ct)

	var c: Node3D = CREATURE.instantiate() as Node3D
	root.add_child(c)
	c.position = Vector3(x, 0.0, z)
	c.call("setup", ct)
	c.call("set_home", Vector3(x, 0.0, z))
	c.rotation.y = _rng.randf_range(-PI, PI)

	var e: Node3D = EGG.instantiate() as Node3D
	root.add_child(e)
	var ex := clampf(x + _rng.randf_range(-1.8, 1.8) * k, -11.0 * k, 11.0 * k)
	e.position = Vector3(ex, 0.0, z - 2.4 * k)

	# 品质按**这颗蛋离起点多远**抽：跑得越深，越容易出闪光/变异。
	# 传的是 z 而不是 tier —— tier 是阶位（每 2~3 段才跳一阶），
	# 而玩家感知的"我跑多深了"是连续的距离。用距离曲线更平滑，
	# 而且"再往前一点就更容易出好蛋"这件事，玩家能一直感觉到。
	var q: Dictionary = CreatureDB.roll_quality(_rng, maxf(0.0, -z))
	var income := float(cd.get("income", 1.0))
	e.call("setup", {
		"name": "%s蛋" % str(cd.get("name", "?")),
		"tier": ct,
		"income": income,
		"value": CreatureDB.sell_value(income) * float(q.get("mult", 1.0)),
		"quality_name": str(q.get("name", "普通")),
		"quality_mult": float(q.get("mult", 1.0)),
		"color": Color(cd.get("color", Color.WHITE)).lightened(0.28),
	}, c)
