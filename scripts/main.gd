extends Control
## Main · 主场景（编排层 / Orchestrator）
## 职责：组装子组件（HUD + PlayArea），编排顾客生成与订单完成的生命周期。
## 原则：
##   - 高内聚：只做"编排"，不持有业务逻辑（货币/换装/动画等在各自节点）
##   - 低耦合：通过信号连接组件，不直接操作内部状态
##   - 组合：本节点 = 窗口管理（阶段0） + 游戏循环（阶段1）

# ─── 阶段 0：窗口管理 ───
var _dragging := false
var _drag_offset := Vector2i.ZERO
# 悬停守卫：当前鼠标下方是否有顾客（Node2D+Area2D 不属于 Control 输入系统，
# 无法用 mouse_filter 拦截，故以"悬停引用"判断，避免点顾客时误拖窗口）
var _hovered_customer: Node2D = null

# ─── 阶段 1：顾客生成配置 ───
@export var first_spawn_delay: float = 1.5          ## 首个顾客出现延迟
@export var min_spawn_interval: float = 2.0         ## 生成间隔下限
@export var max_spawn_interval: float = 4.0         ## 生成间隔上限
@export var base_gold_reward: int = 100             ## 基础金币奖励
@export var base_inspiration_reward: int = 10       ## 基础灵感奖励
@export var reward_variance: int = 50              ## 奖励浮动范围 (±N)

# 节点引用 —— 通过 @onready 注入，不硬编码路径搜索
@onready var play_area: Node2D = $Panel/PlayArea


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


func _gui_input(event: InputEvent) -> void:
	# 鼠标悬停在顾客上时（Node2D+Area2D）不触发窗口拖拽，交给顾客处理点击
	if _hovered_customer != null and is_instance_valid(_hovered_customer):
		return
	# 仅当事件冒泡到 Main（即点中面板空白处，而非顾客/按钮等）时才拖拽
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = DisplayServer.window_get_position() - DisplayServer.mouse_get_position()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		DisplayServer.window_set_position(DisplayServer.mouse_get_position() + _drag_offset)


func _on_close_pressed() -> void:
	get_tree().quit()


# ═══════════════════ 阶段 1：顾客生成与订单编排 ═══════════════════

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
	# 悬停守卫：供拖拽逻辑判断是否点中顾客
	customer.order_completed.connect(_on_order_completed)
	customer.pointer_entered.connect(_on_customer_pointer_entered.bind(customer))
	customer.pointer_exited.connect(_on_customer_pointer_exited.bind(customer))


func _on_customer_pointer_entered(c: Node2D) -> void:
	_hovered_customer = c


func _on_customer_pointer_exited(c: Node2D) -> void:
	if _hovered_customer == c:
		_hovered_customer = null


func _on_order_completed(reward: Dictionary) -> void:
	# 委托给 GameManager 处理货币变更（单一职责）
	GameManager.complete_order(reward)

	# 安排下一个顾客
	var interval := randf_range(min_spawn_interval, max_spawn_interval)
	await get_tree().create_timer(interval).timeout
	_spawn_customer()
