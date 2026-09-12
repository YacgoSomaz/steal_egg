extends Node
## 全局信号总线

signal egg_stolen(tier: int, egg_name: String)
signal creature_woke(creature: Node3D)
signal player_caught(lost_egg: Dictionary)
signal escaped(egg_count: int)
signal coins_changed(value: float)
signal penalty_changed(value: float)
signal grabbed_progress(ratio: float)
