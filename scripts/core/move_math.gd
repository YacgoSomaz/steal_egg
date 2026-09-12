extends RefCounted
## 输入 → 世界方向 的换算。**纯函数，不依赖任何 autoload。**
##
## 为什么单独放一个文件：
## 1. 这段数学错了，表现是"按 W 往旁边走"——headless 里根本看不出来，
##    只能靠断言守住，所以必须能被 `--script` 自检直接调用。
## 2. `--script` 模式下 autoload 不是全局标识符，preload 一个引用了
##    GameState 的脚本（比如 player.gd）会直接解析失败、进程无声退出。
##    所以这段逻辑不能留在 player.gd 里。
##
## 相机永远待在玩家的 (sin yaw, ·, cos yaw) 一侧，因此：
##   画面里的前方 = −(sin yaw, 0, cos yaw)
##   画面里的右方 =  (cos yaw, 0, −sin yaw)
## yaw = 0 时前方 = (0,0,−1)、右方 = (1,0,0)，和原来的世界坐标一致——
## 也就是说没转视角时手感完全不变，只有转了视角才会跟着转。


## input 是 Input.get_vector("move_left","move_right","move_forward","move_back")
## 的返回值：按 W → (0,−1)，按 D → (1,0)。
static func dir_from_input(input: Vector2, yaw: float) -> Vector3:
	if input.length() < 0.001:
		return Vector3.ZERO
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return (right * input.x + fwd * (-input.y)).normalized()


## 朝向角：让模型自己的 −Z 轴指向 dir（Godot 里模型默认朝 −Z）。
static func yaw_from_dir(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
