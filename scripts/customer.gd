extends Node2D
## Customer · 顾客（组合节点 / Node2D）
##
## 组成：
##   - Sprite2D(char.png)  角色外观（region 裁剪出小人本体，region_enabled=true）
##   - Area2D + CollisionShape2D  预留：阶段3 的"重叠/互动区"检测（本阶段不用于点击）
##
## 鼠标交互（本节点自行判断，单一几何真相在 contains_point）：
##   - 左键按下且落在角色本体 → 进入"抓取"状态（grab）
##   - 按住并移动超过阈值 → 拖动角色跟随光标（drag）
##   - 松开：若发生过拖动 → 仅放置（不完成订单）；若几乎未移动（轻点）→ 完成订单
##   点击命中判定基于 Sprite 真实渲染矩形（region + scale），与屏幕显示严格对齐，
##   保证"只有点中角色本体才响应"，避免点空白处或窗口其它位置误触发。
##
## 原则（工程规范）：
##   - 低耦合：仅通过信号对外通信（order_completed），不直接引用 GameManager 等外部模块
##   - 高内聚：本节点只负责"角色表现 + 命中判定 + 自身拖拽/动画"
##   - 可扩展：基于 Node2D，后续可直接挂 AnimationPlayer / AnimationTree 做换装、动作、状态机

signal order_completed(reward: Dictionary)

const BASE_SCALE := Vector2(1.0, 1.0)     ## 角色显示缩放（region 仅裁出小人 76x154，1.0 即实际像素）
const CLICK_BOUNCE := 1.25                ## 点击弹跳倍率（相对 Node2D scale=1）
const SPAWN_FADE := 0.4                   ## 入场渐入时长
const FADE_DURATION := 0.4                ## 离场淡出时长
const CLICK_PADDING := 24.0               ## 命中框外扩容差（像素），提升点击手感但不溢出本体
const DRAG_THRESHOLD := 4.0               ## 拖动判定阈值（像素）：超过才算"拖动"，否则视为轻点

## 奖励（由 Main 通过 set_reward 注入，依赖注入）
@export var gold_reward: int = 100
@export var inspiration_reward: int = 10

var _completed := false

## 拖拽/抓取状态
var _grabbed := false                     ## 本次左键按下是否点中本角色
var _dragging := false                    ## 是否已进入拖动模式
var _moved := false                       ## 本次按下后是否发生过有效拖动
var _press_global := Vector2.ZERO         ## 按下时的全局光标位置
var _grab_offset := Vector2.ZERO          ## 角色原点相对光标的偏移，保持抓取点不跳

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	_sprite.scale = BASE_SCALE
	scale = Vector2.ONE
	modulate.a = 0.0
	_play_spawn_animation()


## 由 Main 注入本次订单奖励
func set_reward(gold: int, inspiration: int) -> void:
	gold_reward = gold
	inspiration_reward = inspiration


## 命中测试：global_pos（世界坐标）是否落在角色显示矩形内
## 直接基于 Sprite 的真实渲染矩形（region + scale），与屏幕显示严格对齐
func contains_point(global_pos: Vector2) -> bool:
	var rect := _sprite.get_rect()
	rect.size *= _sprite.scale
	rect = rect.grow(CLICK_PADDING)   # 仅在本体周围放宽容差
	var local := to_local(global_pos)
	return rect.has_point(local)


## 由轻点（tap）触发，统一入口：完成订单
func on_clicked() -> void:
	if _completed:
		return
	print("[cust] tap -> on_clicked reward=", gold_reward, "/", inspiration_reward)
	_complete_order()


## 鼠标交互：本节点自行判断"抓取 / 拖动 / 轻点完成"
## 命中判定用 contains_point（几何真相）；事件被本节点消费，避免 Main 误拖窗口
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
				get_viewport().set_input_as_handled()   # 声明消费：Main 不再拖窗口
				print("[cust] grab at ", gp)
		else:
			# 松开左键：根据是否拖动决定"放置"或"完成订单"
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
			global_position = gp + _grab_offset   # 跟随光标，保持抓取点


func _play_spawn_animation() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, SPAWN_FADE)


func _complete_order() -> void:
	_completed = true
	# 对外只发信号，不碰货币逻辑（低耦合）
	order_completed.emit({"gold": gold_reward, "inspiration": inspiration_reward})

	# 弹跳：两条独立 tween（顺序），避免并行打架
	var t_bounce := create_tween()
	t_bounce.tween_property(self, "scale", Vector2(CLICK_BOUNCE, CLICK_BOUNCE), 0.1)
	t_bounce.tween_property(self, "scale", Vector2.ONE, 0.15)

	# 淡出：独立 tween 与弹跳并行，结束后自毁
	var t_fade := create_tween()
	t_fade.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	t_fade.tween_callback(queue_free)
