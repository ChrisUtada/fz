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

## 奖励（默认 fallback；阶段 2 起由 CustomerData.apply_data 随机注入）
@export var gold_reward: int = 100
@export var inspiration_reward: int = 10

## 数据模型引用（Resource 驱动）。场景通过 apply_data 消费，控制外观与奖励。
var _data: CustomerData
var _data_pending := false

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
	# 若 apply_data 在 _ready 之前被调用（节点尚未进入场景树），延迟到这里落地外观
	if _data_pending:
		_apply_visuals()


## 由外部直接注入本次订单奖励（兼容/覆盖用）
func set_reward(gold: int, inspiration: int) -> void:
	gold_reward = gold
	inspiration_reward = inspiration


## 数据驱动入口：消费 CustomerData 资源，由场景控制外观与奖励。
## 可在 add_child 之前或之后调用；节点未就绪时延迟到 _ready 落地。
func apply_data(data: CustomerData) -> void:
	if data == null:
		return
	_data = data
	if is_inside_tree() and is_instance_valid(_sprite):
		_apply_visuals()
	else:
		_data_pending = true


## 把 CustomerData 变现为外观 + 抽取奖励（场景控制外观的核心）
func _apply_visuals() -> void:
	if _data == null:
		return
	if _data.texture != null:
		_sprite.texture = _data.texture
	_sprite.region_enabled = true
	_sprite.region_rect = _data.region_rect
	_sprite.scale = _data.base_scale
	_roll_reward()


## 从 CustomerData 的奖励区间内随机抽取值（OCP：新增奖励规则只改这里）
func _roll_reward() -> void:
	if _data == null:
		return
	var g := randi_range(_data.gold_reward_min, maxi(_data.gold_reward_max, _data.gold_reward_min))
	var i := randi_range(_data.inspiration_reward_min, maxi(_data.inspiration_reward_max, _data.inspiration_reward_min))
	set_reward(g, i)


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
	_complete_order()


## 鼠标交互：本节点自行判断抓取/拖动/轻点完成（物理点查询命中判定）
func _input(event: InputEvent) -> void:
	if _completed:
		return
	# 覆盖层弹窗打开时不抢占点击：否则本顾客会用 set_input_as_handled 吃掉落在其
	# 身上的点击，导致弹窗按钮（如「去商城」）偶发点不动。
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
