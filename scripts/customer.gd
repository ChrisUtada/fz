extends Node2D
## Customer · 顾客（阶段 4.5 改造为自主购物者）
##
## 自主行为：出现后随机走向「有货的展架槽」购买，付金币后消失；
## 展架空 / 全售罄则逛逛后离开（不给金币，避免死锁）。
##
## 视觉由 CustomerData 驱动（apply_data）；行为与「订单奖励」解耦——
## 金币由 GameManager.sell_from_rack 结算。本节点离开时 emit order_completed({})
## 仅用于驱动 Main 的「下一个顾客」生成循环（reward 为占位，金币已在 sell_from_rack 结算）。

signal order_completed(reward: Dictionary)

const SPAWN_FADE := 0.4
const FADE_DURATION := 0.4
const SPEED := 70.0            # 行走速度 px/s
const ARRIVE_DIST := 8.0       # 到达判定距离

@export var gold_reward: int = 0        # 保留兼容（不再用于点击结算）
@export var inspiration_reward: int = 0

var _data: CustomerData
var _data_pending := false

var _state: String = "idle"     # idle | shopping | browsing | leaving
var _target_slot: int = -1
var _rack_target: Vector2 = Vector2.ZERO
var _has_target := false
var _leaving := false

@onready var _sprite: Sprite2D = $Sprite
@onready var _hit_area: Area2D = $HitArea


func _ready() -> void:
	_sprite.scale = Vector2.ONE
	scale = Vector2.ONE
	modulate.a = 0.0
	_play_spawn_animation()
	if _data_pending:
		_apply_visuals()
	# 行为决策延迟到首帧 _process：此时 Main 已通过 set_rack_target 注入展架坐标，
	# 避免在 _ready 阶段（目标尚未设置）误判为「逛逛离开」。


## 由外部直接注入本次订单奖励（保留兼容，本阶段不再用于点击结算）
func set_reward(gold: int, inspiration: int) -> void:
	gold_reward = gold
	inspiration_reward = inspiration


## 数据驱动入口：消费 CustomerData 资源，由场景控制外观。
func apply_data(data: CustomerData) -> void:
	if data == null:
		return
	_data = data
	if is_inside_tree() and is_instance_valid(_sprite):
		_apply_visuals()
	else:
		_data_pending = true


func _apply_visuals() -> void:
	if _data == null:
		return
	if _data.texture != null:
		_sprite.texture = _data.texture
	_sprite.region_enabled = true
	_sprite.region_rect = _data.region_rect
	_sprite.scale = _data.base_scale


## 由 Main 在生成时传入展架世界坐标（顾客走向此处购买）
func set_rack_target(pos: Vector2) -> void:
	_rack_target = pos
	_has_target = true


## 决定本次行为：有货槽→随机选一个去购买；无货→逛逛离开
func _decide_behavior() -> void:
	if not _has_target:
		_state = "browsing"
		return
	var stocked := GameManager.get_rack_slots_with_stock()
	if stocked.is_empty():
		_state = "browsing"
	else:
		_state = "shopping"
		_target_slot = stocked.pick_random()


func _process(delta: float) -> void:
	if _state == "idle":
		_decide_behavior()
		return
	if _leaving:
		return
	# 走向展架
	if _has_target and global_position.distance_to(_rack_target) > ARRIVE_DIST:
		var dir := (_rack_target - global_position).normalized()
		global_position += dir * SPEED * delta
		return
	# 到达：结算
	if _state == "shopping":
		var price := GameManager.sell_from_rack(_target_slot)
		if price >= 0:
			_bounce()
		_leave()
	elif _state == "browsing":
		_leave()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	_state = "leaving"
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	t.tween_callback(queue_free)
	# 维持「生成循环」：通知 Main 安排下一个顾客（reward 仅占位，金币已在 sell_from_rack 结算）
	order_completed.emit({"gold": 0, "inspiration": 0})


func _bounce() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.25, 1.25), 0.1)
	t.tween_property(self, "scale", Vector2.ONE, 0.15)


func _play_spawn_animation() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, SPAWN_FADE)


## 命中测试：global_pos 是否落在 HitArea 碰撞形状内（供 Main 拖窗口守卫）
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
