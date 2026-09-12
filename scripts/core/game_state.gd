extends Node
## 全局运行时状态
##
## 三个数值咬成闭环：
##   跑得远 → 怪越高级越值钱 → 养着产钱 → 钱升速度/隐蔽 → 跑得更远
## 而「被抓 → 永久降速」是这套循环唯一的刹车，也是恐惧的来源。

const CreatureDB := preload("res://scripts/data/creature_db.gd")

const BASE_SPEED := 9.0

## 速度有四个来源、三种算法，不再是一条直线：
##   1. 锻炼（乘算）每级 ×1.09 —— 主成长线，越后期绝对收益越大
##   2. 跑鞋（加算）每级 +2.5 基础速度 —— 前期救命，后期被锻炼倍率放大
##   3. 装备（特殊）披风拖长苏醒 / 喷气给起步爆发
##   4. 被抓（乘算）每次 ×0.97 —— 唯一的负面来源
## 实际速度 = (9.0 + 跑鞋×2.5) × 1.09^锻炼 × 0.97^被抓 × 起步喷气
const TRAIN_GROWTH := 1.09
const MAX_LEVEL := 30

const TRAIN_COST_BASE := 40.0
const TRAIN_COST_GROWTH := 1.62      # 跟怪物产出（×2.65/阶）对齐，不然后期钱多到没处花

const SHOE_BONUS := 2.5
const SHOE_COST_BASE := 80.0
const SHOE_COST_GROWTH := 1.70
const MAX_SHOE := 20

const MAX_GEAR := 5
const GEAR_COST_BASE := 200.0
const GEAR_COST_GROWTH := 2.20
const CLOAK_PER_LEVEL := 0.15        # 每级 +15% 苏醒延迟
const JET_PER_LEVEL := 0.25          # 每级 +25% 起步速度
const JET_DURATION := 2.5            # 起步爆发持续秒数

const PENALTY_GROWTH := 0.97
const MAX_CATCH_STACK := 20          # 0.97^20 ≈ 0.54，封底，再倒霉也有 54% 速度
const HEAL_CATCHES := 3              # 治疗一次抹掉 3 次被抓记录

## 数值虚假化：内部 9~90，对外显示成 32~324 km/h。
## 数字大 3.6 倍、单位还是最熟的那个，膨胀感立刻出来了，
## 而物理层一个字都不用改——这就是「虚假化」最省事的一招。
const DISPLAY_SPEED_SCALE := 3.6

const GRAB_TIME := 1.2               # 偷蛋读条固定，快慢交给隐蔽属性去管

## 隐蔽 = 偷完蛋之后，怪物要多久才醒。这是你唯一的逃跑窗口，也是这条属性的全部意义
const WAKE_DELAY_PER_LEVEL := 0.09

var speed_level := 0     # 锻炼
var stealth_level := 0
var shoe_level := 0
var gear_cloak := 0
var gear_jet := 0
var catch_count := 0
var coins := 0.0
var run_time := 0.0      # 本局已跑秒数，喷气起步要用
var best_distance := 0.0
var total_eggs := 0
var total_caught := 0

var carried: Array = []    # 这一趟背在身上的
var stored: Array = []     # 带回农场、还没决定养还是卖
var farm: Array = []       # 正在产钱的 {name,tier,income,quality_name,quality_mult}
var start_tier := 1        # 下一趟从哪一阶开门——由速度决定，草鸡那一段自动跳过


## 出击前调用。速度越快，门开得越深：这是「跑得快 → 见得更奇 → 跑得更快」螺旋的入口
func refresh_start_tier() -> void:
	start_tier = CreatureDB.start_tier_for(get_run_speed())


# ── 派生数值 ───────────────────────────────────
func get_level_multiplier() -> float:
	return pow(TRAIN_GROWTH, float(speed_level))


func get_penalty_multiplier() -> float:
	return pow(PENALTY_GROWTH, float(mini(catch_count, MAX_CATCH_STACK)))


## 起步喷气：只在开局前几秒生效，让你一出发就能拉开距离
func get_jet_multiplier() -> float:
	if gear_jet <= 0 or run_time > JET_DURATION:
		return 1.0
	return 1.0 + JET_PER_LEVEL * float(gear_jet)


func get_run_speed() -> float:
	return get_clean_speed() * get_penalty_multiplier() * get_jet_multiplier()


## 不带惩罚时能跑多快——UI 上用来展示"你现在亏了多少"
func get_clean_speed() -> float:
	return (BASE_SPEED + SHOE_BONUS * float(shoe_level)) * get_level_multiplier()


## 对外显示用的速度（km/h）。内部数值一个字没动，只是把它演大。
func get_display_speed() -> float:
	return get_run_speed() * DISPLAY_SPEED_SCALE


## 速度称号：数字只是数字，跨过一道坎得有个说法，玩家才记得住自己变快了
static func speed_title(kmh: float) -> String:
	if kmh < 40.0:
		return "步行"
	if kmh < 80.0:
		return "慢跑"
	if kmh < 150.0:
		return "狂奔"
	if kmh < 240.0:
		return "疾驰"
	if kmh < 340.0:
		return "音速"
	if kmh < 500.0:
		return "超音速"
	return "无视物理"


func get_grab_time() -> float:
	return GRAB_TIME


## 隐蔽的唯一职责：把怪物从「蛋没了」到「站起来追」之间的延迟拉长。
## 满级 Lv20 是 ×2.8，T10 的 0.35s 也能拖到近 1 秒——够你转身跑两步了
func get_wake_delay(tier_wake: float) -> float:
	var cloak := 1.0 + CLOAK_PER_LEVEL * float(gear_cloak)
	return tier_wake * (1.0 + WAKE_DELAY_PER_LEVEL * float(stealth_level)) * cloak


func get_income_per_sec() -> float:
	var s := 0.0
	for c in farm:
		s += float(c.get("income", 0.0)) * float(c.get("quality_mult", 1.0))
	return s


# ── 成本 ───────────────────────────────────────
func get_speed_cost() -> float:
	return TRAIN_COST_BASE * pow(TRAIN_COST_GROWTH, float(speed_level))


func get_stealth_cost() -> float:
	return TRAIN_COST_BASE * pow(TRAIN_COST_GROWTH, float(stealth_level))


func get_shoe_cost() -> float:
	return SHOE_COST_BASE * pow(SHOE_COST_GROWTH, float(shoe_level))


func get_gear_cost(which: String) -> float:
	var lv := gear_cloak if which == "cloak" else gear_jet
	return GEAR_COST_BASE * pow(GEAR_COST_GROWTH, float(lv))


# ── 升级 ───────────────────────────────────────
func upgrade_speed() -> bool:
	if speed_level >= MAX_LEVEL or coins < get_speed_cost():
		return false
	coins -= get_speed_cost()
	speed_level += 1
	GameEvents.coins_changed.emit(coins)
	return true


func upgrade_stealth() -> bool:
	if stealth_level >= MAX_LEVEL or coins < get_stealth_cost():
		return false
	coins -= get_stealth_cost()
	stealth_level += 1
	GameEvents.coins_changed.emit(coins)
	return true


func upgrade_shoe() -> bool:
	if shoe_level >= MAX_SHOE or coins < get_shoe_cost():
		return false
	coins -= get_shoe_cost()
	shoe_level += 1
	GameEvents.coins_changed.emit(coins)
	return true


func upgrade_gear(which: String) -> bool:
	var lv: int = gear_cloak if which == "cloak" else gear_jet
	if lv >= MAX_GEAR or coins < get_gear_cost(which):
		return false
	coins -= get_gear_cost(which)
	if which == "cloak":
		gear_cloak += 1
	else:
		gear_jet += 1
	GameEvents.coins_changed.emit(coins)
	return true


# ── 永久降速与治疗 ─────────────────────────────
## 「永久」的含义是：不会随时间自愈，必须花钱修。不是无底洞。
func apply_penalty() -> void:
	catch_count += 1
	total_caught += 1
	GameEvents.penalty_changed.emit(get_penalty_multiplier())


func get_heal_cost() -> float:
	return 150.0 * pow(1.25, float(catch_count))


func heal_penalty() -> bool:
	if catch_count <= 0 or coins < get_heal_cost():
		return false
	coins -= get_heal_cost()
	catch_count = maxi(0, catch_count - HEAL_CATCHES)
	GameEvents.penalty_changed.emit(get_penalty_multiplier())
	GameEvents.coins_changed.emit(coins)
	return true


# ── 蛋 ─────────────────────────────────────────
func add_carried(data: Dictionary) -> void:
	carried.append(data)
	total_eggs += 1


## 被追上：抢走身上最贵的那颗。贪心越深，这一口咬得越疼
func lose_best_egg() -> Dictionary:
	if carried.is_empty():
		return {}
	var idx := 0
	var best := -1.0
	for i in range(carried.size()):
		var v := float(carried[i].get("value", 0.0))
		if v > best:
			best = v
			idx = i
	var lost: Dictionary = carried[idx]
	carried.remove_at(idx)
	return lost


func store_carried() -> int:
	var n := carried.size()
	for e in carried:
		stored.append(e)
	carried.clear()
	return n


func sell_stored(index: int) -> bool:
	if index < 0 or index >= stored.size():
		return false
	var e: Dictionary = stored[index]
	coins += float(e.get("value", 0.0))
	stored.remove_at(index)
	GameEvents.coins_changed.emit(coins)
	return true


## 养成：蛋进农场开始产钱
func raise_stored(index: int) -> bool:
	if index < 0 or index >= stored.size():
		return false
	var e: Dictionary = stored[index]
	farm.append({
		"name": str(e.get("name", "?")),
		"tier": int(e.get("tier", 1)),
		"income": float(e.get("income", 0.0)),
		"quality_name": str(e.get("quality_name", "普通")),
		"quality_mult": float(e.get("quality_mult", 1.0)),
	})
	stored.remove_at(index)
	return true


func sell_all_stored() -> int:
	var n := 0
	while not stored.is_empty():
		if sell_stored(0):
			n += 1
		else:
			break
	return n


# ── 经济 ───────────────────────────────────────
func tick_income(delta: float) -> void:
	if farm.is_empty():
		return
	coins += get_income_per_sec() * delta
	GameEvents.coins_changed.emit(coins)


func reset_run() -> void:
	carried.clear()
	run_time = 0.0
