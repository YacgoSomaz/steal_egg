extends RefCounted
## 巢穴地形生成：按生态阶程序化生成布局
## 用法：const NestDB := preload("res://scripts/data/nest_db.gd")
##
## 设计意图：越高的生态阶，掩体越少、危险地面区越多 —— 难度靠地形自然递增，
## 而不是靠数值硬堆。同样的守卫参数，在 T10 会明显比 T1 难混。

const ROOM := Vector2(1280, 720)
const START := Vector2(90, 620)

## 每个生态阶的环境色（手工指定，保证主题辨识度）
const TIER_BG: Array = [
	Color(0.82, 0.88, 0.72),   # T1  农场   浅黄绿
	Color(0.72, 0.80, 0.66),   # T2  湿地   苔绿
	Color(0.78, 0.74, 0.66),   # T3  崖壁   岩石褐
	Color(0.88, 0.70, 0.58),   # T4  火山   橙红
	Color(0.86, 0.90, 0.95),   # T5  极地   冷白蓝
	Color(0.52, 0.62, 0.76),   # T6  深海   蓝
	Color(0.42, 0.40, 0.46),   # T7  地下   灰
	Color(0.70, 0.66, 0.70),   # T8  高山   紫灰
	Color(0.62, 0.58, 0.82),   # T9  云端   紫
	Color(0.26, 0.24, 0.40),   # T10 星球环 深空紫
]

const DANGER_COLOR := Color(0.55, 0.52, 0.48)
const SAFE_COLOR := Color(0.26, 0.34, 0.24)


static func layout_for(tier: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = tier * 9871 + 13

	# 蛋位随阶位变多（3-6），掩体随阶位变少（6-2）
	var egg_count: int = clampi(3 + tier / 4, 3, 6)
	var cover_count: int = maxi(2, 7 - tier / 2)
	var zone_count: int = clampi(1 + tier / 4, 1, 3)

	var blocked: Array = [START]

	var spots: Array = []
	for _i in egg_count:
		var p := _pick_point(rng, 170.0, blocked)
		spots.append(p)
		blocked.append(p)

	var covers: Array = []
	for _i in cover_count:
		var p := _pick_point(rng, 150.0, blocked)
		covers.append({
			"pos": p,
			"size": Vector2(rng.randi_range(60, 140), rng.randi_range(60, 130)),
		})
		blocked.append(p)

	var zones: Array = []
	for _i in zone_count:
		var p := _pick_point(rng, 120.0, blocked)
		# 阶位越高，危险区占比越大
		var danger := rng.randf() < (0.4 + float(tier) * 0.05)
		zones.append({
			"pos": p,
			"size": Vector2(rng.randi_range(200, 360), rng.randi_range(150, 250)),
			"mult": 2.0 if danger else 0.5,
			"color": DANGER_COLOR if danger else SAFE_COLOR,
		})

	return {
		"tier": tier,
		"bg": bg_of(tier),
		"egg_spots": spots,
		"covers": covers,
		"zones": zones,
	}


static func bg_of(tier: int) -> Color:
	var i: int = clampi(tier - 1, 0, TIER_BG.size() - 1)
	return TIER_BG[i]


## 在房间内随机找一个离所有 blocked 点都足够远的位置
static func _pick_point(rng: RandomNumberGenerator, min_dist: float, blocked: Array) -> Vector2:
	var fallback := Vector2(rng.randi_range(180, 1100), rng.randi_range(140, 570))
	for _attempt in 80:
		var p := Vector2(rng.randi_range(180, 1100), rng.randi_range(140, 570))
		var ok := true
		for b in blocked:
			var bp: Vector2 = b if b is Vector2 else Vector2(b.get("pos", Vector2.ZERO))
			if p.distance_to(bp) < min_dist:
				ok = false
				break
		if ok:
			return p
	return fallback
