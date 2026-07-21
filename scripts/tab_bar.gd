extends Control
class_name SignboardTabBar
## TabBar · 底部招牌导航栏（阶段 1 · 步骤 1.2；动画扩展于阶段 3）
##
## 职责（单一）：横栏 + 4 枚对等主 tab（家园/种植/换装/工坊）+ 1 枚全局入口（仓库），点击时 emit tab_selected(id)。
##   本组件只负责「发出点击了哪个 tab」与「显示哪个 tab 处于激活态 + 招牌摆动动画」，
##   不认识屏幕内容、不切屏（切屏由 main 接线到 ScreenManager，步骤 1.3）。
##
## 设计原则：
##   - 低耦合：仅一个出向信号 tab_selected(id)；激活高亮由外部 set_active(id) 同步
##     （main 监听 ScreenManager.screen_changed 后回灌，含 home = 家园态高亮）。
##   - 数据驱动：主 tab 见 TABS，id 与 ScreenManager.SCREEN_* 对齐；全局入口见 GLOBAL_SLOTS。
##
## 阶段 3 · 招牌晃动动画：
##   - 每枚 tab 包成一个「招牌」Control = 顶部 4px 绳子 + 下方按钮，pivot_offset 在顶部中点（挂点）。
##   - 点击切屏（set_active 统一入口，覆盖点击与箭头导航）触发 Elastic 摆动（-12° → 0°，过冲回弹）。
##   - 悬停时极轻微 perpetual 摇摆（±2.5°），移出平滑归位；与点击摆动互不打架。
##
## 注意：不使用 class_name TabBar —— Godot 已有内置 TabBar 类，会冲突，故命名 SignboardTabBar。

signal tab_selected(id: String)

## 对等主 tab：4 个，权重一致，顺序 = 显示顺序 = 箭头 next/prev 循环顺序
const TABS := [
	{"id": "home", "text": "家园"},
	{"id": "farm", "text": "种植"},
	{"id": "wardrobe", "text": "换装"},
	{"id": "workshop", "text": "工坊"},
]
## 全局浮层入口：不切屏，点开全局覆盖层；与 4 个主 tab 视觉区分（暖金基调）
const GLOBAL_SLOTS := [
	{"id": "warehouse", "text": "仓库"},
]

const SIGN_WIDTH := 64
const SIGN_HEIGHT := 34
const ROPE_HEIGHT := 12                       ## 招牌顶部绳子高度（挂点→按钮间的连接）
const ROPE_WIDTH := 4                         ## 绳子粗细
const ROPE_COLOR := Color(0.55, 0.4, 0.25, 1)## 麻绳色（呼应横栏棕调）
const ACTIVE_MOD := Color(1, 1, 1, 1)          ## 激活态招牌（全亮）
const INACTIVE_MOD := Color(1, 1, 1, 0.62)     ## 非激活态招牌（压暗）
const GLOBAL_MOD := Color(0.96, 0.82, 0.42, 1)## 全局入口基调（暖金，暗示“随时可达”）

## 阶段 3 动画参数
const SWING_FROM := -12.0                     ## 摆动起始角（度）
const SWING_DURATION := 0.8                   ## 摆动时长（秒）
const HOVER_AMP := 2.5                        ## 悬停摇摆幅度（度）
const HOVER_DURATION := 1.6                   ## 悬停单程时长（秒）

## 当前高亮的 tab id；home = 家园态高亮
var _current: String = ""
## id -> Button（高亮同步 + 命中检测，保留裸按钮引用）
var _buttons: Dictionary = {}
## id -> 招牌 Control（绳子+按钮的容器，旋转动画作用对象，pivot 在顶部中点）
var _boards: Dictionary = {}
## id -> 悬停状态（决定是否在摆动结束后恢复悬停摇摆）
var _hovering: Dictionary = {}
## id -> 当前摆动/悬停 Tween（便于打断重启动画）
var _swing_tweens: Dictionary = {}
var _hover_tweens: Dictionary = {}
## 全局入口 id 列表（这些按钮不参与屏高亮，保持暖金基调；且不经 set_active 驱动摆动）
var _global_ids: Array[String] = []
## 启动首屏高亮不摆动（避免开局自动晃一下）
var _skip_next_swing := true

@onready var _row: HBoxContainer = $Row


func _ready() -> void:
	_build_tabs()


## 依 TABS / GLOBAL_SLOTS 动态构建：4 枚主 tab + 分隔线 + 全局入口。
func _build_tabs() -> void:
	for def in TABS:
		_add_tab_button(def["id"], def["text"], false)
	# 分隔线：主 tab 与全局入口之间（VSeparator 为竖线）
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(2, 28)
	_row.add_child(sep)
	for def in GLOBAL_SLOTS:
		_add_tab_button(def["id"], def["text"], true)


## 创建一枚招牌（绳子 + 按钮），挂进 _row。
## is_global=true 用暖金基调且不随屏高亮；其 Elastic 摆动由自身 pressed 触发（不经 set_active）。
func _add_tab_button(id: String, text: String, is_global: bool) -> void:
	# 招牌容器：pivot 在顶部中点 → 整块（绳+按钮）绕挂点旋转
	var board := Control.new()
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE   ## 命中交给内部按钮；自身只承载渲染与旋转
	board.custom_minimum_size = Vector2(SIGN_WIDTH, ROPE_HEIGHT + SIGN_HEIGHT)
	board.pivot_offset = Vector2(SIGN_WIDTH / 2.0, 0.0)

	# 绳子：顶部居中 4px，上接横栏、下连按钮（视觉上“挂着”）
	var rope := ColorRect.new()
	rope.color = ROPE_COLOR
	rope.custom_minimum_size = Vector2(ROPE_WIDTH, ROPE_HEIGHT)
	rope.position = Vector2(SIGN_WIDTH / 2.0 - ROPE_WIDTH / 2.0, 0.0)
	rope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(rope)

	# 按钮（招牌主体）
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(SIGN_WIDTH, SIGN_HEIGHT)
	btn.focus_mode = Control.FOCUS_NONE
	btn.modulate = GLOBAL_MOD if is_global else INACTIVE_MOD
	btn.position = Vector2(0, ROPE_HEIGHT)
	btn.pressed.connect(_on_tab_pressed.bind(id))
	# 悬停微摆：挂到按钮（鼠标事件稳定落在按钮区），旋转作用到整块 board
	btn.mouse_entered.connect(_on_tab_hover.bind(id))
	btn.mouse_exited.connect(_on_tab_unhover.bind(id))
	board.add_child(btn)

	_row.add_child(board)
	_boards[id] = board
	_buttons[id] = btn
	if is_global:
		_global_ids.append(id)


func _on_tab_pressed(id: String) -> void:
	tab_selected.emit(id)
	# 全局入口不切屏（无 set_active 回灌），自身点击触发一次摆动作反馈
	if _global_ids.has(id):
		_swing_board(id)


func _on_tab_hover(id: String) -> void:
	_hovering[id] = true
	_start_hover(id)


func _on_tab_unhover(id: String) -> void:
	_hovering.erase(id)
	_stop_hover(id)


## 由外部同步激活高亮（main 监听 ScreenManager.screen_changed 后调用）。
## id 传 home/farm/wardrobe/workshop 之一；全局入口（仓库）始终暖金、不参与高亮。
## 阶段 3：启动首屏跳过摆动；之后每次高亮切换触发对应招牌 Elastic 摆动（覆盖点击与箭头导航）。
func set_active(id: String) -> void:
	_current = id
	for bid in _buttons:
		var b: Button = _buttons[bid]
		if is_instance_valid(b):
			if _global_ids.has(bid):
				b.modulate = GLOBAL_MOD
			else:
				b.modulate = ACTIVE_MOD if bid == id else INACTIVE_MOD
	# 首次（启动高亮）不摆动；之后任意屏切换都让对应招牌荡一下
	if _skip_next_swing:
		_skip_next_swing = false
		return
	if id != "" and _boards.has(id):
		_swing_board(id)


## ── 阶段 3.2 点击 Elastic 摆动 ──
## 招牌从 SWING_FROM 度起，tween 回 0，ELASTIC 过冲回弹；动画仅装饰、不阻塞切屏。
func _swing_board(id: String) -> void:
	var board: Control = _boards.get(id)
	if board == null or not is_instance_valid(board):
		return
	_kill_swing(id)
	_kill_hover(id)
	board.rotation_degrees = SWING_FROM
	var t := create_tween()
	t.tween_property(board, "rotation_degrees", 0.0, SWING_DURATION)
	t.set_trans(Tween.TRANS_ELASTIC)
	t.set_ease(Tween.EASE_OUT)
	_swing_tweens[id] = t
	t.finished.connect(func():
		_swing_tweens.erase(id)
		# 摆动结束：若仍悬停该招牌则恢复轻微摇摆
		if _hovering.get(id, false):
			_start_hover(id)
	)


## ── 阶段 3.3 hover 微摆动 ──
## 悬停时 ±HOVER_AMP 度 perpetual 摇摆（SINE IN_OUT，yoyo 循环），增强挂机活物感。
func _start_hover(id: String) -> void:
	var board: Control = _boards.get(id)
	if board == null or not is_instance_valid(board):
		return
	_kill_swing(id)      ## 悬停接管：若正在 Elastic 摆动则打断，避免两个 tween 抢 rotation_degrees
	_kill_hover(id)
	var t := create_tween()
	t.set_loops()
	t.tween_property(board, "rotation_degrees", HOVER_AMP, HOVER_DURATION)
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_IN_OUT)
	t.tween_property(board, "rotation_degrees", -HOVER_AMP, HOVER_DURATION)
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_IN_OUT)
	_hover_tweens[id] = t


## 停止悬停摇摆并平滑归位（除非正在点击摆动中，由摆动收尾接管）
func _stop_hover(id: String) -> void:
	_kill_hover(id)
	if _swing_tweens.has(id):
		return
	var board: Control = _boards.get(id)
	if board != null and is_instance_valid(board):
		var t := create_tween()
		t.tween_property(board, "rotation_degrees", 0.0, 0.3)
		t.set_trans(Tween.TRANS_SINE)
		t.set_ease(Tween.EASE_OUT)


func _kill_swing(id: String) -> void:
	var t: Tween = _swing_tweens.get(id)
	if t != null and is_instance_valid(t):
		t.kill()
	_swing_tweens.erase(id)


func _kill_hover(id: String) -> void:
	var t: Tween = _hover_tweens.get(id)
	if t != null and is_instance_valid(t):
		t.kill()
	_hover_tweens.erase(id)


## 取某 tab 的按钮节点（保留接口，供外部需要）；无则返回 null
func get_tab_button(id: String) -> Button:
	return _buttons.get(id, null)


## 全局坐标是否命中任一招牌按钮。
## 供 main._input 守卫：点招牌时不启动窗口拖拽（Main._input 早于 GUI 阶段，
## 需主动放行让按钮的 pressed 生效，否则家园态点招牌会同时拖窗口）。
func contains_button_point(global_pos: Vector2) -> bool:
	for bid in _buttons:
		var b: Button = _buttons[bid]
		if is_instance_valid(b) and b.get_global_rect().has_point(global_pos):
			return true
	return false
