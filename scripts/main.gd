extends Control
## Main · 主场景（编排层 / Orchestrator）
## 职责：组装子组件（HUD + PlayArea），编排顾客生成与订单完成的生命周期，
##       以及电话购物 / 仓库 / 灵感等副玩法入口。
## 原则：
##   - 高内聚：只做“编排”，不持有业务逻辑（货币/换装/动画等在各自节点）
##   - 低耦合：通过信号连接组件，不直接操作内部状态
##   - 组合：本节点 = 窗口管理（阶段0） + 游戏循环（阶段1） + 副玩法入口（阶段3）
##
## 输入处理说明：
##   鼠标交互的“判定与响应”归顾客/宠物自身（contains_point + _input 三态）。
##   主场景 _input 只负责：①点中关闭按钮交按钮处理 ②点中顾客/宠物则 return（节点已消费，不拖窗口）
##   ③点中电话摆件则 return（电话自身处理点击）④点中空白则拖拽窗口。
##   用 _customer_at_point / _pet_at_point / _phone_at_point（遍历子节点调 contains_point）守卫。

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

# ─── 阶段 3：灵感活动数据（Resource，灵感弹窗消费） ───
@export var activity_pool: Array[ActivityData] = []   ## 灵感活动资源池（.tres），拖入即用

# ─── 阶段 3 补：产品数据（Resource，电话购物 / 仓库消费） ───
@export var product_pool: Array[ProductData] = []     ## 产品资源池（.tres），拖入即用

# 节点引用 —— 通过 @onready 注入，不硬编码路径搜索
@onready var play_area: Node2D = $Panel/PlayArea
@onready var pet_area: Node2D = $Panel/PetArea
@onready var close_button: Button = $Panel/CloseButton
@onready var inspiration_btn: Button = $Panel/InspirationButton   ## 家园灵感悬浮入口（取代原右侧菜单）
@onready var placement_manager: PlacementManager = $PlacementManager
# ─── 阶段 1：四界面切换框架（步骤 1.3 接线） ───
@onready var screen_manager: ScreenManager = $ScreenManager   ## 屏幕互斥显隐管理器
@onready var screens_root: Control = $Screens                 ## 四个可切换屏的容器（覆盖层）
@onready var tab_bar: SignboardTabBar = $TabBar               ## 底部招牌导航栏

# 电话摆件引用（运行期实例化，见 _instance_phone）
var _phone: Control = null


func _ready() -> void:
	_configure_window()
	_schedule_first_spawn()
	_schedule_first_pet()
	inspiration_btn.pressed.connect(_open_inspiration)   ## 换装/仓库已并入切屏，仅灵感保留家园悬浮入口
	_ensure_product_pool()
	for p in product_pool:
		GameManager.register_item(p)
	# 阶段 0.4：注册服装到统一库存注册表，并一次性播种初始衣橱（每款各 1 件）
	_ensure_clothes_pool()
	for c in clothes_pool:
		GameManager.register_item(c)
	GameManager.seed_starter_clothing(clothes_pool)
	_instance_phone()
	placement_manager.init(product_pool, $Panel/PlacedItems)
	_setup_screens()


## 每帧把「是否有覆盖层弹窗打开」同步给 GameManager，供顾客/宠物/电话/摆放物
## 在 _input 阶段自我屏蔽（弹窗开着时不抢占点击，避免吃掉弹窗按钮的点击）。
func _process(_delta: float) -> void:
	GameManager.set_modal_open(
		_has_catalog() or _has_phone_panel()
		or _has_inspiration()
		or _has_warehouse()
		or _has_active_screen()
	)


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
			# 灵感悬浮入口：交给按钮 GUI 处理，不拖窗口
			if _on_inspiration_button(mp):
				return
			# 底部招牌区域：交给按钮 GUI 处理切屏（家园态点招牌也不拖窗口）
			if tab_bar != null and tab_bar.contains_button_point(mp):
				return
			# 仓库全局浮层已打开时：点击交由浮层自身处理，不拖窗口
			if _has_warehouse():
				return
			# 有活动屏时：屏为覆盖层，点击交由屏自身处理，不拖窗口
			if _has_active_screen():
				return
			# 点中宠物：宠物自身 _input 已消费（拖动/轻点红心），此处不拖窗口
			if _pet_at_point(mp) != null:
				return
			# 点中顾客：顾客自身 _input 已消费并自行处理（拖动/轻点完成），此处不拖窗口
			if _customer_at_point(mp) != null:
				return
			# 点中已摆放物品：摆放物自身 _input 已消费（拖动），此处不拖窗口
			if _placed_at_point(mp) != null:
				return
			# 点中电话摆件：交给电话自身处理点击，不拖窗口
			if _phone_at_point(mp):
				return
			# 产品目录已打开时，不响应空白拖拽（覆盖层处理自身交互）
			if _has_catalog():
				return
			# 订单中心已打开时，不响应空白拖拽
			if _has_phone_panel():
				return
			# 灵感面板已打开时，不响应空白拖拽
			if _has_inspiration():
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


## 点击位置是否落在灵感悬浮入口按钮内（仅按钮可见时生效）
func _on_inspiration_button(pos: Vector2) -> bool:
	return inspiration_btn != null and inspiration_btn.visible \
		and inspiration_btn.get_global_rect().has_point(pos)


## 灵感面板是否已打开（作为 Main 子节点覆盖全窗口）
func _has_inspiration() -> bool:
	return has_node("InspirationPanel")


## 产品目录弹窗是否已打开
func _has_catalog() -> bool:
	return has_node("ProductCatalog")


## 订单中心弹窗是否已打开
func _has_phone_panel() -> bool:
	return has_node("PhonePanel")


## 是否有覆盖屏处于激活态（种植/换装/工坊）。家园态（home）不算，不阻断家园拖拽。
func _has_active_screen() -> bool:
	return screen_manager != null and screen_manager.current_screen != "" \
		and screen_manager.current_screen != "home"


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


## 电话摆件是否被点中（Phone 实现 contains_point）
func _phone_at_point(global_pos: Vector2) -> bool:
	if _phone == null or not _phone.has_method("contains_point"):
		return false
	return _phone.contains_point(global_pos)


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


# ═══════════════════ 阶段 3：灵感面板入口 ═══════════════════

## 实例化灵感面板作为覆盖层，传入活动资源池；完成时通过信号回传 Main 编排
func _open_inspiration() -> void:
	if _has_inspiration():
		return
	# 数据驱动回退：未拖入任何 .tres 时，自动加载内置“阅读”活动，开箱即用
	if activity_pool.is_empty():
		var def = load("res://data/activity_reading.tres")
		if def != null:
			activity_pool = [def]
	var scene := preload("res://scenes/inspiration_panel.tscn")
	var panel: Control = scene.instantiate()
	panel.activity_pool = activity_pool
	add_child(panel)


# ═══════════════════ 阶段 3 补：电话购物 + 仓库 ═══════════════════

## 数据驱动回退：未拖入任何 .tres 时，自动加载内置三个产品
func _ensure_product_pool() -> void:
	if not product_pool.is_empty():
		return
	for path in ["res://data/product_chair.tres", "res://data/product_desk.tres", "res://data/product_lamp.tres"]:
		var res = load(path)
		if res != null:
			product_pool.append(res)


## 数据驱动回退：未拖入任何 .tres 时，自动加载内置五款服装（供注册/播种/换装用）
func _ensure_clothes_pool() -> void:
	if not clothes_pool.is_empty():
		return
	for path in [
		"res://data/clothes_hat.tres", "res://data/clothes_shirt.tres",
		"res://data/clothes_skirt.tres", "res://data/clothes_shoe.tres",
		"res://data/clothes_gt.tres",
	]:
		var res = load(path)
		if res != null:
			clothes_pool.append(res)


## 实例化桌面电话摆件，挂到 Panel 下，连接点击信号
func _instance_phone() -> void:
	var scene := preload("res://scenes/phone.tscn")
	var phone: Control = scene.instantiate()
	$Panel.add_child(phone)
	_phone = phone
	phone.phone_pressed.connect(_on_phone_pressed)


## 电话点击：双击 → 打开订单中心（进行中订单 + 已到货 + 去商城）
func _on_phone_pressed() -> void:
	_open_phone_panel()


## 实例化订单中心弹窗（覆盖层，双击电话打开）
func _open_phone_panel() -> void:
	if _has_phone_panel():
		return
	var scene := preload("res://scenes/phone_panel.tscn")
	var panel: Control = scene.instantiate()
	panel.product_pool = product_pool
	panel.shop_requested.connect(_on_phone_shop_requested)
	add_child(panel)


## 订单中心「去商城」→ 打开产品目录（订单中心留在下层，关闭目录后仍在）
func _on_phone_shop_requested() -> void:
	_open_catalog()


## 实例化产品目录弹窗（覆盖层）
func _open_catalog() -> void:
	if _has_catalog():
		return
	var scene := preload("res://scenes/product_catalog.tscn")
	var panel: Control = scene.instantiate()
	panel.product_pool = product_pool
	add_child(panel)


## 遍历 PlacedItems 子节点，调用各自的 contains_point 进行命中判定
func _placed_at_point(global_pos: Vector2) -> Node2D:
	var container: Node2D = $Panel/PlacedItems
	if container == null:
		return null
	for c in container.get_children():
		if is_instance_valid(c) and c.has_method("contains_point") and c.contains_point(global_pos):
			return c
	return null


## 仓库「摆放」按钮回调：把该产品实例化为世界中的可摆放物体
func _on_placement_requested(data: ProductData) -> void:
	if placement_manager != null:
		placement_manager.spawn_from_product(data)


# ═══════════════════ 阶段 1：四界面切换框架接线（步骤 1.3） ═══════════════════
## 编排职责：实例化/注册 4 个屏幕（本步为占位空屏，阶段 2 换真内容）、
## 把底部 TabBar 与 ScreenManager 互联。切屏互斥逻辑在 ScreenManager，
## 招牌点击/高亮在 TabBar，本处只做「接线」，符合低耦合 + SRP。

## 可切换屏定义：家园是独立第 4 个对等 tab（由 ScreenManager.go_home 处理，不在此注册），
## 仓库是全局浮层（不在此注册）。此处仅 3 个覆盖屏：换装/种植/工坊。
## id 与 ScreenManager.SCREEN_* / TabBar.TABS 对齐，顺序即箭头循环顺序。
const _SCREEN_DEFS := [
	{"id": "wardrobe", "title": "换装屏"},
	{"id": "farm", "title": "种植屏（占位·阶段2填充）"},
	{"id": "workshop", "title": "工坊屏（占位·阶段2填充）"},
]


## 生成 3 个覆盖屏并注册进 ScreenManager，接通 TabBar 双向信号，初始高亮「家园」。
## 家园与仓库不在此注册：家园由 ScreenManager.go_home() 处理（第 4 个对等 tab），
## 仓库是全局浮层，由 _toggle_warehouse_global() 管理。
func _setup_screens() -> void:
	for def in _SCREEN_DEFS:
		var scr: Control
		match def["id"]:
			"wardrobe":
				scr = _make_wardrobe_screen()      ## 换装屏 = 复用换装场景（原右侧菜单「换装」并入）
			_:
				scr = _make_placeholder_screen(def["title"])  ## 种植/工坊：阶段 2.3/2.4 前占位
		scr.name = "Screen_" + def["id"]
		screens_root.add_child(scr)
		screen_manager.register_screen(def["id"], scr)   ## 注册即隐藏
	# TabBar 点击 → 切屏/开全局浮层
	tab_bar.tab_selected.connect(_on_tab_selected)
	# 屏变化 → 回灌 TabBar 高亮（home/farm/wardrobe/workshop）
	screen_manager.screen_changed.connect(tab_bar.set_active)
	# 初始进入家园态并高亮「家园」tab
	screen_manager.go_home()


## 换装屏：实例化换装场景作为常驻切屏内容。
## 隐藏其自带 CloseButton（切屏开合改由底部招牌 toggle 控制）；
## 传入衣服资源池；可见时自刷新由 wardrobe.gd 的 visibility_changed 负责。
func _make_wardrobe_screen() -> Control:
	var scene := preload("res://scenes/wardrobe.tscn")
	var w: Control = scene.instantiate()
	w.clothes_pool = clothes_pool
	var close_btn := w.get_node_or_null("CloseButton") as CanvasItem
	if close_btn != null:
		close_btn.hide()
	return w


## 仓库 = 全局浮层（非切换屏）：任意屏激活时都能打开，不占用 tab 切换位。
## 实例挂到 Screens 容器内（绘制序在 TabBar 之下），故招牌栏始终可点、可再点收起。
## 其内部 × 关闭会 queue_free，tree_exited 时清空引用以便再次打开。
var _warehouse_panel: Control = null

func _toggle_warehouse_global() -> void:
	if _has_warehouse():
		_warehouse_panel.queue_free()      ## × 按钮也会 queue_free，tree_exited 兜底清空
	else:
		_open_warehouse_global()


func _open_warehouse_global() -> void:
	if _has_warehouse():
		return
	var scene := preload("res://scenes/warehouse_panel.tscn")
	var panel: Control = scene.instantiate()
	panel.product_pool = product_pool
	panel.placement_requested.connect(_on_placement_requested)
	screens_root.add_child(panel)          ## 置于 Screens 容器内 → 绘制在 TabBar 之下
	panel.tree_exited.connect(_on_warehouse_exited)
	_warehouse_panel = panel


func _has_warehouse() -> bool:
	return _warehouse_panel != null and is_instance_valid(_warehouse_panel)


func _on_warehouse_exited() -> void:
	_warehouse_panel = null


## 构建一个占位屏（覆盖家园中央区、让出底部招牌栏）。阶段 2 会用真实屏替换。
func _make_placeholder_screen(title: String) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   ## 覆盖层拦截点击，不穿透到家园
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_bottom = -52.0                          ## 让出底部 52px 招牌栏
	bg.color = Color(0.16, 0.13, 0.11, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_bottom = -52.0
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.88))
	root.add_child(label)
	return root


## 底部招牌点击：仓库→开/关全局浮层；其余→toggle 对应屏（再点当前屏则收起回家园）
func _on_tab_selected(id: String) -> void:
	if id == "warehouse":
		_toggle_warehouse_global()
	else:
		screen_manager.toggle_screen(id)
