extends Node2D
## Customer · 顾客（组合节点 / Node2D）
##
## 组成：
##   - Sprite2D(char.png)  角色外观（region 裁剪出小人本体，region_enabled=true）
##   - Area2D(HitArea) + CollisionShape2D  碰撞区域，用于物理点查询命中检测
##
## 鼠标交互（基于物理点查询 + _input 三态）：
##   - 左键按下且落在 HitArea 碰撞框内 → 进入"抓取"状态（grab）
##   - 按住并移动超过阈值 → 拖动角色跟随光标（drag）
##   - 松开：若发生过拖动 → 仅放置（不完成订单）；若几乎未移动（轻点）→ 完成订单
##   命中判定基于 Area2D 碰撞形状，与屏幕显示严格对齐
##
## 原则（工程规范）：
##   - 低耦合：仅通过信号对外通信（order_completed），不直接引用 GameManager 等外部模块
##   - 高内聚：本节点只负责"角色表现 + 命中判定 + 自身拖拽/动画"
##   - 可扩展：基于 Node2D，后续可直接挂 AnimationPlayer / AnimationTree 做换装、动作、状态机

signal order_completed(reward: Dictionary)

const BASE_SCALE := Vector2(1.0, 1.0)     ## 角色显示缩放
const CLICK_BOUNCE := 1.25                ## 点击弹跳倍率
const SPAWN_FADE := 0.4                   ## 入场渐入时长
const FADE_DURATION := 0.4                ## 离场淡出时长
const DRAG_THRESHOLD := 4.0               ## 拖动判定阈值（像素）

## 奖励（由 Main 通过 set_reward 注入）
@export var gold_reward: int = 100
@export var inspiration_reward: int = 10

var _completed := false

## 拖拽/抓取状态
var _grabbed := false
var _dragging := false
var _moved := false
var _press_global := Vector2.ZERO
var _grab_offset := Vector2.ZERO

@onready var _sprite: Sprite2D = $Sprite
@onready var _hit_area: Area2D = $HitArea


func _ready() -> void:
	_sprite.scale = BASE_SCALE
	scale = Vector2.ONE
	modulate.a = 0.0
	_play_spawn_animation()


## 由 Main 注入本次订单奖励
func set_reward(gold: int, inspiration: int) -> void:
	gold_reward = gold
	inspiration_reward = inspiration


## 命中测试：global_pos 是否落在 HitArea 碰撞形状内
func contains_point(global_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_pos
	query.collision_mask = 2
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var results := space.intersect_point(query)
	for r in results:
		if r.collider == _hit_area:
			return true
	return false


## 由轻点触发完成订单
func on_clicked() -> void:
	if _completed:
		return
	print("[cust] tap -> on_clicked reward=", gold_reward, "/", inspiration_reward)
	_complete_order()


## 鼠标交互：本节点自行判断抓取/拖动/轻点完成（物理点查询命中判定）
func _input(event: InputEvent) -> void:
	if _completed:
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
				if _moved:
					print("[cust] dropped at ", global_position)
				else:
					on_clicked()
				_grabbed = false
				_dragging = false

	elif event is InputEventMouseMotion and _grabbed:
		var gp := get_global_mouse_position()
		if not _dragging and gp.distance_to(_press_global) > DRAG_THRESHOLD:
			_dragging = true
			_moved = true
		if _dragging:
			global_position = gp + _grab_offset


func _play_spawn_animation() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, SPAWN_FADE)


func _complete_order() -> void:
	_completed = true
	order_completed.emit({"gold": gold_reward, "inspiration": inspiration_reward})

	var t_bounce := create_tween()
	t_bounce.tween_property(self, "scale", Vector2(CLICK_BOUNCE, CLICK_BOUNCE), 0.1)
	t_bounce.tween_property(self, "scale", Vector2.ONE, 0.15)

	var t_fade := create_tween()
	t_fade.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	t_fade.tween_callback(queue_free)
