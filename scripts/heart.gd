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
## 动画：缩放从 0 弹到 1.3 → 上浮 → 淡出 → queue_free

const POP_SCALE := 1.3                            ## 弹跳最大缩放
const FLOAT_DIST := 40.0                          ## 上浮像素距离
const DURATION := 0.6                             ## 总动画时长


func _ready() -> void:
	_play_animation()


func _play_animation() -> void:
	scale = Vector2.ZERO
	modulate.a = 1.0

	var tween := create_tween()
	# ① 弹跳放大
	tween.tween_property(self, "scale", Vector2(POP_SCALE, POP_SCALE), 0.15)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# ② 回弹 + 上浮 + 淡出（并行）
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)
	tween.tween_property(self, "position:y", -FLOAT_DIST, DURATION - 0.25)
	tween.tween_property(self, "modulate:a", 0.0, DURATION - 0.15)\
		.set_delay(0.15)
	# ③ 自毁
	tween.tween_callback(queue_free)
