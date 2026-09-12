extends SceneTree
## 建模自检：十阶怪各构建一次，打印网格数 / 动画挂钩。
##
## 为什么需要它：`--jump 20000 --diag` 看着覆盖了高阶，其实怪物列表在传送之前
## 就生成完了，T8/T9/T10 的建模代码压根没跑到。这个脚本才是真的逐阶构建。
##
## 用法：
##   Godot --headless --script res://tools/model_test.gd
##
## 注意：这里直接测 CreatureModel.build()，不实例化 creature.tscn。
## 因为 --script 模式不会把 autoload 注册成全局标识符，creature.gd 里的
## GameEvents 会编译失败。建模模块只依赖 CreatureDB，绕得开。
## creature.gd 那边的接线由正常的 headless 自检覆盖。

const CreatureDB := preload("res://scripts/data/creature_db.gd")
const CreatureModel := preload("res://scripts/run/creature_model.gd")


func _initialize() -> void:
	print("[建模自检] 逐阶构建十套身体蓝图")
	var total := 0
	var worst := 0
	var worst_tier := 0
	for t in range(1, 11):
		var m: Dictionary = CreatureModel.build(t)
		var root: Node3D = m.get("root") as Node3D
		if root == null:
			print("  T%-2d 构建失败：root 为空" % t)
			continue
		add_child_to_root(root)
		# owned 必须传 false：运行时 add_child 不会设 owner，传 true 会一个都找不到
		var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
		var legs: Array = m.get("legs") as Array
		var segs: Array = m.get("segs") as Array
		var wings: Array = m.get("wings") as Array
		var halo: Node = m.get("halo") as Node
		var floaty: bool = bool(m.get("float", false))
		var d: Dictionary = CreatureDB.tier_data(t)
		var n := meshes.size()
		total += n
		if n > worst:
			worst = n
			worst_tier = t
		print("  T%-2d %-5s 顶高 %.1f ｜ 网格 %2d ｜ 腿 %d ｜ 体节 %d ｜ 翼 %d ｜ 光环 %s ｜ 浮游 %s"
				% [t, str(d.get("name", "?")), CreatureModel.top_of(t), n,
				   legs.size(), segs.size(), wings.size(),
				   "有" if halo != null else "—", "是" if floaty else "否"])
	print("[建模自检] 合计网格 %d，最重的是 T%d（%d 个）" % [total, worst_tier, worst])
	if worst > 40:
		print("[建模自检] 警告：单只怪网格超 40，同屏几十只时留意 draw call")
	quit()


func add_child_to_root(n: Node) -> void:
	root.add_child(n)
