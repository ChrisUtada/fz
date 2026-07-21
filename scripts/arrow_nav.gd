extends Control
class_name ArrowNav
## ArrowNav · 活动面板左右两侧箭头切换（阶段 1 · 步骤 1.5）
##
## 职责（单一）：在三个切换屏（换装/种植/工坊）活动时，于面板左右边缘、垂直居中
##   各显示一枚箭头按钮（‹ / ›），点击 → ScreenManager.prev/next_screen。
##   复用 show_screen 路径，使底部招牌高亮同步（视觉反馈一致）。
##   家园态（home）与仓库全局浮层打开时隐藏（仓库浮层可由 set_overlay_blocked 屏蔽）。
##
## 设计原则：
##   - 低耦合：仅依赖 ScreenManager（显示/隐藏 + 切屏），不认识具体屏内容。
##   - 自身不切屏：只转发到 ScreenManager.next/prev（循环顺序由 ScreenManager._order 决定）。
##   - 根节点 mouse_filter=IGNORE，点击穿透到下层屏；仅两枚按钮 mouse_filter=STOP 拦截。

const SWITCH_SCREENS := ["wardrobe", "farm", "workshop"]

var _screen_manager: ScreenManager = null
var _last_id: String = ""
var _blocked: bool = false

@onready var left_btn: Button = $LeftArrow
@onready var right_btn: Button = $RightArrow


## 由 main 调用注入 ScreenManager 并接通信号（避免硬编码路径搜索）。
func setup(sm: ScreenManager) -> void:
	_screen_manager = sm
	left_btn.pressed.connect(_on_prev)
	right_btn.pressed.connect(_on_next)
	sm.screen_changed.connect(_on_screen_changed)
	_last_id = sm.current_screen
	_refresh()


func _on_prev() -> void:
	if _screen_manager != null:
		_screen_manager.prev_screen()


func _on_next() -> void:
	if _screen_manager != null:
		_screen_manager.next_screen()


func _on_screen_changed(id: String) -> void:
	_last_id = id
	_refresh()


## 仓库等全局浮层打开时屏蔽箭头（浮层盖在屏之上，箭头无意义）。
func set_overlay_blocked(blocked: bool) -> void:
	_blocked = blocked
	_refresh()


func _refresh() -> void:
	visible = not _blocked and _last_id in SWITCH_SCREENS


## 可选：键盘 ← / → 同效（仅箭头可见时生效，避免干扰家园拖拽等）。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT:
			get_viewport().set_input_as_handled()
			_on_prev()
		elif event.keycode == KEY_RIGHT:
			get_viewport().set_input_as_handled()
			_on_next()
