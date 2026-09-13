extends Node3D
## 跑道主控：相机跟随、偷蛋读条、撤离判定、HUD
##
## 张力设计：冲得越远蛋越值钱，但**必须自己扛着蛋跑回起点**才算数。
## 回程那一路上，被你吵醒的怪全在后面追。

const CreatureDB := preload("res://scripts/data/creature_db.gd")
const LANDMARK := preload("res://scenes/run/landmark.tscn")
const FARM_ZONE := preload("res://scripts/run/farm_zone.gd")

## 相机：绕玩家自由转的第三人称。鼠标控制偏航/俯仰，滚轮拉远近。
## 之所以从"固定越肩"改成自由视角：撤离点后面就是农场和店铺，
## 玩家得能扭头看看自己养的生物长成什么样了。
const CAM_FOV := 72.0
const CAM_LERP := 7.0           # 跟随平滑，别让玩家一转向画面就抽
const CAM_TARGET_Y := 1.3       # 看向玩家胸口，不是脚底
const CAM_DIST_DEF := 8.6
const CAM_DIST_MIN := 3.0
const CAM_DIST_MAX := 24.0
const CAM_PITCH_DEF := 0.30     # 弧度，正值=相机在上方俯视
const CAM_PITCH_MIN := -0.35    # 压到最低，几乎平视（看巨兽用）
const CAM_PITCH_MAX := 1.15     # 拉到最高，快成俯视图
const MOUSE_SENS := 0.0026
const WHEEL_STEP := 0.9

## 速度感三件套。注意配比：以前 zoom 给到 6 倍、模型放大 0.35，
## 结果把速度提升全抵消了——数值涨 10 倍，看着跟没涨一样。
## 现在只做「够用」的补偿，剩下的速度感交给地面条纹和 FOV。
const ZOOM_DIV := 25.0          # 相机拉远：速度/25，封顶 3.5 倍
const ZOOM_MAX := 3.5
const FOV_PER_SPEED := 0.30     # FOV 随速度扩张，制造推背感
const FOV_MAX_BOOST := 18.0

const GRAB_RANGE := 3.6
## 撤离线。和追兵放弃、追兵位置夹取共用同一个常量——
## 以前这三处各写各的，才会出现"蛋进仓库了，怪还追进农场撞人"。
const ESCAPE_Z := CreatureDB.SAFE_LINE
const NOISE_RADIUS := 12.0      # 偷蛋的动静会吵醒周围这么远的怪（蹲走减半）
const LANDMARK_AHEAD := 250.0   # 巨型生物摆在玩家前方这么远

@onready var _cam: Camera3D = $Camera3D
@onready var _player: Node3D = $Player
@onready var _track: Node3D = $Track
@onready var _sun: DirectionalLight3D = $Sun
@onready var _fill: DirectionalLight3D = $Fill
@onready var _info: Label = $HUD/Info
@onready var _hint: Label = $HUD/Hint
@onready var _toast_label: Label = $HUD/Toast
@onready var _bar: ProgressBar = $HUD/GrabBar

var _grab_target: Node3D = null
var _grab_progress := 0.0
var _toast := ""
var _toast_time := 0.0
var _landmarks: Array = []
var _landmark_tier := 0
var _cam_ready := false
var _gallery := false
var _gallery_tier := 1
var _gallery_node: Node = null
var _cam_yaw := 0.0
var _cam_pitch := CAM_PITCH_DEF
var _cam_dist := CAM_DIST_DEF
var _farm: Node3D = null
var _near_station: Dictionary = {}
var _want_interact := false      # 本帧是否按下了 E（边沿触发，防止按住连买）
var _at_home := false            # 上一帧是否已在安全区，用来只在"刚跨过来"时提示


func _ready() -> void:
	GameState.refresh_start_tier()   # 从哪一阶开门，由当前速度决定
	_setup_lights()
	GameEvents.player_caught.connect(_on_caught)
	# 调试用：--jump 直接跳到 700m 处，--diag 把生成结果打出来
	var args := OS.get_cmdline_args()
	if args.has("--jump"):
		# --jump 20000 直接跳到 20000 m 处，方便看高阶长什么样
		var d := 700.0
		var i := args.find("--jump")
		if i + 1 < args.size():
			d = absf(float(args[i + 1]))
		_player.position.z = -d
	# 撤离点后面的农场 + 店铺。不再切场景，走回去就行
	_farm = Node3D.new()
	_farm.name = "FarmZone"
	_farm.set_script(FARM_ZONE)
	add_child(_farm)
	_farm.call("build")

	_track.call("update", _player.position.z)
	_bar.visible = false
	# 玩家就出生在撤离点上（z=0 > 安全线），所以一开始就算"在家"。
	# 不初始化的话，第一帧会白弹一次"已进入撤离区"的提示。
	_at_home = _player.position.z > ESCAPE_Z
	# 鼠标接管视角。Tab 释放（要去点别的窗口时用），再按 Tab 收回
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if args.has("--diag"):
		await get_tree().process_frame
		_diag()
	if args.has("--shop"):
		await get_tree().process_frame
		_shop_selftest()
	if args.has("--esc"):
		await get_tree().process_frame
		_esc_selftest()
	if args.has("--chase"):
		await get_tree().process_frame
		_chase_selftest()
	if args.has("--tier"):
		await get_tree().process_frame
		_tier_selftest()
	if args.has("--gallery"):
		_gallery = true
		# --gallery 7 可以从指定阶位开始，headless 下也能逐阶验证接线
		var gt := 1
		var gi := args.find("--gallery")
		if gi + 1 < args.size():
			gt = int(absf(float(args[gi + 1])))
		_spawn_gallery(gt)


## 商店自检：给一笔钱，把六个摊位各买一遍。
## 这类「点一下扣钱加属性」的逻辑最容易写错（成本公式、等级上限、越界），
## 而且错了要玩家玩很久才发现，值得每次改动都自动跑一遍。
func _shop_selftest() -> void:
	# 先快照 + 关掉写档。自检会真的改 GameState，而 _after_buy 里会触发存档——
	# 不关的话，测试用的 99 万金币会直接写进玩家的存档里（真的发生过）。
	SaveManager.test_mode = true
	var snap := {
		"coins": GameState.coins, "speed_level": GameState.speed_level,
		"stealth_level": GameState.stealth_level, "shoe_level": GameState.shoe_level,
		"gear_cloak": GameState.gear_cloak, "gear_jet": GameState.gear_jet,
		"catch_count": GameState.catch_count,
		"farm": GameState.farm.duplicate(true),
		"stored": GameState.stored.duplicate(true),
	}
	GameState.coins = 999999.0
	GameState.stored = [
		{"name": "林蜥蛋", "tier": 2, "income": 1.2, "value": 42.0,
			"quality_name": "优良", "quality_mult": 1.4},
		{"name": "火蜥蛋", "tier": 4, "income": 9.0, "value": 315.0,
			"quality_name": "普通", "quality_mult": 1.0},
	]
	print("[商店自检] 起始：金币 %.0f ｜ 仓库 %d 颗 ｜ 干净速度 %.2f（%.0f km/h）" % [
		GameState.coins, GameState.stored.size(),
		GameState.get_clean_speed(), GameState.get_display_speed()])
	var list: Array = _farm.get("_stations") as Array
	for st in list:
		var msg := str(_farm.call("interact", st))
		print("  %-8s → %s" % [str(st.get("name", "")), msg])
	print("[商店自检] 结束：金币 %.0f ｜ 锻炼 Lv%d ｜ 跑鞋 Lv%d ｜ 披风 Lv%d ｜ 喷气 Lv%d" % [
		GameState.coins, GameState.speed_level, GameState.shoe_level,
		GameState.gear_cloak, GameState.gear_jet])
	print("[商店自检] 　　　农场 %d 只（每秒 +%.1f）｜ 仓库剩 %d 颗 ｜ 干净速度 %.2f（%.0f km/h）" % [
		GameState.farm.size(), GameState.get_income_per_sec(), GameState.stored.size(),
		GameState.get_clean_speed(), GameState.get_display_speed()])
	# 摊位识别：站在中央摊位前应该能认出来
	var st2: Dictionary = _farm.call("nearest", Vector3(0.0, 0.0, 10.0)) as Dictionary
	print("[商店自检] 站在 (0, 10) 时最近摊位 = %s" % str(st2.get("name", "（没识别到）")))
	var st3: Dictionary = _farm.call("nearest", Vector3(0.0, 0.0, -60.0)) as Dictionary
	print("[商店自检] 站在跑道上 (0, -60) 时 = %s" % str(st3.get("name", "（正确地没提示）")))

	# 还原内存状态，然后恢复写档。
	# 注意顺序：先把 test_mode 关掉，再决定要不要真写一次——
	# 这里不写，因为自检根本没改过存档里的东西（写档全程被挡掉了）。
	GameState.coins = float(snap["coins"])
	GameState.speed_level = int(snap["speed_level"])
	GameState.stealth_level = int(snap["stealth_level"])
	GameState.shoe_level = int(snap["shoe_level"])
	GameState.gear_cloak = int(snap["gear_cloak"])
	GameState.gear_jet = int(snap["gear_jet"])
	GameState.catch_count = int(snap["catch_count"])
	GameState.farm = snap["farm"] as Array
	GameState.stored = snap["stored"] as Array
	SaveManager.test_mode = false
	print("[商店自检] 已还原内存状态（存档全程未写入）：金币 %.0f ｜ 锻炼 Lv%d ｜ 农场 %d 只 ｜ 仓库 %d 颗" % [
		GameState.coins, GameState.speed_level, GameState.farm.size(), GameState.stored.size()])


## 撤离自检：把蛋塞进背包 → 跨过撤离线 → 走到摊位卖。
##
## 这条链路横跨 main.gd / game_state.gd / farm_zone.gd 三个文件，
## 断在哪一环，玩家看到的都是同一句「我明明带回来了，它说我没蛋」。
## 所以要把每一环的中间状态都打出来，而不是只看最后一句提示。
func _esc_selftest() -> void:
	SaveManager.test_mode = true
	var snap := {
		"coins": GameState.coins, "carried": GameState.carried.duplicate(true),
		"stored": GameState.stored.duplicate(true),
		"farm": GameState.farm.duplicate(true),
	}
	var egg := {"name": "林蜥蛋", "tier": 2, "income": 1.2, "value": 42.0,
		"quality_name": "优良", "quality_mult": 1.4}
	GameState.carried = [egg.duplicate(true), egg.duplicate(true)]
	GameState.stored = []
	print("[撤离自检] 出发：背包 %d 颗 ｜ 仓库 %d 颗 ｜ 撤离线 z=%.0f"
		% [GameState.carried.size(), GameState.stored.size(), ESCAPE_Z])

	# ① 还在跑道上，不该入库
	_player.position.z = -40.0
	_check_escape()
	print("[撤离自检] ① 站在 -40 m（未过线）→ 背包 %d ｜ 仓库 %d"
		% [GameState.carried.size(), GameState.stored.size()])

	# ② 跨过撤离线，应该自动入库
	_player.position.z = 2.0
	_check_escape()
	print("[撤离自检] ② 走到 +2 m（已过线）→ 背包 %d ｜ 仓库 %d ｜ 提示「%s」"
		% [GameState.carried.size(), GameState.stored.size(), _toast])

	# ③ 站到卖蛋摊位前按 E
	var st: Dictionary = _farm.call("nearest", Vector3(19.5, 0.0, 10.0)) as Dictionary
	print("[撤离自检] ③ 站在卖蛋摊位前 → 识别到「%s」"
		% str(st.get("name", "（没识别到）")))
	print("[撤离自检] ③ 按 E → 「%s」" % str(_farm.call("interact", st)))
	print("[撤离自检] ③ 卖完 → 金币 %.0f ｜ 仓库 %d 颗"
		% [GameState.coins, GameState.stored.size()])

	# ④ 再偷一颗，重复一次：确认不是"只能成功一次"
	GameState.carried = [egg.duplicate(true)]
	_player.position.z = -40.0
	_check_escape()
	_player.position.z = 2.0
	_check_escape()
	var st2: Dictionary = _farm.call("nearest", Vector3(19.5, 0.0, 10.0)) as Dictionary
	print("[撤离自检] ④ 第二趟：仓库 %d 颗 ｜ 按 E → 「%s」"
		% [GameState.stored.size(), str(_farm.call("interact", st2))])

	# ⑤ 把蛋放进农场，再去卖蛋——必须说清"蛋在农场产钱"而不是"你没有蛋"。
	#    这正是实际收到的反馈：玩家放完农场再来卖，看到"仓库是空的"以为蛋丢了。
	GameState.carried = [egg.duplicate(true)]
	_player.position.z = -40.0
	_check_escape()
	_player.position.z = 2.0
	_check_escape()
	var st_raise: Dictionary = _farm.call("nearest", Vector3(12.0, 0.0, 10.0)) as Dictionary
	var st_sell: Dictionary = _farm.call("nearest", Vector3(19.5, 0.0, 10.0)) as Dictionary
	print("[撤离自检] ⑤ 先入农场 → 「%s」" % str(_farm.call("interact", st_raise)))
	print("[撤离自检] ⑤ 再去卖蛋 → 「%s」" % str(_farm.call("interact", st_sell)))
	print("[撤离自检] ⑤ 状态：仓库 %d 颗 ｜ 农场 %d 只"
		% [GameState.stored.size(), GameState.farm.size()])

	GameState.coins = float(snap["coins"])
	GameState.carried = snap["carried"] as Array
	GameState.stored = snap["stored"] as Array
	GameState.farm = snap["farm"] as Array
	SaveManager.test_mode = false
	print("[撤离自检] 已还原内存状态（存档全程未写入）：金币 %.0f ｜ 仓库 %d 颗" % [
		GameState.coins, GameState.stored.size()])


## 追兵边界自检：把一只「蛋被偷了」的怪放在跑道深处，把玩家丢进农场，
## 看它会不会一路追进店铺门口。
##
## 这是用户实际报过的问题——"怪物都追到撤离点里面来撞我了"。
## 而它同时会引发第二个症状：玩家在自家门口被抢走刚入库的蛋，
## 然后去卖蛋发现是空的。所以这条必须自动化守住。
func _chase_selftest() -> void:
	SaveManager.test_mode = true
	var snap := {"catch_count": GameState.catch_count, "coins": GameState.coins}
	var c: Node3D = preload("res://scenes/run/creature.tscn").instantiate()
	add_child(c)
	c.position = Vector3(0.0, 0.0, -40.0)
	c.call("setup", 5)
	c.call("set_home", Vector3(0.0, 0.0, -40.0))
	c.call("wake", 0.01)
	c.call("on_egg_stolen")          # 变成"不追回来不罢休"的那种

	# 第一段：玩家还在跑道上，怪应该**确实在追**（不然这个自检就是空跑）
	_player.position = Vector3(0.0, 0.0, -20.0)
	var z0 := c.global_position.z
	for i in range(40):
		await get_tree().physics_frame
	var z1 := c.global_position.z
	var chased := z1 > z0 + 1.0
	print("[追兵自检] ① 玩家在跑道 z=-20：怪 z %.1f → %.1f ｜ %s"
		% [z0, z1, "✓ 在追" if chased else "✗ 没动（自检无效）"])

	# 第二段：玩家跑回农场，怪必须放弃，且**全程不许越线**。
	# 记录这一段里它到过的最大 z —— 只看最终位置是不够的：
	# 它可能先冲进农场再"回家"，最终位置看起来正常，其实已经撞过人了。
	_player.position = Vector3(0.0, 0.0, 6.0)
	var caught_before := GameState.catch_count
	var max_z := c.global_position.z
	for i in range(180):
		await get_tree().physics_frame
		max_z = maxf(max_z, c.global_position.z)
	print("[追兵自检] ② 玩家进农场 z=+6：怪本段最大 z=%.2f（安全线 %.0f）｜ 终态 z=%.2f 状态 %s"
		% [max_z, CreatureDB.SAFE_LINE, c.global_position.z, str(c.get("_state"))])
	var ok := max_z <= CreatureDB.SAFE_LINE + 0.01
	var ok2 := GameState.catch_count == caught_before
	print("[追兵自检] %s 追兵全程没有越过安全线" % ("✓" if ok else "✗"))
	print("[追兵自检] %s 玩家在农场里没有被抓（被抓 %d → %d）"
		% ["✓" if ok2 else "✗", caught_before, GameState.catch_count])

	# 第三段：直接把怪硬塞到农场里（模拟"某阶怪速度太大一步跨过"），
	# 验证位置夹取会把它拽回安全线。这是兜底，正常追击走不到这里。
	c.global_position = Vector3(0.0, 0.0, 10.0)
	c.call("wake", 0.01)
	_player.position = Vector3(0.0, 0.0, -30.0)     # 玩家在跑道深处，怪才会继续追
	for i in range(4):
		await get_tree().physics_frame
	var cz3 := c.global_position.z
	var ok3 := cz3 <= CreatureDB.SAFE_LINE + 0.01
	print("[追兵自检] ③ 硬塞到 z=+10 → 4 帧后 z=%.2f ｜ %s"
		% [cz3, "✓ 被拽回安全线内" if ok3 else "✗ 仍在线外"])

	c.queue_free()
	GameState.catch_count = int(snap["catch_count"])
	GameState.coins = float(snap["coins"])
	_player.position = Vector3(0.0, 0.0, 0.0)
	SaveManager.test_mode = false
	print("[追兵自检] %s（存档全程未写入）"
		% ("全部通过" if (chased and ok and ok2 and ok3) else "**失败**"))


## 起始阶位自检：确认「被抓」不会把玩家推回 T1「草鸡」。
##
## 为什么必须自动守：这类缺陷**不会报任何错**。表现只是"被抓几次之后
## 跑道上的怪又变回最便宜那批"，玩家只会觉得"我变弱了"，查代码看不出来。
##
## ⚠️ 守的是**下限**，不是"不变"。
## 起始阶位随惩罚变浅是**设计**（必须等于你当前跑得过的那一阶，
## 否则开在自己跑不过的阶位上必被抓 → 死循环，详见 game_state.refresh_start_tier）。
## 不允许的只有一件事：掉到 T1 —— 那是被淘汰的内容，用户明确说不要。
func _tier_selftest() -> void:
	SaveManager.test_mode = true
	var snap := {
		"catch_count": GameState.catch_count,
		"speed_level": GameState.speed_level,
		"shoe_level": GameState.shoe_level,
	}

	print("[起始阶自检] ① 当前 速度 Lv%d / 跑鞋 Lv%d ｜ 干净速度 %.2f"
		% [GameState.speed_level, GameState.shoe_level, GameState.get_clean_speed()])

	GameState.catch_count = 0
	GameState.refresh_start_tier()
	var t_free: int = GameState.start_tier
	print("[起始阶自检] ② 没被抓 → 起点阶 T%d（实际速度 %.2f）"
		% [t_free, GameState.get_run_speed()])

	# 关键断言：惩罚封底时，起始阶位仍不得低于下限
	GameState.catch_count = 99
	GameState.refresh_start_tier()
	var t_caught: int = GameState.start_tier
	var ok1 := t_caught >= CreatureDB.MIN_START_TIER
	print("[起始阶自检] ③ 被抓 99 次（惩罚封底 ×%.3f）→ 起点阶 T%d（实际速度 %.2f）"
		% [GameState.get_penalty_multiplier(), t_caught, GameState.get_run_speed()])
	print("[起始阶自检] %s 惩罚再重也不掉回 T1（下限 T%d）"
		% ["✓" if ok1 else "✗", CreatureDB.MIN_START_TIER])

	# 兜底断言：全零新号 + 抓满，是最容易被推到 T1 的组合
	GameState.speed_level = 0
	GameState.shoe_level = 0
	GameState.refresh_start_tier()
	var t_new: int = GameState.start_tier
	var ok2 := t_new >= CreatureDB.MIN_START_TIER
	print("[起始阶自检] %s 全零新号 + 抓满 → T%d" % ["✓" if ok2 else "✗", t_new])

	# 诊断（**不是断言**）：起始阶的怪是否比玩家慢。
	# 新号+满惩罚时这条会不成立 —— 那是惩罚按设计生效，不是 bug，
	# 玩家可以花钱治疗（GameState.heal / HEAL_CATCHES 一次抹 3 次）。
	var ti := clampi(t_caught, 1, CreatureDB.MAX_TIER) - 1
	var tier_speed := float(CreatureDB.TIERS[ti]["speed"])
	print("[起始阶自检] ④ 起始阶怪速 %.1f vs 实际速度 %.2f → %s"
		% [tier_speed, GameState.get_run_speed(),
		   "跑得过" if GameState.get_run_speed() >= tier_speed
		   else "跑不过（惩罚生效中，可花钱治疗）"])

	GameState.catch_count = int(snap["catch_count"])
	GameState.speed_level = int(snap["speed_level"])
	GameState.shoe_level = int(snap["shoe_level"])
	GameState.refresh_start_tier()
	SaveManager.test_mode = false
	print("[起始阶自检] %s（存档全程未写入）｜ 已还原：起点阶 T%d"
		% ["全部通过" if (ok1 and ok2) else "**失败**", GameState.start_tier])


func _diag() -> void:
	var creatures := get_tree().get_nodes_in_group("creatures")
	var eggs := get_tree().get_nodes_in_group("eggs")
	var dist := maxf(0.0, -_player.position.z)
	var by_tier: Dictionary = {}
	# 兽栏里养着的怪不算跑道怪：它们不睡、不追、也不在跑道上。
	# 不排除的话，玩家一旦养了怪，"最近怪"就会永远是 0 m（兽栏在 z≈46），
	# 首怪距离这个指标直接失效——这是个会骗人的假信号。
	var track_creatures: Array = []
	for c in creatures:
		if bool(c.get("_display")):
			continue
		track_creatures.append(c)
	for c in track_creatures:
		var t := int(c.get("tier"))
		by_tier[t] = int(by_tier.get(t, 0)) + 1
	# 最近的那只怪离起点多远——这个数字太大就说明起点附近太空
	var nearest := INF
	for c in track_creatures:
		var n: Node3D = c as Node3D
		nearest = minf(nearest, maxf(0.0, -n.global_position.z))
	if is_inf(nearest):
		nearest = 0.0
	print("[自检] 起点阶 T%d ｜ 距离 %.0f m ｜ 当前阶 T%d ｜ 沉睡怪 %d 只（兽栏 %d 只不计）｜ 蛋 %d 颗 ｜ 最近怪 %.0f m ｜ 阶位分布 %s" % [
		GameState.start_tier, dist, CreatureDB.tier_at(dist, GameState.start_tier),
		track_creatures.size(), creatures.size() - track_creatures.size(),
		eggs.size(), nearest, str(by_tier),
	])


## 陈列模式：一次只放一只在眼前慢慢转，按 1-9/0 或 [ ] 换阶。
##
## 为什么做成一次一只而不是一字排开：T10 到 4.6 倍体型、二十个单位高，
## 十只并排根本塞不进画面，而且透视会让远的那几只失真，反而比不出差别。
func _spawn_gallery(t: int) -> void:
	if _gallery_node != null and is_instance_valid(_gallery_node):
		_gallery_node.queue_free()
	_gallery_tier = clampi(t, 1, CreatureDB.MAX_TIER)
	var s: Node = preload("res://scenes/run/creature.tscn").instantiate()
	s.call("setup", _gallery_tier)
	# 观察距离按体型走：T1 只有 1.9 单位高，放远了是个点；
	# T10 有二十个单位高，放近了连头都出画。这样既看得清细节，又保住体型差
	var sc := float(CreatureDB.tier_data(_gallery_tier).get("scale", 1.0))
	s.position = Vector3(0.0, 0.0, -(6.0 + sc * 2.5))
	add_child(s)
	s.call("set_home", s.position)
	s.call("set_display", true)
	_gallery_node = s


# ── 相机 ───────────────────────────────────────
func _cam_target() -> Vector3:
	return _player.position + Vector3(0.0, CAM_TARGET_Y, 0.0)


## 从玩家指向相机的单位向量，乘上距离就是偏移。
## yaw=0 时相机在 +Z（玩家背后），因为玩家朝 −Z。
func _cam_offset() -> Vector3:
	var cp := cos(_cam_pitch)
	return Vector3(sin(_cam_yaw) * cp, sin(_cam_pitch), cos(_cam_yaw) * cp) * _cam_dist


# ── 店铺交互 ───────────────────────────────────
## 走到摊位边上按 E 就买。撤离点后面就是店铺，不用再切场景。
func _handle_shop() -> void:
	if _farm == null:
		return
	_near_station = _farm.call("nearest", _player.position) as Dictionary
	if _near_station.is_empty():
		_want_interact = false
		return
	# 必须用"按下"的边沿，不能用 is_key_pressed 轮询——
	# 否则站在摊位前按住 E 会每帧买一次，一秒钟把金币清空
	if _want_interact:
		_want_interact = false
		var msg := str(_farm.call("interact", _near_station))
		if msg != "":
			_show_toast(msg)
			GameState.refresh_start_tier()   # 速度变了，下次开门的阶位也要跟着变


func _setup_lights() -> void:
	_sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	_sun.light_energy = 1.15
	_fill.rotation_degrees = Vector3(-25.0, -140.0, 0.0)
	_fill.light_energy = 0.45
	# 透视投影：地平线进画面，远处的巨兽才看得见
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = CAM_FOV
	# 第一帧直接摆到位，别从原点飞过去
	_cam.position = _cam_target() + _cam_offset()
	_cam.look_at(_cam_target(), Vector3.UP)
	_cam_ready = true
	_build_start_marker()
	_setup_environment()
	_setup_landmarks()


## 雾 + 天空色：让远处的大东西有层次，而不是贴在纯色背景上
func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.66, 0.76)
	env.ambient_light_energy = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.80, 0.90)
	env.fog_density = 0.0022
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_landmarks() -> void:
	for i in range(2):
		var lm: Node3D = LANDMARK.instantiate() as Node3D
		add_child(lm)
		_landmarks.append(lm)
	_update_landmarks()


## 巨型生物永远在你前方固定的距离，随你前进——你跑多远，它就退多远，
## 但它的阶位会跟着涨：看得见的威胁，才叫目标
func _update_landmarks() -> void:
	if _landmarks.is_empty():
		return
	var dist := maxf(0.0, -_player.position.z) + LANDMARK_AHEAD
	var t := CreatureDB.tier_at(dist, GameState.start_tier)
	if t != _landmark_tier:
		_landmark_tier = t
		for i in range(_landmarks.size()):
			var lm: Node3D = _landmarks[i]
			lm.call("setup", t, 1 if i == 0 else -1)
	var k := CreatureDB.world_scale(t)
	var z := _player.position.z - LANDMARK_AHEAD * (1.0 + (k - 1.0) * 0.3)
	var a: Node3D = _landmarks[0]
	var b: Node3D = _landmarks[1]
	a.position = Vector3(-62.0 * k, 0.0, z)
	b.position = Vector3(70.0 * k, 0.0, z - 95.0 * k)


## 撤离区得看得见，否则玩家不知道该往哪儿跑。
## 还要有一条**明确的安全线**：玩家必须能看出"过这条线追兵就回头"，
## 否则他会以为农场里也不安全，不敢停下来买东西。
func _build_start_marker() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(26.0, 16.0)
	mi.mesh = pm
	mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	mi.position = Vector3(0.0, 0.06, -8.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.85, 0.45, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	add_child(mi)

	# 安全线本体：一条横贯跑道的亮线，位置就是 CreatureDB.SAFE_LINE
	var line := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(30.0, 0.12, 0.7)
	line.mesh = lm
	line.position = Vector3(0.0, 0.08, ESCAPE_Z)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.45, 0.95, 0.55)
	lmat.emission_enabled = true
	lmat.emission = Color(0.35, 0.85, 0.45)
	lmat.emission_energy_multiplier = 1.6
	line.material_override = lmat
	add_child(line)

	var tag := Label3D.new()
	tag.text = "起点 / 撤离"
	tag.font_size = 40
	tag.position = Vector3(0.0, 2.6, -8.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(tag)

	var safe := Label3D.new()
	safe.text = "安全线 · 过此线追兵回头"
	safe.font_size = 30
	safe.position = Vector3(0.0, 1.9, ESCAPE_Z)
	safe.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	safe.modulate = Color(0.60, 1.0, 0.70)
	add_child(safe)


func _process(delta: float) -> void:
	GameState.run_time += delta      # 喷气起步要看开局秒数
	GameState.tick_income(delta)
	_track.call("update", _player.position.z)
	# 把相机朝向喂给玩家：移动是"相对相机"的，不喂的话 W 永远往世界 −Z 走，
	# 转了视角就变成横着走。喂的是目标偏航角（不是 lerp 后的相机），操作更跟手。
	_player.set("cam_yaw", _cam_yaw)
	if _cam_ready:
		var sp := GameState.get_run_speed()
		var zoom := CreatureDB.camera_zoom(sp)
		var target := _cam_target()
		var want := target + _cam_offset() * zoom
		_cam.position = _cam.position.lerp(want, clampf(CAM_LERP * delta, 0.0, 1.0))
		# 朝向每帧重算：位置是 lerp 过去的，朝向不能也跟着慢半拍
		_cam.look_at(target, Vector3.UP)
		# FOV 随速度撑开：这是最便宜也最有效的"我在变快"信号
		_cam.fov = CAM_FOV + clampf(sp * FOV_PER_SPEED, 0.0, FOV_MAX_BOOST)
		# 高速时轻微抖动，速度感里"体感"的那一半
		var shake := clampf((sp - 25.0) / 60.0, 0.0, 1.0) * 0.09 * zoom
		if shake > 0.001:
			_cam.position.x += randf_range(-shake, shake)
			_cam.position.y += randf_range(-shake, shake)
	_update_landmarks()
	_handle_grab(delta)
	_handle_shop()
	_check_escape()
	if _toast_time > 0.0:
		_toast_time -= delta
	_update_hud()


# ── 偷蛋 ───────────────────────────────────────
func _handle_grab(delta: float) -> void:
	if _grab_target != null:
		_player.set("frozen", true)
		_grab_progress += delta
		var need := GameState.get_grab_time()
		_bar.visible = true
		_bar.value = clampf(_grab_progress / need, 0.0, 1.0) * 100.0
		if _grab_progress >= need:
			_finish_grab()
		return

	_player.set("frozen", false)
	_bar.visible = false
	if Input.is_key_pressed(KEY_E):
		_try_grab()


func _try_grab() -> void:
	var best: Node3D = null
	var bd := GRAB_RANGE
	for e in get_tree().get_nodes_in_group("eggs"):
		if bool(e.get("taken")):
			continue
		var d := _flat_dist(e)
		if d < bd:
			bd = d
			best = e as Node3D
	if best != null:
		_grab_target = best
		_grab_progress = 0.0


func _finish_grab() -> void:
	_grab_target.call("take")
	var d: Dictionary = _grab_target.get("data")
	GameState.add_carried(d)
	var nm := str(d.get("name", "蛋"))
	GameEvents.egg_stolen.emit(int(d.get("tier", 1)), nm)
	_show_toast("得手：%s（%s）" % [nm, str(d.get("quality_name", "普通"))])
	var sneaked := bool(_player.get("sneaking"))
	_wake_nearby(_grab_target.global_position, NOISE_RADIUS * (0.5 if sneaked else 1.0))
	_grab_target = null
	_grab_progress = 0.0
	_player.set("frozen", false)


## 不只是蛋主人醒，动静范围内的也醒——但它们是被吵醒的，反应比主人慢一半
func _wake_nearby(pos: Vector3, r: float) -> void:
	for c in get_tree().get_nodes_in_group("creatures"):
		if bool(c.call("is_asleep")):
			var d := Vector2(c.global_position.x - pos.x, c.global_position.z - pos.z).length()
			if d < r:
				var base := float(c.call("get_base_wake"))
				c.call("wake", GameState.get_wake_delay(base) * 1.5)


# ── 撤离 ───────────────────────────────────────
## 跑过撤离线就把蛋卸进仓库——**不切场景**。
## 后面就是农场和店铺，转身走两步就能花掉，节奏不再被打断。
##
## 注意这里和 creature.gd 的追兵放弃是**同一条线**（CreatureDB.SAFE_LINE）：
## 玩家过线的同一帧，蛋入库 + 追兵回头，两件事必须同时发生。
## 如果只做入库不做回头，玩家会在自家店铺门口被抢第二次。
func _check_escape() -> void:
	var home := _player.position.z > ESCAPE_Z
	# 刚跨过线：不管身上有没有蛋都要告诉玩家"安全了"，
	# 否则空手跑回来的人会以为追兵还在，继续往农场里躲
	if home and not _at_home:
		_show_toast("已进入撤离区——追兵到此为止，不会再追进来")
	_at_home = home
	if GameState.carried.is_empty():
		return
	if home:
		var n := GameState.store_carried()
		GameEvents.escaped.emit(n)
		SaveManager.save()
		_show_toast("撤离成功：%d 颗蛋进了仓库，转身去摊位花掉" % n)


func _on_caught(lost: Dictionary) -> void:
	if lost.is_empty():
		_show_toast("被撞飞了！速度 ×0.97")
	else:
		_show_toast("%s 被抢回去了！速度 ×0.97" % str(lost.get("name", "蛋")))


func _show_toast(text: String) -> void:
	_toast = text
	_toast_time = 2.6


# ── HUD ────────────────────────────────────────
func _update_hud() -> void:
	if _gallery:
		var gd: Dictionary = CreatureDB.tier_data(_gallery_tier)
		var gs := float(gd.get("speed", 6.0)) * GameState.DISPLAY_SPEED_SCALE
		_info.text = "【陈列】T%d %s ｜ 追击 %.0f km/h ｜ 每秒产出 %.1f ｜ 体型 ×%.2f ｜ 苏醒 %.2f s" % [
			_gallery_tier, str(gd.get("name", "")), gs,
			float(gd.get("income", 0.0)), float(gd.get("scale", 1.0)),
			float(gd.get("wake", 1.0))]
		_hint.text = "按 1-9、0 直接跳阶 ｜ [ ] 前后翻 ｜ 十阶的轮廓应该一眼分得出来"
		_toast_label.text = _toast if _toast_time > 0.0 else ""
		return
	var dist := maxf(0.0, -_player.position.z)
	if dist > GameState.best_distance:
		GameState.best_distance = dist
	var tier := CreatureDB.tier_at(dist, GameState.start_tier)
	var td: Dictionary = CreatureDB.tier_data(tier)
	var carried_n := GameState.carried.size()

	var nt := CreatureDB.distance_to_next_tier(dist, GameState.start_tier)
	var nt_txt := "下一阶还有 %.0f m" % nt if nt > 0.0 else "已是最深阶"
	var my := GameState.get_display_speed()
	var foe := float(td.get("speed", 6.0)) * GameState.DISPLAY_SPEED_SCALE
	# 两行：第一行是位置/速度/资产，第二行是**当前位置的蛋品概率**。
	# 第二行是关键——品质按跑道长度抽，玩家得能自己算出"再往前一点更划算"，
	# 否则这条曲线在他眼里根本不存在。
	_info.text = "距离 %.0f m（%s）｜ T%d %s（%.0f km/h）｜ 你 %.0f km/h【%s】｜ 携带 %d 颗 ｜ 被抓 %d 次 ×%.2f ｜ %.0f 金币\n%s" % [
		dist, nt_txt, tier, str(td.get("name", "")), foe,
		my, GameState.speed_title(my), carried_n,
		GameState.catch_count, GameState.get_penalty_multiplier(), GameState.coins,
		_quality_line(dist),
	]

	if not _near_station.is_empty():
		_hint.text = "按 E ▸ %s" % str(_near_station.get("name", ""))
	elif _player.position.z > ESCAPE_Z:
		_hint.text = "农场区（安全）｜ 仓库 %d 颗 ｜ 养着 %d 只（每秒 +%.1f 金币）｜ 走到摊位前按 E" % [
			GameState.stored.size(), GameState.farm.size(), GameState.get_income_per_sec()]
	elif carried_n > 0:
		_hint.text = "带着 %d 颗蛋——跑回绿线就安全，路上被追上就赔进去" % carried_n
	else:
		_hint.text = "WASD/方向键 移动（跟着视角走）｜ 鼠标 转视角 ｜ 滚轮 拉远近 ｜ Shift 蹲走 ｜ E 偷蛋"

	_toast_label.text = _toast if _toast_time > 0.0 else ""


## 当前位置能刷到什么品质的蛋。四个百分比直接写出来，
## 玩家看一眼就知道"现在跑深一点值不值"。
func _quality_line(dist: float) -> String:
	var parts: Array = []
	for i in range(CreatureDB.QUALITIES.size()):
		parts.append("%s %.0f%%" % [str(CreatureDB.QUALITIES[i]["name"]),
			CreatureDB.quality_chance(i, dist) * 100.0])
	return "此处蛋品：" + " ／ ".join(parts)


func _flat_dist(other: Node3D) -> float:
	var a := _player.global_position
	var b := other.global_position
	return Vector2(a.x - b.x, a.z - b.z).length()


func _input(event: InputEvent) -> void:
	# 鼠标：转视角 + 滚轮拉远近。没被捕获时不转，免得玩家去点别的窗口时画面乱飞
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mm := event as InputEventMouseMotion
			_cam_yaw -= mm.relative.x * MOUSE_SENS
			_cam_pitch = clampf(_cam_pitch + mm.relative.y * MOUSE_SENS,
					CAM_PITCH_MIN, CAM_PITCH_MAX)
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist - WHEEL_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist + WHEEL_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var kc := (event as InputEventKey).keycode

	if _gallery:
		if kc >= KEY_0 and kc <= KEY_9:
			_spawn_gallery(10 if kc == KEY_0 else (kc - KEY_0))
			return
		if kc == KEY_BRACKETLEFT:
			_spawn_gallery(_gallery_tier - 1)
			return
		if kc == KEY_BRACKETRIGHT:
			_spawn_gallery(_gallery_tier + 1)
			return

	match kc:
		KEY_TAB:
			_toggle_mouse()
		KEY_E:
			_want_interact = true          # 摊位交互，边沿触发
		KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_toggle_mouse()            # 先放鼠标，方便切窗口
			else:
				# 再按一次才进详细管理面板（孵蛋/单颗处理）
				GameState.reset_run()
				get_tree().change_scene_to_file("res://scenes/farm.tscn")


func _toggle_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
