extends SceneTree
## 蛋品曲线自检：品质是否真的随跑道长度变稀有。
##
## 用法：
##   Godot --headless --script res://tools/quality_test.gd
##
## 为什么需要它：品质曲线错了**不会报任何错**，
## 表现只是"玩家感觉不到跑深了有什么用"——这种 bug 靠读代码和跑场景都发现不了。
## 只能靠统计断言：跑得越深，平均品质必须单调上升。
##
## 纯 CreatureDB 逻辑，不依赖 autoload，所以能直接 --script 跑。

const DB := preload("res://scripts/data/creature_db.gd")

const SAMPLES := 20000
const DISTS := [0.0, 500.0, 1000.0, 2000.0, 3000.0, 4000.0]


func _initialize() -> void:
	var bad := 0

	# ① 概率必须归一：每个距离下四个品质的概率加起来要是 1
	print("[蛋品自检] ① 概率归一性")
	for d in DISTS:
		var s := 0.0
		for i in range(DB.QUALITIES.size()):
			s += DB.quality_chance(i, float(d))
		if absf(s - 1.0) < 0.0001:
			print("  ✓ %.0f m 概率合计 %.4f" % [float(d), s])
		else:
			print("  ✗ %.0f m 概率合计 %.4f（应为 1.0）" % [float(d), s])
			bad += 1

	# ② 实测分布 + 平均品质倍率，必须随距离单调上升
	print("[蛋品自检] ② 实测分布（每档抽 %d 次）" % SAMPLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260912
	var avgs: Array = []
	for d in DISTS:
		var counts := [0, 0, 0, 0]
		var mult_sum := 0.0
		for _i in range(SAMPLES):
			var q: Dictionary = DB.roll_quality(rng, float(d))
			var qi := DB.quality_index(str(q.get("name", "普通")))
			counts[qi] += 1
			mult_sum += float(q.get("mult", 1.0))
		var avg := mult_sum / float(SAMPLES)
		avgs.append(avg)
		var cells: Array = []
		for i in range(4):
			cells.append("%s %.1f%%" % [str(DB.QUALITIES[i]["name"]),
				float(counts[i]) / float(SAMPLES) * 100.0])
		print("  %5.0f m ｜ %s ｜ 平均倍率 ×%.3f" % [float(d), " ／ ".join(cells), avg])

	for i in range(1, avgs.size()):
		if float(avgs[i]) > float(avgs[i - 1]):
			print("  ✓ 平均倍率上升：%.0f m ×%.3f → %.0f m ×%.3f" % [
				float(DISTS[i - 1]), float(avgs[i - 1]),
				float(DISTS[i]), float(avgs[i])])
		else:
			print("  ✗ 平均倍率没上升：%.0f m ×%.3f → %.0f m ×%.3f" % [
				float(DISTS[i - 1]), float(avgs[i - 1]),
				float(DISTS[i]), float(avgs[i])])
			bad += 1

	# ③ 两端必须明显不同，否则"跑深有回报"这件事玩家感受不到
	var gain := float(avgs[avgs.size() - 1]) / maxf(0.001, float(avgs[0]))
	if gain > 1.3:
		print("[蛋品自检] ③ 起点 → 满距离 平均倍率提升 ×%.2f（够明显）" % gain)
	else:
		print("[蛋品自检] ③ 起点 → 满距离 只提升 ×%.2f —— 差距太小，玩家感受不到" % gain)
		bad += 1

	# ④ 越界距离要能兜住（负数 / 超长），不能崩也不能给出怪值
	var q_neg: Dictionary = DB.roll_quality(rng, -999.0)
	var q_over: Dictionary = DB.roll_quality(rng, 999999.0)
	print("[蛋品自检] ④ 越界距离：-999 m → %s ｜ 999999 m → %s"
		% [str(q_neg.get("name", "?")), str(q_over.get("name", "?"))])

	if bad == 0:
		print("[蛋品自检] 全部通过")
	else:
		print("[蛋品自检] %d 项有问题" % bad)
	quit()
