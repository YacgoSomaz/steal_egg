extends RefCounted
## 怪物 / 生态阶数据表
##
## 跑道是无限的：走得越远 tier 越高，怪越快、越值钱、醒得也越快。
## 玩家基础速度 9.0，速度属性每级 +5%（Lv20 时 ×2.0 = 18.0）。
## 所以 T5(10.2) 大约要 Lv3 才跑得过，T10(14.5) 要 Lv13 —— 这就是"偷更高级的蛋"的门槛。

## 速度 / 体型 / 产出全部**等比**递增，不是等差。
## 速度 ×1.5 一阶（5 → 192，跨度 38 倍），体型 ×1.21，产出 ×2.65。
## 等差表的毛病是：T1 和 T2 只差 1.5，玩家根本感觉不到，升两级就通吃——这就是「不够膨胀」。
const TIERS: Array = [
	{"tier": 1,  "name": "草鸡",     "speed": 6.0,  "income": 0.4,   "wake": 1.60, "scale": 0.80, "color": Color(0.86, 0.78, 0.52), "bg": Color(0.55, 0.65, 0.40)},
	{"tier": 2,  "name": "林蜥",     "speed": 7.8,  "income": 1.2,   "wake": 1.35, "scale": 1.05, "color": Color(0.45, 0.66, 0.40), "bg": Color(0.30, 0.48, 0.32)},
	{"tier": 3,  "name": "岩龟",     "speed": 10.1, "income": 3.4,   "wake": 1.15, "scale": 1.35, "color": Color(0.60, 0.55, 0.47), "bg": Color(0.48, 0.46, 0.43)},
	{"tier": 4,  "name": "火蜥",     "speed": 13.2, "income": 9.0,   "wake": 0.95, "scale": 1.70, "color": Color(0.85, 0.38, 0.22), "bg": Color(0.35, 0.18, 0.14)},
	{"tier": 5,  "name": "冰熊",     "speed": 17.1, "income": 24.0,  "wake": 0.80, "scale": 2.10, "color": Color(0.80, 0.88, 0.95), "bg": Color(0.85, 0.88, 0.92)},
	{"tier": 6,  "name": "深海鱼龙", "speed": 22.3, "income": 62.0,  "wake": 0.68, "scale": 2.55, "color": Color(0.22, 0.40, 0.72), "bg": Color(0.10, 0.20, 0.38)},
	{"tier": 7,  "name": "穴居魔虫", "speed": 28.9, "income": 160.0, "wake": 0.56, "scale": 3.05, "color": Color(0.42, 0.25, 0.55), "bg": Color(0.18, 0.12, 0.25)},
	{"tier": 8,  "name": "高山飞龙", "speed": 37.6, "income": 420.0, "wake": 0.46, "scale": 3.60, "color": Color(0.92, 0.70, 0.25), "bg": Color(0.55, 0.45, 0.28)},
	{"tier": 9,  "name": "云间星龙", "speed": 48.9, "income": 1100.0,"wake": 0.40, "scale": 4.10, "color": Color(0.65, 0.90, 0.95), "bg": Color(0.88, 0.92, 0.98)},
	{"tier": 10, "name": "宇宙龙",   "speed": 63.5, "income": 2900.0,"wake": 0.35, "scale": 4.60, "color": Color(0.34, 0.20, 0.60), "bg": Color(0.12, 0.08, 0.22)},
]

## 单局跑道长度。跑到头就是尽头（有一堵墙挡着），必须折返。
## 定死上限有两个理由：一是回程距离可控，二是 chunk 可以全部常驻不回收——
## 之前"往回走跑道消失"就是因为边跑边回收，回头时路已经没了。
const MAX_RUN_DIST := 4000.0

## 本局内「再跑多远升一阶」的档位（相对起点，不是绝对距离）。
## 起点本身由玩家速度决定，所以低阶内容会被跳过——没人想再刷一遍草鸡。
const RUN_TIER_GAPS: Array = [250.0, 600.0, 1200.0, 2200.0, 3800.0, 6300.0, 10000.0, 16000.0]

## 品质：影响养出来之后的产钱效率，也影响卖价
const QUALITIES: Array = [
	{"name": "普通", "mult": 1.0, "cum": 0.70},
	{"name": "优良", "mult": 1.4, "cum": 0.90},
	{"name": "闪光", "mult": 1.9, "cum": 0.98},
	{"name": "变异", "mult": 2.6, "cum": 1.00},
]

const MAX_TIER: int = 10

## 世界尺度：速度涨 10 倍，跑道和 chunk 就得跟着变宽变长，
## 否则高阶区角色一秒穿过好几条街，画面直接失控。
## T1 ×1.0（半宽 13）→ T10 ×3.25（半宽 42）
const WORLD_SCALE_PER_TIER := 0.25

static func world_scale(tier: int) -> float:
	return 1.0 + float(clampi(tier, 1, MAX_TIER) - 1) * WORLD_SCALE_PER_TIER


## 相机随速度拉远——只做「够用」的补偿（封顶 3.5 倍）。
## 拉太远会把速度感一起抵消掉：那是上一版最失败的地方。
static func camera_zoom(speed: float) -> float:
	return clampf(1.0 + speed / 25.0, 1.0, 3.5)


## 角色模型跟着放大一点点，否则拉远后人就变成一个点。系数压到 0.15，不能再高。
static func model_scale(speed: float) -> float:
	return 1.0 + (camera_zoom(speed) - 1.0) * 0.15


## 起始阶位：由玩家速度决定，等于「你跑得过的那一阶」。
## 速度上去了，下次出击直接从那一阶开门，草鸡那一段自动略过。
static func start_tier_for(player_speed: float) -> int:
	var t := 1
	for i in range(1, MAX_TIER + 1):
		if player_speed >= float(TIERS[i - 1]["speed"]) * 1.05:
			t = i
		else:
			break
	return t


## 本局距离 → 阶位（相对起点）
static func tier_at(run_distance: float, start_tier: int) -> int:
	var bump := 0
	for g in RUN_TIER_GAPS:
		if run_distance >= float(g):
			bump += 1
	return clampi(start_tier + bump, 1, MAX_TIER)


## 下一阶还有多远——HUD 上告诉玩家「再跑 XXX m 就换一阶」
static func distance_to_next_tier(run_distance: float, start_tier: int) -> float:
	var t := tier_at(run_distance, start_tier)
	if t >= MAX_TIER:
		return -1.0
	# gaps 数组里第 (t - start_tier) 项就是下一阶的门槛
	var idx := t - start_tier
	if idx < 0 or idx >= RUN_TIER_GAPS.size():
		return -1.0
	return float(RUN_TIER_GAPS[idx]) - run_distance


static func tier_data(tier: int) -> Dictionary:
	return TIERS[clampi(tier, 1, MAX_TIER) - 1]


static func roll_quality(rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf()
	for q in QUALITIES:
		if r <= float(q["cum"]):
			return q
	return QUALITIES[0]


## 卖价 = 每秒产出 × 25。养着是细水长流，卖掉是立刻套现
static func sell_value(income: float) -> float:
	return income * 25.0
