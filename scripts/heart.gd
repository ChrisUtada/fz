extends Node2D
## Heart · 红心跳出效果
##
## 场景 heart.tscn 内已含 Sprite2D（cat.png 的红心区域），本脚本只负责动画。
## 动画链：弹出(scale 0→1.3) → 回弹(→1.0) → 上浮+淡出 → queue_free
##
## ⚠️ 关键：queue_free 必须在动画链【末尾】顺序执行，
##    不能放进 set_parallel(true) 的并行组（否则实例化即自毁，玩家看不见）。

const POP_TIME := 0.15                          ## 弹出时长
const POP_SCALE := 1.3                          ## 弹出峰值
const SETTLE_TIME := 0.08                       ## 回弹时长
const FLOAT_DIST := -42.0                       ## 上浮距离（负=向上）
const FADE_TIME := 0.45                         ## 上浮+淡出时长


func _ready() -> void:
	# 初始不可见，由弹出动画放大显现
	scale = Vector2.ZERO
	_play_animation()


func _play_animation() -> void:
	var tween := create_tween()

	# 1) 弹出：scale 0 → 1.3（BACK 缓动产生弹跳感）
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(POP_SCALE, POP_SCALE), POP_TIME)

	# 2) 回弹到 1.0
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, SETTLE_TIME)

	# 3) 上浮 + 淡出（并行）
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", FLOAT_DIST, FADE_TIME).as_relative()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)

	# 4) 自毁：取消并行，tween_callback 接在动画链末尾顺序执行
	#    （若放在并行组里会无延迟立即调用 → 红心瞬间消失）
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
