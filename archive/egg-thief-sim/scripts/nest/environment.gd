extends Node2D
## 环境机制：按生态阶施加环境威胁（docs/03-进阶与兑换体系.md §1）
##
## 这里写入 GameState 的 env_* 字段，由 player / guard / main 各自读取：
##   env_wind        → player 移动被推挤
##   env_vision_mult → guard 视野缩放（顺带也影响玩家视野观感）
##   env_speed_mult  → player 移速缩放
##   env_oxygen      → HUD 显示，耗尽则警戒飞涨，逼你撤离
##   env_name        → HUD 显示

const ENV_BY_TIER: Dictionary = {
	1: "none",      # 农场：无
	2: "toxic",     # 湿地：毒气区（缓慢掉 Alert）
	3: "wind",      # 崖壁：周期性强风推挤
	4: "heat",      # 火山：持续高温，Alert 一直涨
	5: "blizzard",  # 极地：暴风雪周期性遮蔽守卫视野
	6: "oxygen",    # 深海：氧气倒计时
	7: "dark",      # 地下：全黑，守卫视野大减
	8: "none",      # 高山：守卫本身就够强，不加料
	9: "lowgrav",   # 云端：失重，移速周期性紊乱
	10: "none",     # 星球环：宇宙龙本人就是威胁
}

const LABELS: Dictionary = {
	"none": "", "toxic": "毒气", "wind": "强风",
	"heat": "高温", "blizzard": "暴风雪", "oxygen": "缺氧",
	"dark": "黑暗", "lowgrav": "失重",
}

@export var oxygen_total: float = 60.0
@export var dark_tint: Color = Color(0.42, 0.42, 0.52)

var _kind: String = "none"
var _t: float = 0.0
var _oxygen: float = -1.0
var _canvas_mod: CanvasModulate = null


func _ready() -> void:
	_kind = String(ENV_BY_TIER.get(GameState.current_tier, "none"))
	GameState.env_name = String(LABELS.get(_kind, ""))

	if _kind == "oxygen":
		_oxygen = oxygen_total
		GameState.env_oxygen = _oxygen

	var cm := CanvasModulate.new()
	cm.name = "EnvTint"
	add_child(cm)
	_canvas_mod = cm
	_apply_tint(0.0)


func _process(delta: float) -> void:
	_t += delta

	# 每帧先复位，再由具体环境覆写
	GameState.env_wind = Vector2.ZERO
	GameState.env_vision_mult = 1.0
	GameState.env_speed_mult = 1.0
	GameState.env_intensity = 0.0

	match _kind:
		"toxic":
			_tick_toxic(delta)
		"wind":
			_tick_wind()
		"heat":
			_tick_heat(delta)
		"blizzard":
			_tick_blizzard()
		"oxygen":
			_tick_oxygen(delta)
		"dark":
			_tick_dark()
		"lowgrav":
			_tick_lowgrav()

	_apply_tint(GameState.env_intensity)


# ── 各环境 ─────────────────────────────────────

## 伙伴是否免疫某类环境（宇宙龙 cosmic 免疫一切）
func _immune(passive_type: String) -> bool:
	return GameState.has_partner_passive(passive_type) or GameState.has_partner_passive("cosmic")


## 毒气：持续缓慢涨警戒，逼你速战速决
## 旧值 1.2/s 意味着 83 秒就满，一局根本撑不住，调到 0.8
func _tick_toxic(delta: float) -> void:
	if _immune("toxic_immune"):
		return
	GameState.add_alert(0.8 * delta)
	GameState.env_intensity = 0.3


## 强风：方向缓慢旋转的阵风，走直线会被吹偏
func _tick_wind() -> void:
	if _immune("wind_immune"):
		return
	var gust := maxf(0.0, sin(_t * 0.9))                 # 阵风强度 0-1
	var angle := _t * 0.3                                 # 风向缓慢旋转
	GameState.env_wind = Vector2(cos(angle), sin(angle) * 0.4) * 120.0 * gust
	GameState.env_intensity = gust


## 高温：警戒持续上涨，站着不动也会累积
## 旧值 3.5/s 太狠（29 秒就满，走到蛋那儿就快没了），调到 1.8 —— 约 55 秒的压迫窗口
func _tick_heat(delta: float) -> void:
	if _immune("heat_immune"):
		return
	GameState.add_alert(1.8 * delta)
	GameState.env_intensity = 0.5


## 暴风雪：10 秒周期，其中 4 秒视野减半 —— 那是你的行动窗口
## 带雪鸮（blizzard_vision）时视野压得更低，等于把窗口变成你的主场
func _tick_blizzard() -> void:
	var phase := fmod(_t, 10.0)
	if phase < 4.0:
		GameState.env_vision_mult = 0.35 if GameState.has_partner_passive("blizzard_vision") else 0.5
		GameState.env_intensity = 1.0
	else:
		GameState.env_intensity = 0.0


## 缺氧：倒计时归零后警戒飞涨，等于逼你撤离
func _tick_oxygen(delta: float) -> void:
	if _oxygen < 0.0:
		_oxygen = oxygen_total
	var cost := delta
	if GameState.has_partner_passive("cosmic"):
		cost = 0.0
	elif GameState.has_partner_passive("oxygen_half"):
		cost = delta * 0.5
	_oxygen -= cost
	GameState.env_oxygen = maxf(0.0, _oxygen)
	if _oxygen <= 0.0:
		GameState.add_alert(22.0 * delta)
		GameState.env_intensity = 1.0
	else:
		GameState.env_intensity = clampf(1.0 - _oxygen / oxygen_total, 0.0, 1.0)


## 黑暗：画面变暗 + 守卫视野大减（对双方都难，看你更熟悉地形）
## 带蝙蝠（dark_vision）时画面明显亮起来，等于你单方面看得见
func _tick_dark() -> void:
	GameState.env_vision_mult = 0.55
	GameState.env_intensity = 0.25 if _immune("dark_vision") else 1.0


## 失重：移速周期性忽快忽慢，负重控制变难
func _tick_lowgrav() -> void:
	var s := sin(_t * 1.6)
	GameState.env_speed_mult = 1.0 + s * 0.35
	GameState.env_intensity = absf(s)


# ── 画面色调 ───────────────────────────────────
func _apply_tint(intensity: float) -> void:
	if _canvas_mod == null:
		return
	if _kind == "dark":
		if _immune("dark_vision"):
			_canvas_mod.color = dark_tint.lightened(0.32)   # 蝙蝠让你看得见
		else:
			_canvas_mod.color = dark_tint
	elif _kind == "heat":
		_canvas_mod.color = Color(1.0, 0.88, 0.82)
	elif _kind == "blizzard" or _kind == "lowgrav":
		_canvas_mod.color = Color(1, 1, 1).lerp(Color(0.80, 0.86, 0.95), intensity)
	elif _kind == "oxygen":
		_canvas_mod.color = Color(1, 1, 1).lerp(Color(0.62, 0.76, 0.92), intensity * 0.8)
	else:
		_canvas_mod.color = Color(1, 1, 1)
