extends Control
## Main · 主场景（编排层 / Orchestrator）
## 职责：组装子组件（HUD + PlayArea），编排顾客生成与订单完成的生命周期。
## 原则：
##   - 高内聚：只做"编排"，不持有业务逻辑（货币/换装/动画等在各自节点）
##   - 低耦合：通过信号连接组件，不直接操作内部状态
##   - 组合：本节点 = 窗口管理（阶段0） + 游戏循环（阶段1）
##
## 输入处理说明：
##   单一输入权威：Main._input（最早回调，对所有节点调用，不依赖事件是否被 GUI 消费）
##   统一做命中判定与派发——命中顾客则调用 customer.on_clicked() 完成订单，
##   点中空白则拖拽窗口，点中关闭按钮则交给按钮自身处理。顾客不再持有 _input，避免双 _input 竞态。

# ─── 阶段 0：窗口管理 ───
var _dragging := false
var _drag_offset := Vector2i.ZERO

# ─── 阶段 1：顾客生成配置 ───
@export var first_spawn_delay: float = 1.5          ## 首个顾客出现延迟
@export var min_spawn_interval: float = 2.0         ## 生成间隔下限
@export var max_spawn_interval: float = 4.0         ## 生成间隔上限
@export var base_gold_reward: int = 100             ## 基础金币奖励
@export var base_inspiration_reward: int = 10       ## 基础灵感奖励
@export var reward_variance: int = 50              ## 奖励浮动范围 (±N)

# 节点引用 —— 通过 @onready 注入，不硬编码路径搜索
@onready var play_area: Node2D = $Panel/PlayArea
@onready var close_button: Button = $Panel/CloseButton


func _ready() -> void:
	_configure_window()
	_schedule_first_spawn()


# ═══════════════════ 阶段 0：窗口管理 ═══════════════════

func _configure_window() -> void:
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.borderless = true
	win.transparent = true
	win.always_on_top = false


func _input(event: InputEvent) -> void:
	# 用 _input（最早回调，对所有节点调用，不依赖事件是否被 GUI 消费）统一处理指针
	# 单一输入权威：命中判定与订单派发都在此完成，避免双 _input 竞态
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mp := get_global_mouse_position()
			# 关闭按钮区域：交给按钮自身的 pressed 处理，不拖拽
			if _on_close_button(mp):
				print("[main] press on close button")
				return
			# 命中顾客 → 派发订单完成，不拖拽
			var target := _customer_at_point(mp)
			print("[main] press pos=", mp, " cust=", target)
			if target != null:
				target.on_clicked()
				return
			# 空白 → 开始拖拽窗口
			_dragging = true
			_drag_offset = DisplayServer.window_get_position() - DisplayServer.mouse_get_position()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		DisplayServer.window_set_position(DisplayServer.mouse_get_position() + _drag_offset)


## 点击位置是否落在关闭按钮的全局矩形内
func _on_close_button(pos: Vector2) -> bool:
	return close_button.get_global_rect().has_point(pos)


## 在 PlayArea 中查找包含 global_pos 的顾客（调用顾客自身的 contains_point 几何判定）
func _customer_at_point(global_pos: Vector2) -> Node2D:
	for c in play_area.get_children():
		if is_instance_valid(c) and c.has_method("contains_point") and c.contains_point(global_pos):
			return c
	return null


func _on_close_pressed() -> void:
	get_tree().quit()


# ═══════════════════ 阶段 1：顾客生成与订单编排 ═════════════════

func _schedule_first_spawn() -> void:
	await get_tree().create_timer(first_spawn_delay).timeout
	_spawn_customer()


func _spawn_customer() -> void:
	var scene := preload("res://scenes/customer.tscn")
	var customer: Node2D = scene.instantiate()

	# 注入随机奖励金额（依赖注入）
	var gold_r := randi_range(base_gold_reward - reward_variance, base_gold_reward + reward_variance)
	var insp_r := randi_range(
		base_inspiration_reward - reward_variance,
		base_inspiration_reward + reward_variance
	)
	customer.set_reward(max(gold_r, 1), max(insp_r, 1))

	# 随机位置偏移，避免每次完全重叠
	customer.position = Vector2(randf_range(-40.0, 40.0), randf_range(-20.0, 20.0))

	# 将顾客注入 PlayArea —— 依赖注入目标容器
	play_area.add_child(customer)

	# 信号连接：顾客完成 → 编排器处理 → 触发下一个周期
	customer.order_completed.connect(_on_order_completed)


func _on_order_completed(reward: Dictionary) -> void:
	# 委托给 GameManager 处理货币变更（单一职责）
	GameManager.complete_order(reward)

	# 安排下一个顾客
	var interval := randf_range(min_spawn_interval, max_spawn_interval)
	await get_tree().create_timer(interval).timeout
	_spawn_customer()
