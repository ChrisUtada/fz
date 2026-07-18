extends Node2D
## Heart · 红心跳出效果（纯几何，无需纹理资产）
##
## 用法：实例化后加入场景树即可自动播放并自毁
##   var h := preload("res://scenes/heart.tscn").instantiate()
##   parent.add_child(h)
##   h.global_position = spawn_pos  # 跳出位置
##
## 动画：缩放从 0 弹到 1.3 → 上浮 → 淡出 → queue_free

const HEART_COLOR := Color(1, 0.25, 0.35, 1)   ## 鲜红偏粉
const POP_SCALE := 1.3                            ## 弹跳最大缩放
const FLOAT_DIST := 40.0                          ## 上浮像素距离
const DURATION := 0.6                             ## 总动画时长


func _ready() -> void:
	_build_heart_shape()
	_play_animation()


## 用参数方程构建心形多边形点集（经典心形曲线）
func _build_heart_shape() -> void:
	var points := PackedVector2Array()
	const SEGMENTS := 32
	for i in range(SEGMENTS + 1):
		var t := (TAU / SEGMENTS) * i
		# 心形参数方程（归一化到 ~[-16, 16] x [-16, 12]）
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		# 缩放到合适大小 (~30px 宽)
		points.append(Vector2(x, y) * 0.9)

	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = HEART_COLOR
	poly.antialiased = true
	add_child(poly)


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
