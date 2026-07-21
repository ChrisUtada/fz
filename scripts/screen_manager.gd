extends Node
class_name ScreenManager
## ScreenManager · 屏幕显隐管理器（阶段 1 · 步骤 1.1）
##
## 职责（单一）：管理「家园 / 种植 / 换装 / 工坊」四个对等屏的互斥显隐，
##   保证任意时刻至多一个活动屏（并列，而非“家园为底层、其余覆盖其上”）。
##   四个主 tab 地位完全对等，均注册进本管理器；仓库是全局浮层（由 main 管理），不在此注册。
##
## 设计原则：
##   - 低耦合：本管理器不认识屏幕的具体内容，只按 id 操作 Control 的 show/hide。
##     屏幕由外部（main，步骤 1.3）实例化后经 register_screen 注册进来。
##   - SRP：只负责「哪个屏可见」，不负责创建屏幕、不处理输入、不管动画。
##   - 数据驱动切换：id 用 String（与 TabBar 的 tab_selected(id) / 箭头 next/prev 对齐）。
##
## 约定 id：见下方 SCREEN_* 常量。注册顺序即 next/prev 的循环顺序（= TabBar.TABS 顺序）。

# ─── 标准屏幕 id ───
const SCREEN_HOME := "home"            ## 家园屏（四个对等主 tab 之一，与其余三屏地位相同，均注册进本管理器）
const SCREEN_WARDROBE := "wardrobe"    ## 换装屏
const SCREEN_FARM := "farm"            ## 种植屏
const SCREEN_WORKSHOP := "workshop"    ## 工坊（制作）屏
## 注：仓库不再是切换屏，而是全局浮层（由 main 管理），故无 SCREEN_* 常量。

## 当前活动屏 id；取值为 home / farm / wardrobe / workshop 之一（四个对等屏）。
var current_screen: String = SCREEN_HOME

# id → Control 映射；_order 保留注册顺序（供 next/prev 循环）
var _screens: Dictionary = {}
var _order: Array[String] = []

## 活动屏变化时发出：id 为新屏 id。供 TabBar 高亮、招牌摆动、箭头高亮等 UI 联动监听（步骤 1.2 / 1.5）。
signal screen_changed(id: String)


## 注册一个屏幕。重复 id 覆盖旧引用（并从顺序表去重后按新顺序追加）。
## 注册即默认隐藏，保证初始为纯家园态（由 go_home 在 _setup_screens 末尾显示）。
func register_screen(id: String, screen: Control) -> void:
	if id.is_empty() or screen == null:
		push_warning("ScreenManager.register_screen: 非法 id 或空屏幕，已忽略")
		return
	_screens[id] = screen
	if not _order.has(id):
		_order.append(id)
	screen.hide()


## 显示指定屏，隐藏其余所有已注册屏。四个对等屏（含 home）统一按此处理，
## 故任意时刻仅一个屏可见——实现“并列”而非“覆盖”。id 未注册则警告并忽略。
func show_screen(id: String) -> void:
	if not _screens.has(id):
		push_warning("ScreenManager.show_screen: 未注册的屏 id = " + id)
		return
	for sid in _screens:
		var s: Control = _screens[sid]
		if is_instance_valid(s):
			s.visible = (sid == id)
	current_screen = id
	screen_changed.emit(id)


## 回到家园屏：显示 home 屏、隐藏其余三屏。home 现在与其它屏对等（也是已注册屏），故直接委托 show_screen。
## 公开方法：main 在 _setup_screens 末尾调用以进入初始家园态并高亮「家园」tab。
func go_home() -> void:
	show_screen(SCREEN_HOME)


## 隐藏所有屏（进入“无活动屏”空白态，仅留 Background / TabBar 等常驻层）。
## 注意：与 go_home 不同，本方法不显示 home。当前主要用于兜底/调试，日常切屏请用 show_screen / go_home。
func hide_all() -> void:
	for sid in _screens:
		var s: Control = _screens[sid]
		if is_instance_valid(s):
			s.hide()
	current_screen = ""
	screen_changed.emit("")


## 便捷：家园 tab → 已在家园则不动，否则回家园；其余 → 再点当前屏则收起回家园，否则显示。
func toggle_screen(id: String) -> void:
	if id == SCREEN_HOME:
		if current_screen == SCREEN_HOME:
			return
		go_home()
		return
	if current_screen == id:
		go_home()
	else:
		show_screen(id)


## 是否正在显示指定屏
func is_showing(id: String) -> bool:
	return current_screen == id


## 按注册顺序切到下一屏（循环）。当前无活动屏时切到第一个。供步骤 1.5 右箭头。
func next_screen() -> void:
	_step(1)


## 按注册顺序切到上一屏（循环）。当前无活动屏时切到最后一个。供步骤 1.5 左箭头。
func prev_screen() -> void:
	_step(-1)


func _step(dir: int) -> void:
	if _order.is_empty():
		return
	var idx := _order.find(current_screen)
	if idx == -1:
		# 无活动屏：右→第一个，左→最后一个
		idx = 0 if dir > 0 else _order.size() - 1
	else:
		idx = (idx + dir + _order.size()) % _order.size()
	show_screen(_order[idx])
