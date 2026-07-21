extends Control
class_name SignboardTabBar
## TabBar · 底部招牌导航栏（阶段 1 · 步骤 1.2）
##
## 职责（单一）：横栏 + 4 枚对等主 tab（家园/种植/换装/工坊）+ 1 枚全局入口（仓库），点击时 emit tab_selected(id)。
##   本组件只负责「发出点击了哪个 tab」与「显示哪个 tab 处于激活态」，
##   不认识屏幕内容、不切屏（切屏由 main 接线到 ScreenManager，步骤 1.3）。
##
## 设计原则：
##   - 低耦合：仅一个出向信号 tab_selected(id)；激活高亮由外部 set_active(id) 同步
##     （main 监听 ScreenManager.screen_changed 后回灌，含 "" = 家园态无高亮）。
##   - 数据驱动：主 tab 见 TABS，id 与 ScreenManager.SCREEN_* 对齐；全局入口见 GLOBAL_SLOTS。
##   - 为阶段 3「招牌摆动」预留：每枚 tab 的 pivot_offset 设在顶部中点，_buttons 保留引用。
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
const ACTIVE_MOD := Color(1, 1, 1, 1)          ## 激活态招牌（全亮）
const INACTIVE_MOD := Color(1, 1, 1, 0.62)     ## 非激活态招牌（压暗）
const GLOBAL_MOD := Color(0.96, 0.82, 0.42, 1) ## 全局入口基调（暖金，暗示“随时可达”）

## 当前高亮的 tab id；home = 家园态高亮
var _current: String = ""
## id -> Button（供高亮同步与阶段 3 摆动动画取引用）
var _buttons: Dictionary = {}
## 全局入口 id 列表（这些按钮不参与屏高亮，保持暖金基调）
var _global_ids: Array[String] = []

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


## 创建一枚招牌按钮；is_global=true 用暖金基调且不随屏高亮。
func _add_tab_button(id: String, text: String, is_global: bool) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(SIGN_WIDTH, SIGN_HEIGHT)
	btn.focus_mode = Control.FOCUS_NONE
	btn.modulate = GLOBAL_MOD if is_global else INACTIVE_MOD
	btn.pivot_offset = Vector2(SIGN_WIDTH / 2.0, 0.0) ## 顶部中点=枢轴，供阶段3摆动
	btn.pressed.connect(_on_tab_pressed.bind(id))
	_row.add_child(btn)
	_buttons[id] = btn
	if is_global:
		_global_ids.append(id)


func _on_tab_pressed(id: String) -> void:
	tab_selected.emit(id)


## 由外部同步激活高亮（main 监听 ScreenManager.screen_changed 后调用）。
## id 传 home/farm/wardrobe/workshop 之一；全局入口（仓库）始终暖金、不参与高亮。
func set_active(id: String) -> void:
	_current = id
	for bid in _buttons:
		var b: Button = _buttons[bid]
		if is_instance_valid(b):
			if _global_ids.has(bid):
				b.modulate = GLOBAL_MOD
			else:
				b.modulate = ACTIVE_MOD if bid == id else INACTIVE_MOD


## 取某 tab 的按钮节点（供阶段 3 招牌摆动动画）；无则返回 null
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
