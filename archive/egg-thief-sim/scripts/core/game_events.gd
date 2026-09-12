extends Node
## 全局信号总线 —— 各系统之间只通过信号通信，不互相持有引用

signal alert_changed(value: float, ratio: float)
signal alert_maxed()
signal egg_grab_started(egg: Node2D)
signal egg_grabbed(egg: Node2D)
signal egg_dropped(egg: Node2D)
signal guard_spotted_player(guard: Node2D)
signal guard_lost_player(guard: Node2D)
signal player_caught()
signal escaped(egg_count: int, flawless: bool)
signal exit_reached()
