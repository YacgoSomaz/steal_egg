extends Node3D
## 撤离点后面的农场 + 商店
##
## 之前升级要切到另一个场景（farm.tscn），玩起来是「跑一趟 → 退出 → 买东西 → 再进去」，
## 节奏被切得很碎。现在把店铺直接盖在撤离点后面：扛着蛋跑回来，
## 转身走两步就能升级，还能看见自己养的那些生物在栏里晃。
##
## 布局（z 轴：跑道往 −Z，农场往 +Z）：
##   z = 0      起点 / 撤离线
##   z = 10     六个摊位一字排开
##   z = 46     畜栏，养着的生物在这儿游荡
##   z = 72     围栏尽头

const CreatureDB := preload("res://scripts/data/creature_db.gd")
const CREATURE := preload("res://scenes/run/creature.tscn")

const HALF_W := 26.0
const STATION_Z := 10.0
const PEN_Z := 46.0
const PEN_R := 15.0
const Z_FAR := 74.0
const INTERACT_RANGE := 5.0
const MAX_PEN_CREATURES := 20     # 每只二十来个网格，全摆出来会拖帧

## 摊位：kind 决定按 E 时干什么
const STATIONS: Array = [
	{"kind": "train", "x": -18.0, "name": "锻炼", "color": Color(0.85, 0.45, 0.35)},
	{"kind": "shoe",  "x": -10.5, "name": "跑鞋", "color": Color(0.45, 0.72, 0.90)},
	{"kind": "cloak", "x": -3.0,  "name": "披风", "color": Color(0.55, 0.50, 0.75)},
	{"kind": "jet",   "x": 4.5,   "name": "喷气", "color": Color(0.90, 0.75, 0.35)},
	{"kind": "raise", "x": 12.0,  "name": "入农场", "color": Color(0.45, 0.80, 0.50)},
	{"kind": "sell",  "x": 19.5,  "name": "卖蛋",  "color": Color(0.80, 0.65, 0.30)},
]

var _stations: Array = []          # [{kind,x,z,label}]
var _pen_creatures: Array = []
var _pen_root: Node3D


func build() -> void:
	_ground()
	_fence()
	_build_stations()
	rebuild_farm()


# ── 地面与围栏 ─────────────────────────────────
func _ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF_W * 2.0, Z_FAR)
	g.mesh = pm
	g.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	g.position = Vector3(0.0, 0.01, Z_FAR * 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.46, 0.32)
	g.material_override = m
	add_child(g)

	# 一条深色带子把「跑道」和「农场」在视觉上分开
	var sep := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(HALF_W * 2.0, 0.08, 0.5)
	sep.mesh = sm
	sep.position = Vector3(0.0, 0.04, 0.0)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.85, 0.82, 0.55)
	sep.material_override = smat
	add_child(sep)


func _fence() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.38, 0.24)
	# 两侧
	for sx in [-HALF_W, HALF_W]:
		_post_line(Vector3(sx, 0.0, 0.0), Vector3(sx, 0.0, Z_FAR), mat)
	# 尽头
	_post_line(Vector3(-HALF_W, 0.0, Z_FAR), Vector3(HALF_W, 0.0, Z_FAR), mat)


func _post_line(a: Vector3, b: Vector3, mat: Material) -> void:
	var d := b - a
	var n := maxi(2, int(d.length() / 4.0))
	for i in range(n + 1):
		var p := a + d * (float(i) / float(n))
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 2.2, 0.35)
		post.mesh = bm
		post.position = p + Vector3(0.0, 1.1, 0.0)
		post.material_override = mat
		add_child(post)
	# 横杆
	var rail := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(absf(d.x) + 0.35, 0.22, absf(d.z) + 0.35)
	rail.mesh = rm
	rail.position = (a + b) * 0.5 + Vector3(0.0, 1.5, 0.0)
	rail.material_override = mat
	add_child(rail)


# ── 摊位 ───────────────────────────────────────
func _build_stations() -> void:
	for st in STATIONS:
		var x := float(st.get("x", 0.0))
		var kind := str(st.get("kind", ""))
		var col := Color(st.get("color", Color.WHITE))

		# 台子
		var podium := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.4, 1.5, 3.0)
		podium.mesh = bm
		podium.position = Vector3(x, 0.75, STATION_Z)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = col.darkened(0.25)
		podium.material_override = pmat
		add_child(podium)

		# 台面
		var top := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(4.8, 0.22, 3.4)
		top.mesh = tm
		top.position = Vector3(x, 1.6, STATION_Z)
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = col
		top.material_override = tmat
		add_child(top)

		# 招牌
		var sign := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(3.6, 1.1, 0.18)
		sign.mesh = sm
		sign.position = Vector3(x, 3.4, STATION_Z)
		var smat := StandardMaterial3D.new()
		smat.albedo_color = col.lightened(0.35)
		sign.material_override = smat
		add_child(sign)

		var label := Label3D.new()
		label.font_size = 44
		label.position = Vector3(x, 4.6, STATION_Z)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 12
		label.modulate = Color(1.0, 0.98, 0.90)
		add_child(label)

		_stations.append({
			"kind": kind, "x": x, "z": STATION_Z, "label": label,
			"name": str(st.get("name", kind)),
		})
	refresh()


## 买完之后把牌子上的字刷新一遍
func refresh() -> void:
	for st in _stations:
		var label: Label3D = st.get("label") as Label3D
		if label == null:
			continue
		label.text = _station_text(str(st.get("kind", "")))


func _station_text(kind: String) -> String:
	match kind:
		"train":
			return "锻炼 Lv%d / %d\n×%.2f 速度\n%d 金币" % [
				GameState.speed_level, GameState.MAX_LEVEL,
				GameState.get_level_multiplier(), int(GameState.get_speed_cost())]
		"shoe":
			return "跑鞋 Lv%d / %d\n基础速度 +%.1f\n%d 金币" % [
				GameState.shoe_level, GameState.MAX_SHOE,
				GameState.SHOE_BONUS * float(GameState.shoe_level),
				int(GameState.get_shoe_cost())]
		"cloak":
			return "披风 Lv%d / %d\n苏醒延迟 ×%.2f\n%d 金币" % [
				GameState.gear_cloak, GameState.MAX_GEAR,
				1.0 + GameState.CLOAK_PER_LEVEL * float(GameState.gear_cloak),
				int(GameState.get_gear_cost("cloak"))]
		"jet":
			return "喷气 Lv%d / %d\n开局 %.1fs ×%.2f\n%d 金币" % [
				GameState.gear_jet, GameState.MAX_GEAR, GameState.JET_DURATION,
				1.0 + GameState.JET_PER_LEVEL * float(GameState.gear_jet),
				int(GameState.get_gear_cost("jet"))]
		"raise":
			return "入农场\n仓库 %d 颗 → 开始产钱\n（每秒 +%.1f）" % [
				GameState.stored.size(), GameState.get_income_per_sec()]
		"sell":
			return "卖蛋\n仓库 %d 颗 → 立刻变现\n%d 金币" % [
				GameState.stored.size(), int(_stored_value())]
	return "?"


func _stored_value() -> float:
	var s := 0.0
	for e in GameState.stored:
		s += float(e.get("value", 0.0))
	return s


# ── 交互 ───────────────────────────────────────
## 玩家附近有没有摊位可交互（没有就返回空字典）
func nearest(pos: Vector3) -> Dictionary:
	if pos.z < 0.0:
		return {}                       # 还在跑道上，不提示
	var best: Dictionary = {}
	var bd := INTERACT_RANGE
	for st in _stations:
		var d := Vector2(pos.x - float(st.get("x", 0.0)), pos.z - float(st.get("z", 0.0))).length()
		if d < bd:
			bd = d
			best = st
	return best


## 按 E 时调用。返回一句给玩家的反馈
func interact(st: Dictionary) -> String:
	if st.is_empty():
		return ""
	var kind := str(st.get("kind", ""))
	var msg := ""
	match kind:
		"train":
			if not GameState.upgrade_speed():
				return _fail("锻炼", GameState.speed_level >= GameState.MAX_LEVEL, GameState.get_speed_cost())
			msg = "锻炼到 Lv%d，速度 ×%.2f" % [GameState.speed_level, GameState.get_level_multiplier()]
		"shoe":
			if not GameState.upgrade_shoe():
				return _fail("跑鞋", GameState.shoe_level >= GameState.MAX_SHOE, GameState.get_shoe_cost())
			msg = "换上第 %d 双跑鞋，基础速度 +%.0f" % [
				GameState.shoe_level, GameState.SHOE_BONUS * float(GameState.shoe_level)]
		"cloak":
			if not GameState.upgrade_gear("cloak"):
				return _fail("披风", GameState.gear_cloak >= GameState.MAX_GEAR, GameState.get_gear_cost("cloak"))
			msg = "披风 Lv%d，苏醒延迟 ×%.2f" % [
				GameState.gear_cloak, 1.0 + GameState.CLOAK_PER_LEVEL * float(GameState.gear_cloak)]
		"jet":
			if not GameState.upgrade_gear("jet"):
				return _fail("喷气", GameState.gear_jet >= GameState.MAX_GEAR, GameState.get_gear_cost("jet"))
			msg = "喷气 Lv%d，开局 ×%.2f" % [
				GameState.gear_jet, 1.0 + GameState.JET_PER_LEVEL * float(GameState.gear_jet)]
		"raise":
			var n := 0
			while not GameState.stored.is_empty():
				if GameState.raise_stored(0):
					n += 1
				else:
					break
			if n == 0:
				return "仓库是空的——先去偷几颗蛋回来"
			msg = "%d 只进了农场，现在每秒 +%.1f 金币" % [n, GameState.get_income_per_sec()]
			rebuild_farm()
		"sell":
			var got := _stored_value()
			var n2 := GameState.sell_all_stored()
			if n2 == 0:
				return "仓库是空的——先去偷几颗蛋回来"
			msg = "卖掉 %d 颗，到手 %d 金币" % [n2, int(got)]
	_after_buy(msg)
	return msg


## 失败提示要报**这个摊位**的价格，不能写死锻炼的价——
## 买跑鞋钱不够却提示锻炼的价格，玩家会以为游戏算错了
func _fail(what: String, maxed: bool, cost: float) -> String:
	if maxed:
		return "%s 已经满级了" % what
	return "%s 要 %d 金币，还差 %d" % [what, int(cost), int(maxf(0.0, cost - GameState.coins))]


func _after_buy(msg: String) -> void:
	refresh()
	SaveManager.save()
	GameEvents.coins_changed.emit(GameState.coins)


# ── 畜栏 ───────────────────────────────────────
## 按 GameState.farm 重建栏里的生物
func rebuild_farm() -> void:
	for c in _pen_creatures:
		if is_instance_valid(c):
			c.queue_free()
	_pen_creatures.clear()
	if _pen_root != null and is_instance_valid(_pen_root):
		_pen_root.queue_free()
	_pen_root = Node3D.new()
	add_child(_pen_root)

	var n := mini(GameState.farm.size(), MAX_PEN_CREATURES)
	for i in range(n):
		var e: Dictionary = GameState.farm[i]
		var t := clampi(int(e.get("tier", 1)), 1, CreatureDB.MAX_TIER)
		var c: Node3D = CREATURE.instantiate() as Node3D
		_pen_root.add_child(c)
		var a := float(i) * 2.399963          # 黄金角，摆得均匀又不呆板
		var r := sqrt(float(i) / maxf(1.0, float(n))) * PEN_R
		var p := Vector3(cos(a) * r, 0.0, PEN_Z + sin(a) * r)
		c.position = p
		c.call("setup", t)
		c.call("set_home", p)
		c.call("set_pen", Vector3(0.0, 0.0, PEN_Z), PEN_R)
		_pen_creatures.append(c)


func pen_count() -> int:
	return _pen_creatures.size()
