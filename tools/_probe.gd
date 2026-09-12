extends SceneTree
## 最小冒烟测试：确认 `--script` 模式能跑起来。
##
## 用法：
##   Godot --headless --script res://tools/_probe.gd
##
## 留着它的理由：建模自检（model_test.gd）也是 --script 模式跑的，
## 一旦它哪天连 "hello" 都打不出来，你就知道是 Godot 的调用方式变了，
## 而不是建模代码坏了。排障时先跑这个，能省掉一次误判。


func _initialize() -> void:
	print("[冒烟] --script 模式正常")
	quit()
