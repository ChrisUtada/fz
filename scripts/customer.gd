extends Node2D
## Customer · 顾客（组合节点 / Node2D）
##
## 组成：
##   - Sprite2D(char.png)  角色外观（region 裁剪出小人，scale 由代码统一设置）
##
## 点击检测：
##   由 Main._input（单一输入权威）做世界坐标命中测试，调用本节点的 contains_point()
##   判断是否点中，命中则调用 on_clicked() 完成订单。
##   contains_point 直接基于 Sprite 的真实渲染矩形（region + scale），与屏幕显示严格对齐，
##   不再手动估算矩形，避免"框与显示错位导致点击永远 miss"。
##   这样顾客仍"以自己的几何方法判断鼠标命中"，但派发权集中在 Main，避免双 _input 竞态。
##
## 原则（工程规范）：
##   - 低耦合：仅通过信号对外通信（order_completed），不直接引用 GameManager 等外部模块
##   - 高内聚：本节点只负责"角色表现 + 命中判定 + 自身动画"
##   - 可扩展：基于 Node2D，后续可直接挂 AnimationPlayer / AnimationTree 做换装、动作、状态机
##
## 信号：
##   order_completed(reward)  点击完成后发出，由 Main 编排层接收并委托 GameManager

signal order_completed(reward: Dictionary)

const BASE_SCALE := Vector2(1.0, 1.0)     ## 角色显示缩放（region 仅裁出小人 76x154，1.0 即实际像素）
const CLICK_BOUNCE := 1.25                ## 点击弹跳倍率（相对 Node2D scale=1）
const SPAWN_FADE := 0.4                   ## 入场渐入时长
const FADE_DURATION := 0.4                ## 离场淡出时长
const CLICK_PADDING := 36.0               ## 命中框外扩容差（像素），提升点击手感

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
	# 直接基于 Sprite 的真实渲染矩形（含 region 裁剪 + 自身 scale），
	# 保证命中框与屏幕显示完全对齐，避免手动估算矩形导致的错位
	var rect := _sprite.get_rect()
	rect.size *= _sprite.scale
	rect = rect.grow(CLICK_PADDING)   # 放宽点击容差，提升手感
	var local := to_local(global_pos)
	return rect.has_point(local)


## 由 Main 命中测试触发，统一入口
func on_clicked() -> void:
	if _completed:
		return
	print("[cust] on_clicked() reward=", gold_reward, "/", inspiration_reward)
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
