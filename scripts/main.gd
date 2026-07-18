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


func _unhandled_input(event: InputEvent) -> void:
	# 指针处理放在 _unhandled_input：
	# - UI 按钮（如 CloseButton, mouse_filter=STOP）会自行消费点击，不会进入这里 → 不误拖
	# - 顾客（Node2D，非 Control）与空白处的点击不被 GUI 消费 → 进入这里做命中测试 / 拖拽
	# 用 get_global_mouse_position() 取世界坐标，避开 event.global_position 的视口/画布空间歧义
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		var target := _customer_at_point(get_global_mouse_position())
		if target != null:
			target.on_clicked()
		else:
			_dragging = true
			_drag_offset = DisplayServer.window_get_position() - DisplayServer.mouse_get_position()
	else:
		_dragging = false


func _input(event: InputEvent) -> void:
	# 拖拽中的鼠标移动用 _input 处理：保证 motion 不被任何节点拦截，窗口跟随流畅
	if _dragging and event is InputEventMouseMotion:
		DisplayServer.window_set_position(DisplayServer.mouse_get_position() + _drag_offset)


## 在 PlayArea 中查找包含 global_pos 的顾客（点击命中测试）
func _customer_at_point(global_pos: Vector2) -> Node2D:
	for c in play_area.get_children():
		if c.has_method("contains_point") and c.contains_point(global_pos):
			return c
	return null


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
	customer.order_completed.connect(_on_order_completed)


func _on_order_completed(reward: Dictionary) -> void:
	# 委托给 GameManager 处理货币变更（单一职责）
	GameManager.complete_order(reward)

	# 安排下一个顾客
	var interval := randf_range(min_spawn_interval, max_spawn_interval)
	await get_tree().create_timer(interval).timeout
	_spawn_customer()
