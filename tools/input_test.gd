extends SceneTree
## 输入自检：① move_* 动作绑定 ② 移动方向是否跟着相机转
##
## 用法：
##   Godot --headless --script res://tools/input_test.gd
##
## 背景 ①：之前用的是内置 ui_left/ui_right/ui_up/ui_down，而 Godot 4 里
## 这四个默认只绑方向键、**不含 WASD**，所以 WASD 一直按不动。
##
## 背景 ②：加了自由视角之后，移动如果还按世界坐标算，转一下鼠标
## 按 W 就变成横着走。这段数学错了 headless 里看不出来，只能靠断言守。

const MOVE_MATH := preload("res://scripts/core/move_math.gd")

const WANT := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
}

## [说明, yaw, 输入向量, 期望的世界方向]
## 输入向量是 Input.get_vector("left","right","forward","back") 的返回值：
## 按 W → (0,−1)，按 D → (1,0)。
const DIR_CASES := [
	["没转视角 按W → 往画面里走", 0.0, Vector2(0.0, -1.0), Vector3(0.0, 0.0, -1.0)],
	["没转视角 按S → 往画面外走", 0.0, Vector2(0.0, 1.0), Vector3(0.0, 0.0, 1.0)],
	["没转视角 按A → 画面左", 0.0, Vector2(-1.0, 0.0), Vector3(-1.0, 0.0, 0.0)],
	["没转视角 按D → 画面右", 0.0, Vector2(1.0, 0.0), Vector3(1.0, 0.0, 0.0)],
	["视角右转90° 按W → 世界 −X", PI * 0.5, Vector2(0.0, -1.0), Vector3(-1.0, 0.0, 0.0)],
	["视角右转90° 按D → 世界 −Z", PI * 0.5, Vector2(1.0, 0.0), Vector3(0.0, 0.0, -1.0)],
	["视角左转90° 按W → 世界 +X", -PI * 0.5, Vector2(0.0, -1.0), Vector3(1.0, 0.0, 0.0)],
	["视角转180° 按W → 世界 +Z", PI, Vector2(0.0, -1.0), Vector3(0.0, 0.0, 1.0)],
]


func _initialize() -> void:
	var bad := 0
	print("[输入自检] move_* 动作绑定")
	for action in WANT.keys():
		if not InputMap.has_action(action):
			print("  ✗ %s —— 动作不存在！" % action)
			bad += 1
			continue
		var keys: Array = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var k := ev as InputEventKey
				keys.append(k.physical_keycode if k.physical_keycode != 0 else k.keycode)
		var missing: Array = []
		for want in WANT[action]:
			if not keys.has(want):
				missing.append(OS.get_keycode_string(want))
		if missing.is_empty():
			print("  ✓ %s ← %s" % [action, str(keys)])
		else:
			print("  ✗ %s 缺少 %s（当前只有 %s）" % [action, str(missing), str(keys)])
			bad += 1

	print("[输入自检] 移动方向跟随相机")
	for c in DIR_CASES:
		var label := str(c[0])
		var yaw := float(c[1])
		var inp := c[2] as Vector2
		var want := c[3] as Vector3
		var got := MOVE_MATH.dir_from_input(inp, yaw)
		if got.distance_to(want) < 0.01:
			print("  ✓ %s" % label)
		else:
			print("  ✗ %s —— 期望 %s，实际 %s" % [label, str(want), str(got)])
			bad += 1
	# 没输入时必须是零向量，否则玩家会自己飘
	if MOVE_MATH.dir_from_input(Vector2.ZERO, 1.23).length() > 0.001:
		print("  ✗ 无输入时返回了非零方向，玩家会自己飘")
		bad += 1
	else:
		print("  ✓ 无输入时静止")

	if bad == 0:
		print("[输入自检] 全部通过")
	else:
		print("[输入自检] %d 项有问题" % bad)
	quit()
