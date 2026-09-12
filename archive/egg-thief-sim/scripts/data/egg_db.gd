extends RefCounted
## 品种与生态阶数据表（docs/03-进阶与兑换体系.md §1）
## 10 个生态阶 × 40 个品种 × 4 档品质 = 160 图鉴条目
## 用法（不用 class_name，避免命令行模式下全局类未注册）：
##   const EggDB := preload("res://scripts/data/egg_db.gd")
##   var d: Dictionary = EggDB.roll_egg(3)

# ── 生态阶 ─────────────────────────────────────
## unlock_cost: 解锁该阶所需基因点
## stealth_req / speed_req: 属性门槛，防止纯刷低级图跳阶
## guard_speed = 守卫追击速度。巡逻速度另按 0.7 折算。
## 调参依据（v0.4）：玩家基础跑 180，负重后 ——
##   0 颗 180 ｜ 1 颗 171 ｜ 2 颗 153 ｜ 3 颗 126 ｜ 4 颗 99
## 让「带几颗能跑掉」成为每阶的核心决策：
##   T1  (115)：速度 Lv1 带 3 颗(126) 刚好跑得掉 —— 新手关给足甜头
##   T5  (148)：带 2 颗(153) 勉强跑掉，3 颗(126) 跑不掉
##   T10 (190)：需速度 Lv14 才能带 3 颗跑掉，Lv11 只能带 2 颗
## 旧值 70-126 严重偏低（玩家是守卫 2.57 倍），导致追击毫无威胁，已重算。
const TIERS: Array = [
	{"tier": 1, "name": "农场", "unlock_cost": 0, "stealth_req": 1, "speed_req": 1, "guard_speed": 115.0},
	{"tier": 2, "name": "湿地", "unlock_cost": 3, "stealth_req": 1, "speed_req": 1, "guard_speed": 123.0},
	{"tier": 3, "name": "崖壁", "unlock_cost": 12, "stealth_req": 2, "speed_req": 1, "guard_speed": 132.0},
	{"tier": 4, "name": "火山", "unlock_cost": 35, "stealth_req": 3, "speed_req": 1, "guard_speed": 140.0},
	{"tier": 5, "name": "极地", "unlock_cost": 80, "stealth_req": 4, "speed_req": 3, "guard_speed": 148.0},
	{"tier": 6, "name": "深海", "unlock_cost": 160, "stealth_req": 6, "speed_req": 4, "guard_speed": 157.0},
	{"tier": 7, "name": "地下", "unlock_cost": 300, "stealth_req": 7, "speed_req": 6, "guard_speed": 165.0},
	{"tier": 8, "name": "高山龙巢", "unlock_cost": 500, "stealth_req": 9, "speed_req": 7, "guard_speed": 173.0},
	{"tier": 9, "name": "云端", "unlock_cost": 800, "stealth_req": 11, "speed_req": 9, "guard_speed": 182.0},
	{"tier": 10, "name": "星球环", "unlock_cost": 1200, "stealth_req": 13, "speed_req": 11, "guard_speed": 190.0},
]

# ── 品质 ───────────────────────────────────────
## rate 累计区间：普通 0-0.70，优良 0.70-0.90，闪光 0.90-0.98，变异 0.98-1.0
const QUALITIES: Array = [
	{"name": "普通", "mult": 1.0, "cum": 0.70, "value_mult": 1.0},
	{"name": "优良", "mult": 1.15, "cum": 0.90, "value_mult": 1.5},
	{"name": "闪光", "mult": 1.35, "cum": 0.98, "value_mult": 2.5},
	{"name": "变异", "mult": 1.60, "cum": 1.00, "value_mult": 5.0},
]

## 伙伴被动：按生态阶给，遵循「每阶孵出的伙伴克制下一阶的威胁」（docs/03 §5）
## T2 免疫毒气 → T3 免疫强风 → T4 免疫高温 → T5 抗暴风雪 → T6 氧气减半
## → T7 黑暗视觉 → T8 威压守卫 → T9 负重减半 → T10 宇宙龙全面免疫
## 携带伙伴时，这些被动自动生效 —— 这是「养成反哺偷窃」真正的兑现点
const PARTNER_PASSIVES: Dictionary = {
	1: {"type": "none", "desc": "无（但能下蛋换基因点）"},
	2: {"type": "toxic_immune", "desc": "免疫毒气：湿地不再持续涨警戒"},
	3: {"type": "wind_immune", "desc": "免疫强风：崖壁不会被吹偏"},
	4: {"type": "heat_immune", "desc": "免疫高温：火山不再持续涨警戒"},
	5: {"type": "blizzard_vision", "desc": "暴风雪中视野不减"},
	6: {"type": "oxygen_half", "desc": "氧气消耗减半"},
	7: {"type": "dark_vision", "desc": "黑暗中看得见（画面不再全黑）"},
	8: {"type": "intimidate", "desc": "威压：守卫追击速度 −20%"},
	9: {"type": "half_load", "desc": "负重惩罚减半：能多背一颗"},
	10: {"type": "cosmic", "desc": "宇宙龙：免疫一切环境威胁"},
}


static func partner_passive_of(tier: int) -> Dictionary:
	return PARTNER_PASSIVES.get(tier, PARTNER_PASSIVES[1])


# ── 40 个品种 ──────────────────────────────────
const SPECIES: Array = [
	{"name": "鸡蛋", "tier": 1, "color": Color(0.96, 0.93, 0.82)},
	{"name": "鸭蛋", "tier": 1, "color": Color(0.86, 0.90, 0.84)},
	{"name": "鹅蛋", "tier": 1, "color": Color(0.97, 0.97, 0.94)},
	{"name": "鹌鹑蛋", "tier": 1, "color": Color(0.82, 0.74, 0.58)},
	{"name": "火鸡蛋", "tier": 1, "color": Color(0.90, 0.80, 0.68)},

	{"name": "青蛙卵", "tier": 2, "color": Color(0.55, 0.74, 0.45)},
	{"name": "蜥蜴蛋", "tier": 2, "color": Color(0.68, 0.76, 0.52)},
	{"name": "龟蛋", "tier": 2, "color": Color(0.80, 0.78, 0.62)},
	{"name": "蟒蛇蛋", "tier": 2, "color": Color(0.60, 0.66, 0.44)},

	{"name": "鹰蛋", "tier": 3, "color": Color(0.78, 0.68, 0.52)},
	{"name": "隼蛋", "tier": 3, "color": Color(0.70, 0.60, 0.48)},
	{"name": "秃鹫蛋", "tier": 3, "color": Color(0.72, 0.66, 0.58)},
	{"name": "猫头鹰蛋", "tier": 3, "color": Color(0.84, 0.80, 0.72)},

	{"name": "火蜥蜴蛋", "tier": 4, "color": Color(0.92, 0.42, 0.24)},
	{"name": "熔岩蟹卵", "tier": 4, "color": Color(0.88, 0.30, 0.18)},
	{"name": "蝾螈蛋", "tier": 4, "color": Color(0.94, 0.58, 0.30)},
	{"name": "凤凰蛋", "tier": 4, "color": Color(1.00, 0.72, 0.28)},

	{"name": "企鹅蛋", "tier": 5, "color": Color(0.72, 0.82, 0.90)},
	{"name": "雪鸮蛋", "tier": 5, "color": Color(0.90, 0.94, 0.98)},
	{"name": "冰蠕虫卵", "tier": 5, "color": Color(0.62, 0.84, 0.92)},
	{"name": "霜狼幼崽蛋", "tier": 5, "color": Color(0.78, 0.86, 0.94)},

	{"name": "章鱼卵", "tier": 6, "color": Color(0.42, 0.48, 0.72)},
	{"name": "灯笼鱼卵", "tier": 6, "color": Color(0.48, 0.72, 0.68)},
	{"name": "深海龙蛋", "tier": 6, "color": Color(0.28, 0.36, 0.62)},
	{"name": "巨鲸胎卵", "tier": 6, "color": Color(0.52, 0.58, 0.74)},

	{"name": "蝙蝠卵", "tier": 7, "color": Color(0.42, 0.38, 0.48)},
	{"name": "蜘蛛卵", "tier": 7, "color": Color(0.60, 0.55, 0.62)},
	{"name": "石像鬼蛋", "tier": 7, "color": Color(0.52, 0.52, 0.56)},
	{"name": "地龙蛋", "tier": 7, "color": Color(0.46, 0.40, 0.52)},

	{"name": "幼龙蛋", "tier": 8, "color": Color(0.76, 0.28, 0.26)},
	{"name": "双足飞龙蛋", "tier": 8, "color": Color(0.68, 0.34, 0.22)},
	{"name": "Wyvern 蛋", "tier": 8, "color": Color(0.58, 0.26, 0.30)},
	{"name": "古龙蛋", "tier": 8, "color": Color(0.48, 0.20, 0.24)},

	{"name": "星龙蛋", "tier": 9, "color": Color(0.62, 0.52, 0.92)},
	{"name": "气元素核", "tier": 9, "color": Color(0.78, 0.86, 0.96)},
	{"name": "雷鸟蛋", "tier": 9, "color": Color(0.72, 0.68, 0.98)},
	{"name": "虹羽蛋", "tier": 9, "color": Color(0.80, 0.60, 0.94)},

	{"name": "宇宙龙蛋", "tier": 10, "color": Color(1.00, 0.84, 0.36)},
	{"name": "星核", "tier": 10, "color": Color(0.98, 0.96, 0.80)},
	{"name": "虚空卵", "tier": 10, "color": Color(0.30, 0.26, 0.42)},
]


# ── 查询 ───────────────────────────────────────

static func tier_data(tier: int) -> Dictionary:
	for t in TIERS:
		if int(t.get("tier", 1)) == tier:
			return t
	return TIERS[0]


static func species_of_tier(tier: int) -> Array:
	var out: Array = []
	for s in SPECIES:
		if int(s.get("tier", 1)) == tier:
			out.append(s)
	return out


## 基因点价值 = 3^(tier-1)
static func base_value_of(tier: int) -> int:
	var v := 1
	for _i in range(tier - 1):
		v *= 3
	return v


## 孵化时长（秒）：越高阶越久
static func hatch_time_of(tier: int) -> float:
	return 20.0 + float(tier) * 10.0


## 随机抽一个品质，返回索引
static func roll_quality() -> int:
	var r := randf()
	for i in QUALITIES.size():
		if r < float(QUALITIES[i].get("cum", 1.0)):
			return i
	return 0


## 生成一颗完整的蛋数据
static func roll_egg(tier: int) -> Dictionary:
	var pool := species_of_tier(tier)
	if pool.is_empty():
		pool = species_of_tier(1)
	var sp: Dictionary = pool[randi() % pool.size()]
	var qi := roll_quality()
	var q: Dictionary = QUALITIES[qi]
	return {
		"name": sp.get("name", "蛋"),
		"tier": tier,
		"quality": qi,
		"quality_name": q.get("name", "普通"),
		"value": int(round(float(base_value_of(tier)) * float(q.get("value_mult", 1.0)))),
		"hatch_time": hatch_time_of(tier),
		"color": sp.get("color", Color(1, 1, 1)),
		"quality_mult": q.get("mult", 1.0),
	}
