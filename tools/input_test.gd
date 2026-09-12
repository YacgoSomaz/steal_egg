extends SceneTree
## 输入映射自检：确认 move_* 四个动作存在，且 WASD / 方向键都绑上了。
##
## 用法：
##   Godot --headless --script res://tools/input_test.gd
##
## 背景：之前用的是内置 ui_left/ui_right/ui_up/ui_down，而 Godot 4 里
## 这四个默认只绑方向键、**不含 WASD**，所以 WASD 一直按不动。
## 这个自检就是防止那种事再发生。

const WANT := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
}


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
	if bad == 0:
		print("[输入自检] 全部通过")
	else:
		print("[输入自检] %d 项有问题" % bad)
	quit()
