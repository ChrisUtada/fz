extends TextureButton
## Customer · 顾客节点（组合式：以 TextureButton 作为可点击精灵）
## 职责单一：展示角色、检测点击、发射订单完成信号。
## 原则：
##   - 组合/地道做法：直接以 TextureButton 承载贴图与点击，命中框=整张贴图，
##     点击小人任意位置都能命中；且 Control 默认 mouse_filter=STOP 会吞噬输入，
##     天然避免与主窗口拖拽逻辑冲突（点击顾客不会误拖窗口）。
##   - 低耦合：只发 order_completed 信号，不引用 GameManager / HUD / Spawner
##   - 数据注入：奖励金额由外部通过 @export 或 set_reward() 设置

signal order_completed(reward: Dictionary)  ## reward 包含 { "gold": int, "inspiration": int }

@export var reward_gold: int = 100
@export var reward_inspiration: int = 10
@export var click_scale_bounce: float = 1.15
@export var fade_duration: float = 0.4

const BASE_SCALE: float = 0.38  ## 与 .tscn 中 scale 保持一致

var _is_completed := false


func _ready() -> void:
	# 入场动画：从透明渐入
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 1.0, 0.5)


func _on_button_down() -> void:
	if _is_completed:
		return
	_complete_order()


func _complete_order() -> void:
	_is_completed = true
	disabled = true  ## 防重复点击（同时阻止拖拽误触发）

	var bounce := BASE_SCALE * click_scale_bounce
	# 缩放弹跳（顺序：放大 → 回弹），独立于淡出
	var t_bounce := create_tween()
	t_bounce.tween_property(self, "scale", Vector2(bounce, bounce), 0.1)
	t_bounce.tween_property(self, "scale", Vector2(BASE_SCALE, BASE_SCALE), 0.15)
	# 淡出（稍延迟，与回弹并行）
	var t_fade := create_tween()
	t_fade.tween_property(self, "modulate:a", 0.0, fade_duration).set_delay(0.1)

	# 发射订单完成信号 —— 外部监听者负责后续逻辑（奖励/编排下一轮）
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
