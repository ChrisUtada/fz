extends Node2D
## Heart · 红心跳出效果
##
## 组成：Sprite2D（在 heart.tscn 中定义，从 cat.png 裁剪出心形图标）
##
## 用法：实例化后加入场景树即可自动播放并自毁
##   var h := preload("res://scenes/heart.tscn").instantiate()
##   parent.add_child(h)
##   h.global_position = spawn_pos  # 跳出位置
##
## 动画：上浮 → 淡出 → queue_free

const FLOAT_UP := -30.0                           ## 上浮偏移量（相对当前位置）
const DURATION := 1.0                              ## 总动画时长


func _ready() -> void:
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
