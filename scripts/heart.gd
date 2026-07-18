extends Node2D
## Heart · 红心跳出效果（调试版：ColorRect）
##
## 用法：实例化后加入场景树即可自动播放并自毁
##   var h := preload("res://scenes/heart.tscn").instantiate()
##   parent.add_child(h)
##   h.global_position = spawn_pos
##
## 动画：上浮 → 淡出 → queue_free

const FLOAT_UP := -30.0
const DURATION := 1.0
const SIZE := 20.0


func _ready() -> void:
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	rect.color = Color(1, 0, 0, 1)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)

	_play_animation()


func _play_animation() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", FLOAT_UP, DURATION * 0.5)\
		.as_relative()\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, DURATION * 0.5)\
		.set_delay(DURATION * 0.3)
	tween.tween_callback(queue_free)
