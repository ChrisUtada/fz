extends Node2D
## Customer · 顾客（组合节点 / Node2D）
##
## 组成：
##   - Sprite2D(char.png)  角色外观（scale=0.38 由代码统一设置）
##   - Area2D + CollisionShape2D  预留：阶段3 的"重叠/互动区"检测（本阶段不用于点击）
##
## 点击检测：
##   由 Main._unhandled_input 的世界坐标命中测试（contains_point）触发 on_clicked，
##   不依赖 Area2D 的 input_event（在 Control 为主的窗口里拾取不稳定）。
##
## 原则（工程规范）：
##   - 低耦合：仅通过信号对外通信（order_completed），不直接引用 GameManager 等外部模块
##   - 高内聚：本节点只负责"角色表现 + 命中判定 + 自身动画"
##   - 可扩展：基于 Node2D，后续可直接挂 AnimationPlayer / AnimationTree 做换装、动作、状态机
##
## 信号：
##   order_completed(reward)  点击完成后发出，由 Main 编排层接收并委托 GameManager

signal order_completed(reward: Dictionary)

const BASE_SCALE := Vector2(0.38, 0.38)   ## 贴图缩放（char.png 736x414 偏大）
const CLICK_BOUNCE := 1.25                ## 点击弹跳倍率（相对 Node2D scale=1）
const SPAWN_FADE := 0.4                   ## 入场渐入时长
const FADE_DURATION := 0.4                ## 离场淡出时长
const HIT_HALF := Vector2(140.0, 78.5)    ## 命中框半尺寸（= 贴图显示尺寸 280x157 的一半）

## 奖励（由 Main 通过 set_reward 注入，依赖注入）
@export var gold_reward: int = 100
@export var inspiration_reward: int = 10

var _completed := false

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
func contains_point(global_pos: Vector2) -> bool:
	var half := HIT_HALF * scale
	var local := to_local(global_pos)
	return abs(local.x) <= half.x and abs(local.y) <= half.y


## 由 Main 命中测试触发，统一入口
func on_clicked() -> void:
	if _completed:
		return
	_complete_order()


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
