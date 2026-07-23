extends MarginContainer
class_name FocusBar
## FocusBar · 番茄钟常驻专注条（右下角，绘制序最高）
##
## 番茄钟进行中由 Main 显示；玩家点「最小化专注条」→ Main 缩条（仅显此条），
## 点「展开」→ Main 恢复游戏。萎缩态/展开态均由 Main 控制游戏主内容显隐。
## 数据实时读 GameManager：剩余时间 / 总时长 / 活动名 / 打断次数 / 完成百分比。

signal request_minimize   ## 玩家请求进入缩条态
signal request_expand     ## 玩家请求恢复游戏主界面

var _focus_mode := false

var _title: Label          ## 子节点均在 _build_children() 中手动 new()，非场景树获取，故不用 @onready
var _countdown: Label
var _progress: ProgressBar
var _toggle: Button
var _cancel_btn: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", _panel_style())
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 80)
	_build_children()
	GameManager.activity_finished.connect(_on_activity_ended)
	GameManager.activity_cancelled.connect(_on_activity_ended)
	GameManager.activity_interrupted.connect(_on_interrupted)
	GameManager.activity_started.connect(_refresh_title)
	_refresh_title()
	_update_dynamic()


func _build_children() -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	add_child(hb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)

	_title = Label.new()
	_title.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	_title.add_theme_font_size_override("font_size", 14)
	vb.add_child(_title)

	_countdown = Label.new()
	_countdown.add_theme_color_override("font_color", UITheme.TEXT_GOLD)
	_countdown.add_theme_font_size_override("font_size", 22)
	vb.add_child(_countdown)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 10)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.show_percentage = false
	_progress.add_theme_stylebox_override("bg", _bar_style(UITheme.BG_SURFACE))
	_progress.add_theme_stylebox_override("fg", _bar_style(UITheme.BG_ACCENT))
	hb.add_child(_progress)

	_toggle = Button.new()
	_toggle.custom_minimum_size = Vector2(64, 0)
	_toggle.pressed.connect(_on_toggle_pressed)
	hb.add_child(_toggle)

	_cancel_btn = Button.new()
	_cancel_btn.text = "×"
	_cancel_btn.custom_minimum_size = Vector2(36, 0)
	_cancel_btn.tooltip_text = "放弃本次专注（无奖励）"
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	hb.add_child(_cancel_btn)


func _refresh_title() -> void:
	_title.text = GameManager.get_active_activity_name()


func _update_dynamic() -> void:
	var rem := GameManager.get_remaining_sec()
	_countdown.text = Utils.format_time(rem)
	var total := GameManager.get_activity_total_sec()
	if total > 0.0:
		_progress.value = clampf(100.0 * (1.0 - rem / total), 0.0, 100.0)
	else:
		_progress.value = 0.0
	var n := GameManager.get_activity_interrupts()
	_progress.tooltip_text = ("中断 %d 次" % n) if n > 0 else "专注中"
	var st := GameManager.get_activity_streak()
	_title.text = GameManager.get_active_activity_name() + ("  🔥%d" % st if st >= 1 else "")
	if _toggle != null:
		_toggle.text = "展开" if _focus_mode else "最小化"
		_toggle.tooltip_text = ("展开游戏界面" if _focus_mode else "收起为专注条（去做现实中的事）")


func _process(_delta: float) -> void:
	if visible and GameManager.is_activity_running() and GameManager.get_activity_mode() == ActivityData.Mode.POMODORO:
		_update_dynamic()


func _on_toggle_pressed() -> void:
	if _focus_mode:
		request_expand.emit()
	else:
		request_minimize.emit()


func _on_cancel_pressed() -> void:
	GameManager.cancel_activity()


## 由 Main 在缩条/展开切换时调用，仅更新文案与内部状态
func set_focus_collapsed(on: bool) -> void:
	_focus_mode = on
	if _toggle != null:
		_toggle.text = "展开" if on else "最小化"


func _on_activity_ended(_p := {}) -> void:
	visible = false


## 番茄钟进行中发生打断 → 专注条闪红 + 标题提示，0.9s 后自动恢复
func _on_interrupted(_n: int) -> void:
	add_theme_stylebox_override("panel", _danger_style())
	_title.text = "⚠ 打断！灵感将减少"
	_title.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	await get_tree().create_timer(0.9).timeout
	if not is_instance_valid(self):   # 等待期间专注条可能被 queue_free（切场景/收起），避免访问已释放实例
		return
	add_theme_stylebox_override("panel", _panel_style())
	_refresh_title()


# 时间格式化已统一到 Utils.format_time（见 scripts/utils.gd）


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UITheme.BG_PANEL
	s.set_corner_radius_all(12)
	s.set_content_margin_all(12)
	return s


func _bar_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(5)
	return s


func _danger_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UITheme.BG_DANGER
	s.set_corner_radius_all(12)
	s.set_content_margin_all(12)
	return s
