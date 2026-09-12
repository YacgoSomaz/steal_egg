extends Node
## 全局运行时状态：属性、警戒值、携带的蛋

const EggDB := preload("res://scripts/data/egg_db.gd")
## 数值公式见 docs/01-核心循环.md §3、docs/03-进阶与兑换体系.md §2

const ALERT_MAX := 100.0

# ── 人物双属性（Lv1-15）─────────────────────────
var stealth_level: int = 1
var speed_level: int = 1

const STEALTH_COEF := 0.045   # 隐匿：感知半径 × (1 - 0.045×(Lv-1))，Lv15 → 0.37
const SPEED_COEF := 0.04      # 速度：移速 × (1 + 0.04×(Lv-1))，Lv15 → 1.56

# ── 运行时状态 ─────────────────────────────────
var alert: float = 0.0
var carried_eggs: Array[Node2D] = []
var total_stolen: int = 0
var was_spotted: bool = false      # 本局是否被发现过（判定"无痕之偷"）
var _alert_max_fired: bool = false

# ── 基地 / 养成（Phase 1）──────────────────────
var gene_points: int = 0                    # 基因点：献祭获得，用于升级与解锁
var stored_eggs: Array[Dictionary] = []     # 带回但还没处理的蛋
var partners: Array[Dictionary] = []        # 已孵化的伙伴
var hatching: Array[Dictionary] = []        # 孵化中的蛋
var selected_partner: String = ""           # 本次出击携带的伙伴

const HATCH_SLOTS := 2                      # 孵化槽数量（可升级）
const MAX_LEVEL := 15

var current_tier: int = 1                   # 本次出击前往的生态阶
var unlocked_tier: int = 1                  # 已解锁的最高生态阶

# ── 环境（由 Environment 节点每帧写入）────────────
var env_wind: Vector2 = Vector2.ZERO        # 强风推力（崖壁）
var env_vision_mult: float = 1.0            # 守卫视野倍率（暴风雪/黑暗）
var env_speed_mult: float = 1.0             # 玩家移速倍率（失重）
var env_oxygen: float = -1.0                # 剩余氧气，<0 表示无限制
var env_name: String = ""                   # 环境名，HUD 显示
var env_intensity: float = 0.0              # 当前强度 0-1，HUD 提示用

# ── 伙伴主动技能 ───────────────────────────────
var skill_active: bool = false
var skill_timer: float = 0.0
var skill_cooldown: float = 0.0

const SKILL_DURATION := 3.0                 # 持续：噪音归零 + 守卫视野减半
const SKILL_COOLDOWN := 25.0

## 属性升级成本（差值递增）—— 见 docs/03 §2
const UPGRADE_COST: Array[int] = [4, 6, 9, 13, 18, 24, 31, 39, 48, 58, 69, 81, 94, 108]

# ── 属性派生值 ─────────────────────────────────

func get_perception_multiplier() -> float:
	return 1.0 - STEALTH_COEF * float(stealth_level - 1)


func get_speed_multiplier() -> float:
	return 1.0 + SPEED_COEF * float(speed_level - 1)


## 负重系数：超线性惩罚，见核心循环 §3
## T9 星龙的 half_load 被动会把「惩罚」本身减半（不是减蛋数）
func get_load_multiplier() -> float:
	var n := carried_eggs.size()
	var m := 1.0
	if n == 1:
		m = 0.95
	elif n == 2:
		m = 0.85
	elif n == 3:
		m = 0.70
	elif n >= 4:
		m = 0.55
	if has_partner_passive("half_load"):
		m = 1.0 - (1.0 - m) * 0.5
	return m


# ── 伙伴被动 ───────────────────────────────────

func get_partner_tier() -> int:
	if selected_partner.is_empty():
		return 0
	for p in partners:
		if str(p.get("name", "")) == selected_partner:
			return int(p.get("tier", 1))
	return 0


func has_partner_passive(type_name: String) -> bool:
	var t := get_partner_tier()
	if t <= 0:
		return false
	var d: Dictionary = EggDB.partner_passive_of(t)
	return str(d.get("type", "")) == type_name


func get_partner_passive_desc() -> String:
	var t := get_partner_tier()
	if t <= 0:
		return ""
	var d: Dictionary = EggDB.partner_passive_of(t)
	return str(d.get("desc", ""))


## 玩家最终移速 = 基础 × 速度属性 × 负重系数
func get_effective_speed(base: float) -> float:
	return base * get_speed_multiplier() * get_load_multiplier() * env_speed_mult


# ── 警戒值 ─────────────────────────────────────

func add_alert(amount: float) -> void:
	alert = clampf(alert + amount, 0.0, ALERT_MAX)
	GameEvents.alert_changed.emit(alert, alert / ALERT_MAX)
	if alert >= ALERT_MAX and not _alert_max_fired:
		_alert_max_fired = true
		GameEvents.alert_maxed.emit()


func reset_alert() -> void:
	alert = 0.0
	_alert_max_fired = false


# ── 携带 ───────────────────────────────────────

func carry_egg(egg: Node2D) -> void:
	carried_eggs.append(egg)
	total_stolen += 1


func drop_all_eggs() -> int:
	var n := carried_eggs.size()
	carried_eggs.clear()
	return n


# ── 基地：蛋的三重去向 ─────────────────────────

## 撤离成功后，把携带的蛋存进基地
func store_carried_eggs() -> void:
	for egg in carried_eggs:
		discover(egg.egg_name, egg.quality_name)
		stored_eggs.append({
			"name": egg.egg_name,
			"tier": egg.tier,
			"value": egg.base_value,
			"hatch_time": egg.hatch_time,
			"quality_name": egg.quality_name,
			"quality_mult": egg.quality_mult,
		})
		egg.queue_free()
	carried_eggs.clear()


## 献祭：蛋 → 基因点
func sacrifice_egg(index: int) -> int:
	if index < 0 or index >= stored_eggs.size():
		return 0
	var data: Dictionary = stored_eggs[index]
	var pts: int = int(data.get("value", 1))
	gene_points += pts
	stored_eggs.remove_at(index)
	return pts


## 孵化：蛋 → 孵化槽
func start_hatch(index: int) -> bool:
	if index < 0 or index >= stored_eggs.size():
		return false
	if hatching.size() >= HATCH_SLOTS:
		return false
	var data: Dictionary = stored_eggs[index]
	hatching.append({
		"name": data.get("name", "蛋"),
		"tier": data.get("tier", 1),
		"quality_name": data.get("quality_name", "普通"),
		"quality_mult": data.get("quality_mult", 1.0),
		"total": float(data.get("hatch_time", 20.0)),
		"remaining": float(data.get("hatch_time", 20.0)),
	})
	stored_eggs.remove_at(index)
	return true


## 推进孵化计时，返回本次新孵出的伙伴名列表
func tick_hatch(delta: float) -> Array[String]:
	var born: Array[String] = []
	for i in range(hatching.size() - 1, -1, -1):
		var h: Dictionary = hatching[i]
		h["remaining"] = float(h["remaining"]) - delta
		if float(h["remaining"]) <= 0.0:
			var nm: String = str(h.get("name", "生物"))
			partners.append({
				"name": nm,
				"tier": int(h.get("tier", 1)),
				"quality_name": h.get("quality_name", "普通"),
				"quality_mult": h.get("quality_mult", 1.0),
			})
			born.append(nm)
			hatching.remove_at(i)
	return born


# ── 属性升级 ───────────────────────────────────

func get_upgrade_cost(current_level: int) -> int:
	if current_level < 1 or current_level >= MAX_LEVEL:
		return -1
	return UPGRADE_COST[current_level - 1]


## 属性等级上限受已解锁生态阶限制（docs/03 §2 的刹车机制）
## 上限 = 4 + 阶位 × 1.2，向下取整。防止刷低级图堆满属性直接跳到终极阶。
func get_max_level() -> int:
	return mini(MAX_LEVEL, 4 + int(float(unlocked_tier) * 1.2))


func upgrade_stealth() -> bool:
	if stealth_level >= get_max_level():
		return false
	var cost := get_upgrade_cost(stealth_level)
	if cost < 0 or gene_points < cost:
		return false
	gene_points -= cost
	stealth_level += 1
	return true


func upgrade_speed() -> bool:
	if speed_level >= get_max_level():
		return false
	var cost := get_upgrade_cost(speed_level)
	if cost < 0 or gene_points < cost:
		return false
	gene_points -= cost
	speed_level += 1
	return true


# ── 生态阶解锁 ─────────────────────────────────

func next_tier_data() -> Dictionary:
	if unlocked_tier >= EggDB.TIERS.size():
		return {}
	return EggDB.tier_data(unlocked_tier + 1)


func can_unlock_next_tier() -> bool:
	var t := next_tier_data()
	if t.is_empty():
		return false
	return (gene_points >= int(t.get("unlock_cost", 0))
		and stealth_level >= int(t.get("stealth_req", 1))
		and speed_level >= int(t.get("speed_req", 1)))


func unlock_next_tier() -> bool:
	if not can_unlock_next_tier():
		return false
	var t := next_tier_data()
	gene_points -= int(t.get("unlock_cost", 0))
	unlocked_tier += 1
	print("[基地] 解锁生态阶 T%d %s" % [unlocked_tier, t.get("name", "")])
	return true


# ── 伙伴被动 ───────────────────────────────────

## 释放伙伴技能：3 秒内噪音归零、守卫视野减半
func try_use_skill() -> bool:
	if selected_partner.is_empty() or skill_active or skill_cooldown > 0.0:
		return false
	skill_active = true
	skill_timer = SKILL_DURATION
	skill_cooldown = SKILL_COOLDOWN
	return true


func tick_skill(delta: float) -> void:
	if skill_timer > 0.0:
		skill_timer -= delta
		if skill_timer <= 0.0:
			skill_active = false
			skill_timer = 0.0
	if skill_cooldown > 0.0:
		skill_cooldown = maxf(0.0, skill_cooldown - delta)


func get_skill_vision_multiplier() -> float:
	return 0.5 if skill_active else 1.0


## 携带伙伴时的噪音修正：阶位 -5%/级，品质再除一次
## 变异伙伴（×1.6）比普通伙伴安静得多 —— 品质终于影响实战了
func get_partner_noise_multiplier() -> float:
	if selected_partner.is_empty():
		return 1.0
	for p in partners:
		if str(p.get("name", "")) == selected_partner:
			var tier: int = int(p.get("tier", 1))
			var qm: float = float(p.get("quality_mult", 1.0))
			var base := 1.0 - 0.05 - 0.05 * float(tier - 1)
			return maxf(0.35, base / qm)
	return 1.0


# ── 图鉴 ───────────────────────────────────────
## key = "品种名|品质名"，偷回来就算发现
var discovered: Dictionary = {}


func discover(name: String, quality: String) -> bool:
	var key := "%s|%s" % [name, quality]
	if discovered.has(key):
		return false
	discovered[key] = true
	print("[图鉴] 新发现：%s（%s）　%d/%d" % [name, quality, discovered.size(), 160])
	return true


func discovered_count() -> int:
	return discovered.size()
