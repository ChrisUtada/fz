extends Node2D
## Customer · 顾客节点（组合式）
## 职责单一：展示角色、检测点击、发射订单完成信号。
## 原则：
##   - 组合：本节点 = Sprite2D + Area2D（点击区），不继承任何基类
##   - 低耦合：只发 order_completed 信号，不引用 GameManager / HUD / Spawner
##   - 数据注入：奖励金额由外部通过 @export 或 set 设置

signal order_completed(reward: Dictionary)  ## reward 包含 { "gold": int, "inspiration": int }

@export var reward_gold: int = 100
@export var reward_inspiration: int = 10
@export var click_scale_bounce: float = 1.15
@export var fade_duration: float = 0.4

var _is_completed := false


func _ready() -> void:
	# 入场动画：从透明渐入
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 1.0, 0.5)


func _on_click_area_input_event(
	_viewport: Node, event: InputEvent, _shape_idx: int
) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _is_completed:
		return
	_complete_order()


func _complete_order() -> void:
	_is_completed = true

	# 点击反馈：缩放弹跳
	var tween := create_tween()
	tween.set_parallel(true)
	# 弹跳
	tween.tween_property(self, "scale", Vector2(click_scale_bounce, click_scale_bounce), 0.1)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15).set_delay(0.1)
	# 淡出
	tween.chain().tween_property(self, "modulate:a", 0.0, fade_duration)

	# 发射订单完成信号 —— 外部监听者负责后续逻辑
	order_completed.emit({
		"gold": reward_gold,
		"inspiration": reward_inspiration,
	})

	# 动画完成后自毁
	await get_tree().create_timer(fade_duration + 0.2).timeout
	queue_free()


func set_reward(gold_amount: int, inspiration_amount: int) -> void:
	reward_gold = gold_amount
	reward_inspiration = inspiration_amount
