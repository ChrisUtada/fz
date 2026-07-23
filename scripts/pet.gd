extends Node2D
## Pet · 宠物（猫，Node2D 组合节点）
##
## 组成：
##   - Sprite2D(cat.png)  猫咪外观（region 裁剪出猫本体）
##   - Area2D(ClickArea) + CollisionShape2D  碰撞区域，用于物理点查询命中检测
##
## 行为：
##   1. 行走：按选定方向匀速移动，带轻微上下浮动（正弦波），到达屏幕边缘后消失
##   2. 拖拽：左键按住可自由拖动放置（拖拽时暂停行走）
##   3. 点击：轻点（未拖动）→ 红心跳出反馈
##
## 鼠标交互：与 Customer 一致 —— 物理点查询 + _input 三态

signal pet_tapped

const BASE_SCALE := Vector2(1.0, 1.0)

## 行走参数
@export var walk_speed: float = 60.0
@export var bob_amplitude: float = 4.0
@export var bob_frequency: float = 3.0
@export var edge_margin: float = 50.0

var _direction := Vector2.RIGHT
var _walk_time := 0.0
var _alive := true

## 数据模型引用（Resource 驱动）。场景通过 apply_data 消费，控制外观与行走参数。
var _data: PetData
var _data_pending := false

## 拖拽/抓取状态
var _grabbed := false
var _dragging := false
var _moved := false
var _press_global := Vector2.ZERO
var _grab_offset := Vector2.ZERO

@onready var _sprite: Sprite2D = $Sprite
@onready var _click_area: Area2D = $ClickArea


func _ready() -> void:
	_sprite.scale = BASE_SCALE
	scale = Vector2.ONE
	modulate.a = 0.0
	_play_spawn_animation()
	# 先落地外观与行走参数（含 edge_margin），再选方向/定位。
	# 否则 _pick_direction 用默认 edge_margin=50 定位，若 PetData.edge_margin<50，
	# 下一帧 _check_bounds 可能立即判出界 → 出生即瞬灭。
	if _data_pending:
		_apply_visuals()
	_pick_direction()


func _process(delta: float) -> void:
	if not _alive:
		return
	if _grabbed:
		return

	_walk_time += delta
	position += _direction * walk_speed * delta
	position.y += sin(_walk_time * TAU * bob_frequency) * bob_amplitude * delta * 10.0

	_check_bounds()


# ═══════════════════ 命中测试 & 点击 ═══════════════════

## global_pos 是否落在 ClickArea 碰撞形状内
func contains_point(global_pos: Vector2) -> bool:
	return Utils.point_in_area(global_pos, _click_area, 4)


## 由轻点触发：弹出红心
func on_tapped() -> void:
	if not _alive:
		return
	pet_tapped.emit()
	_spawn_heart()


## 数据驱动入口：消费 PetData 资源，由场景控制外观与行走参数。
## 可在 add_child 之前或之后调用；节点未就绪时延迟到 _ready 落地。
func apply_data(data: PetData) -> void:
	if data == null:
		return
	_data = data
	if is_inside_tree() and is_instance_valid(_sprite):
		_apply_visuals()
	else:
		_data_pending = true


## 把 PetData 变现为外观 + 行走参数（场景控制外观/行为的核心）
func _apply_visuals() -> void:
	if _data == null:
		return
	if _data.texture != null:
		_sprite.texture = _data.texture
	_sprite.region_enabled = true
	_sprite.region_rect = _data.region_rect
	_sprite.scale = _data.base_scale
	# 行走参数从数据覆盖 @export 默认值（OCP：改数据不改代码）
	walk_speed = _data.walk_speed
	bob_amplitude = _data.bob_amplitude
	bob_frequency = _data.bob_frequency
	edge_margin = _data.edge_margin


## 鼠标交互（抓取/拖动/轻点）
func _input(event: InputEvent) -> void:
	if not _alive:
		return
	# 覆盖层弹窗打开时不抢占点击（同 customer.gd，避免吃掉弹窗按钮的点击）。
	if GameManager.is_modal_open():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var gp := get_global_mouse_position()
			if contains_point(gp):
				_grabbed = true
				_dragging = false
				_moved = false
				_press_global = gp
				_grab_offset = global_position - gp
				get_viewport().set_input_as_handled()
		else:
			if _grabbed:
				if not _moved:
					on_tapped()
				_grabbed = false
				_dragging = false

	elif event is InputEventMouseMotion and _grabbed:
		var gp := get_global_mouse_position()
		if not _dragging and Utils.exceeds_drag_threshold(gp, _press_global):
			_dragging = true
			_moved = true
		if _dragging:
			global_position = gp + _grab_offset


# ═══════════════════ 内部方法 ═══════════════════

func _pick_direction() -> void:
	if randf() > 0.5:
		_position_at_edge("left")
		_direction = Vector2.RIGHT
	else:
		_position_at_edge("right")
		_direction = Vector2.LEFT


func _position_at_edge(side: String) -> void:
	var win_size := get_window().size
	match side:
		"left":
			position.x = -edge_margin
			position.y = randf_range(edge_margin, win_size.y - edge_margin)
		"right":
			position.x = win_size.x + edge_margin
			position.y = randf_range(edge_margin, win_size.y - edge_margin)
		"top":
			position.x = randf_range(edge_margin, win_size.x - edge_margin)
			position.y = -edge_margin
		"bottom":
			position.x = randf_range(edge_margin, win_size.x - edge_margin)
			position.y = win_size.y + edge_margin


func _check_bounds() -> void:
	var win_size := get_window().size
	var margin := edge_margin
	if (position.x < -margin or position.x > win_size.x + margin or
		position.y < -margin or position.y > win_size.y + margin):
		_die()


func _die() -> void:
	if not _alive:
		return
	_alive = false
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)


func _spawn_heart() -> void:
	var heart_scene := preload("res://scenes/heart.tscn")
	var heart: Node2D = heart_scene.instantiate()
	heart.position = Vector2(0, -30)
	add_child(heart)


func _play_spawn_animation() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.35)
