extends Control
## Main · 主场景（编排层 / Orchestrator）
## 职责：组装子组件（HUD + PlayArea），编排顾客生成与订单完成的生命周期。
## 原则：
##   - 高内聚：只做"编排"，不持有业务逻辑（货币/换装/动画等在各自节点）
##   - 低耦合：通过信号连接组件，不直接操作内部状态
##   - 组合：本节点 = 窗口管理（阶段0） + 游戏循环（阶段1）
##
## 输入处理说明：
##   鼠标交互的"判定与响应"归顾客/宠物自身（contains_point + _input 三态）。
##   主场景 _input 只负责：①点中关闭按钮交按钮处理 ②点中顾客/宠物则 return（节点已消费，不拖窗口）
##   ③点中空白则拖拽窗口。用 _customer_at_point / _pet_at_point（遍历子节点调 contains_point）守卫。

# ─── 阶段 0：窗口管理 ───
var _dragging := false
var _drag_offset := Vector2i.ZERO

# ─── 阶段 1：顾客生成配置 ───
@export var first_spawn_delay: float = 1.5          ## 首个顾客出现延迟
@export var min_spawn_interval: float = 2.0         ## 生成间隔下限
@export var max_spawn_interval: float = 4.0         ## 生成间隔上限

# ─── 阶段 2：数据驱动（Resource） ───
@export var customer_pool: Array[CustomerData] = []   ## 顾客数据资源池（.tres），拖入即用

# ─── 阶段 1 补：宠物生成配置 ───
@export var first_pet_delay: float = 3.0          ## 首只宠物出现延迟
@export var min_pet_interval: float = 5.0         ## 宠物生成间隔下限
@export var max_pet_interval: float = 10.0        ## 宠物生成间隔上限
@export var max_pets: int = 1                     ## 同时存在的宠物数量上限

# ─── 阶段 2：宠物数据（Resource） ───
@export var pet_pool: Array[PetData] = []           ## 宠物数据资源池（.tres），拖入即用

# ─── 阶段 2：衣服数据（Resource，换装场景消费） ───
@export var clothes_pool: Array[ClothesData] = []   ## 衣服数据资源池（.tres），拖入即用

# 节点引用 —— 通过 @onready 注入，不硬编码路径搜索
@onready var play_area: Node2D = $Panel/PlayArea
@onready var pet_area: Node2D = $Panel/PetArea
@onready var close_button: Button = $Panel/CloseButton
@onready var ui_panel: Control = $Panel/UIPanel


func _ready() -> void:
	_configure_window()
	_schedule_first_spawn()
	_schedule_first_pet()
	ui_panel.wardrobe_requested.connect(_open_wardrobe)


# ═══════════════════ 阶段 0：窗口管理 ═══════════════════

func _configure_window() -> void:
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.borderless = true
	win.transparent = true
	win.always_on_top = false


func _input(event: InputEvent) -> void:
	# 用 _input（最早回调，对所有节点调用，不依赖事件是否被 GUI 消费）统一处理指针
	# 空白拖拽窗口；点中顾客/关闭按钮则交给对应节点，不在此处理
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mp := get_global_mouse_position()
			# 关闭按钮区域：交给按钮自身的 pressed 处理，不拖拽
			if _on_close_button(mp):
				return
			# UI 侧边面板区域：交互由面板内部处理，不拖窗口
			if _on_ui_panel(mp):
				return
			# 点中宠物：宠物自身 _input 已消费（拖动/轻点红心），此处不拖窗口
			if _pet_at_point(mp) != null:
				return
			# 点中顾客：顾客自身 _input 已消费并自行处理（拖动/轻点完成），此处不拖窗口
			if _customer_at_point(mp) != null:
				return
			# 换装场景已打开时，不响应空白拖拽（换装场景覆盖全窗口处理自身交互）
			if _has_wardrobe():
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


## 点击位置是否落在 UI 侧边面板区域内
func _on_ui_panel(pos: Vector2) -> bool:
	return ui_panel.get_global_rect().has_point(pos)


## 换装场景是否已打开（作为 Main 子节点覆盖全窗口）
func _has_wardrobe() -> bool:
	return has_node("Wardrobe")


## 遍历 PlayArea 子节点，调用各自的 contains_point 进行命中判定
func _customer_at_point(global_pos: Vector2) -> Node2D:
	for c in play_area.get_children():
		if is_instance_valid(c) and c.has_method("contains_point") and c.contains_point(global_pos):
			return c
	return null


## 遍历 PetArea 子节点，调用各自的 contains_point 进行命中判定
func _pet_at_point(global_pos: Vector2) -> Node2D:
	for p in pet_area.get_children():
		if is_instance_valid(p) and p.has_method("contains_point") and p.contains_point(global_pos):
			return p
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

	# 数据驱动：从顾客资源池随机抽一个 CustomerData，交给场景消费控制外观与奖励
	if not customer_pool.is_empty():
		var data: CustomerData = customer_pool.pick_random()
		if customer.has_method("apply_data"):
			customer.apply_data(data)

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


# ═══════════════════ 阶段 1 补：宠物生成与编排 ═════════════════

func _schedule_first_pet() -> void:
	await get_tree().create_timer(first_pet_delay).timeout
	_spawn_pet()


func _spawn_pet() -> void:
	# 检查是否达到数量上限（包含正在淡出的）
	if pet_area.get_child_count() >= max_pets:
		# 已达上限，跳过本次生成，继续监听
		var interval := randf_range(min_pet_interval, max_pet_interval)
		await get_tree().create_timer(interval).timeout
		_spawn_pet()
		return

	var scene := preload("res://scenes/pet.tscn")
	var pet: Node2D = scene.instantiate()

	# 数据驱动：从宠物资源池随机抽一个 PetData，交给场景消费控制外观与行走参数
	if not pet_pool.is_empty():
		var data: PetData = pet_pool.pick_random()
		if pet.has_method("apply_data"):
			pet.apply_data(data)

	# 宠物从屏幕边缘随机位置进入（由 pet.gd 内部的 _pick_direction 决定方向）
	pet.position = Vector2.ZERO  # 初始位置由 pet 自身调整

	pet_area.add_child(pet)

	# 可选：连接宠物信号（如点击统计、成就等扩展点）
	# pet.pet_tapped.connect(_on_pet_tapped)

	# 安排下一只宠物
	var interval := randf_range(min_pet_interval, max_pet_interval)
	await get_tree().create_timer(interval).timeout
	_spawn_pet()


# ═══════════════════ 阶段 2：换装场景入口 ═══════════════════

## 实例化换装场景作为覆盖层，传入衣服资源池
func _open_wardrobe() -> void:
	var scene := preload("res://scenes/wardrobe.tscn")
	var wardrobe: Control = scene.instantiate()
	wardrobe.clothes_pool = clothes_pool
	add_child(wardrobe)
