extends Node3D
## 速度特效：让「快」被看见，而不是只写在数字里
##
## 内部速度其实只涨了 10 倍出头，但速度线的密度／长度／亮度、脚下的尘土、
## 相机的 FOV 和抖动一起上，感知上能放大到二三十倍。
## 数值可以虚假化，感受不能撒谎——这就是这套特效存在的理由。
##
## 用 CPUParticles3D：粒子数不多（100 出头），CPU 版在任何渲染后端都稳，
## 不必赌 compatibility renderer 支不支持 compute。
## 注意 CPU 版用的是扁平属性（direction / initial_velocity_min …），
## 没有 process_material，也没有 align_y_to_velocity（只有 align_y）。

const SPEED_REF := 60.0      # 到这个速度特效拉满
const LINE_AMOUNT := 64
const DUST_AMOUNT := 40

var _lines: CPUParticles3D
var _dust: CPUParticles3D


func _ready() -> void:
	_lines = _make_lines()
	add_child(_lines)
	_dust = _make_dust()
	add_child(_dust)


## 每帧由 player 调用。moving=false 时立刻收干净（站定偷蛋时不该有速度线）
func update(speed: float, moving: bool) -> void:
	if _lines == null or _dust == null:
		return
	var r := clampf(speed / SPEED_REF, 0.0, 1.3)

	# amount 必须 ≥ 1：低速时算出来是 0，Godot 会每帧报
	# "Amount of particles must be greater than 0"。用 emitting 去关，不用 amount 归零。
	_lines.amount = maxi(1, int(float(LINE_AMOUNT) * clampf(r * 1.4 - 0.15, 0.0, 1.0)))
	_lines.emitting = moving and r > 0.12
	_lines.initial_velocity_min = 16.0 + speed * 1.5
	_lines.initial_velocity_max = 28.0 + speed * 2.3
	_lines.scale_amount_min = 0.5 + r
	_lines.scale_amount_max = 1.2 + r * 2.8

	_dust.amount = maxi(1, int(float(DUST_AMOUNT) * clampf(r * 1.1, 0.15, 1.0)))
	_dust.emitting = moving
	_dust.initial_velocity_min = 2.0 + speed * 0.10
	_dust.initial_velocity_max = 5.0 + speed * 0.22


## 向后飞的细长条 —— 速度感的主力
func _make_lines() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = LINE_AMOUNT
	p.lifetime = 0.5
	p.emitting = false
	p.local_coords = false                     # 世界坐标：粒子留在原地，形成拖尾
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(3.2, 2.4, 1.6)
	p.direction = Vector3(0.0, 0.0, 1.0)       # 玩家往 −Z 跑，线就往 +Z 甩
	p.spread = 14.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 40.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 2.0
	p.damping_min = 0.0
	p.damping_max = 0.0
	p.particle_flag_align_y = true             # Y 轴是长边，对齐速度后被拉成一条线

	# Y 轴长、X 轴极窄：一条线
	var qm := QuadMesh.new()
	qm.size = Vector2(0.055, 1.0)
	p.mesh = qm

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	p.material_override = mat
	return p


## 脚下扬起的尘土：低速时几乎看不见，高速时一片黄烟
func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = DUST_AMOUNT
	p.lifetime = 0.7
	p.emitting = false
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.55
	p.direction = Vector3(0.0, 1.0, 0.7)
	p.spread = 38.0
	p.gravity = Vector3(0.0, -7.0, 0.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.75

	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	p.mesh = sm

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.80, 0.74, 0.60, 0.42)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = mat
	return p
