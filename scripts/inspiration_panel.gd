extends Control
## InspirationPanel · 灵感弹窗（覆盖层）
##
## 三个视图状态（同场景内切换）：
##   列表视图：从 activity_pool 数据驱动生成活动按钮
##   计时视图：选中活动后显示，HSlider + SpinBox 双向绑定设时
##   进行中视图：开始后台计时后显示，实时读 GameManager 剩余时间
##
## 计时由 GameManager 持有（墙钟时间戳 + 存档），本面板只负责 UI：
##   - 开始 → GameManager.start_activity()（后台继续，支持离线收益）
##   - 放弃 → GameManager.cancel_activity()
##   - 关闭 × → 仅收起弹窗，后台计时不中止
##   - 完成 → GameManager 自动发奖（HUD 滚动），弹窗收到 activity_finished 回列表
##
## 奖励 = 时长 × 每分钟灵感值（见 GameManager._compute_activity_reward）

const LIST_VIEW := 0
const TIMER_VIEW := 1
const RUNNING_VIEW := 2

@export var activity_pool: Array[ActivityData] = []

var _current_view: int = LIST_VIEW
var _current_activity: ActivityData
var _minutes: int = 25

## 初始化期间抑制 value_changed 回调
var _suppress: bool = false

@onready var _list_view: Control = $Card/Content/ListView
@onready var _timer_view: Control = $Card/Content/TimerView
@onready var _activity_list: VBoxContainer = $Card/Content/ListView/ActivityList
@onready var _close_button: Button = $Card/Content/TitleBar/CloseButton
@onready var _back_button: Button = $Card/Content/TimerView/BackButton
@onready var _activity_title: Label = $Card/Content/TimerView/ActivityTitle
@onready var _time_row: HBoxContainer = $Card/Content/TimerView/TimeRow
@onready var _slider: HSlider = $Card/Content/TimerView/TimeRow/HSlider
@onready var _spinbox: SpinBox = $Card/Content/TimerView/TimeRow/SpinBox
@onready var _countdown_box: Control = $Card/Content/TimerView/CountdownBox
@onready var _countdown_label: Label = $Card/Content/TimerView/CountdownBox/CountdownLabel
@onready var _start_button: Button = $Card/Content/TimerView/StartButton
@onready var _cancel_button: Button = $Card/Content/TimerView/CancelButton
@onready var _reward_hint: Label = $Card/Content/TimerView/RewardHint


func _ready() -> void:
	_close_button.pressed.connect(_on_close)
	_back_button.pressed.connect(_show_list)
	_start_button.pressed.connect(_on_start_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_slider.value_changed.connect(_on_slider_changed)
	_spinbox.value_changed.connect(_on_spinbox_changed)
	GameManager.activity_finished.connect(_on_activity_finished)

	# 先抑制回调，统一设好范围与初值，再放开，保证 _minutes 保持 25（不被夹值回调改掉）
	_suppress = true
	_slider.min_value = 1
	_slider.max_value = 60
	_slider.step = 1
	_slider.value = _minutes
	_spinbox.min_value = 1
	_spinbox.max_value = 60
	_spinbox.step = 1
	_spinbox.value = _minutes
	_suppress = false

	# 倒计时大字号，确保一眼可见
	_countdown_label.add_theme_font_size_override("font_size", 40)

	_populate_activities()

	# 打开时若后台已有进行中的活动，直接进入“进行中”视图
	if GameManager.is_activity_running():
		_show_running()
	else:
		_show_list()


# ═══════════════════ 列表视图（数据驱动） ═══════════════════

func _populate_activities() -> void:
	for child in _activity_list.get_children():
		child.queue_free()
	if activity_pool.is_empty():
		# 回退：无任何 .tres 时，给一个默认“阅读”按钮（@export 默认值）
		_add_activity_button(null)
		return
	for data in activity_pool:
		_add_activity_button(data)


func _add_activity_button(data: ActivityData) -> void:
	var btn := Button.new()
	if data != null:
		btn.text = "%s   ·   每分钟 +%.1f 灵感" % [data.activity_name, data.inspiration_per_minute]
	else:
		btn.text = "阅读   ·   每分钟 +0.4 灵感"
	btn.pressed.connect(func(): _open_activity(data))
	_activity_list.add_child(btn)


func _open_activity(data: ActivityData) -> void:
	if data != null:
		_current_activity = data
		_minutes = data.default_duration_minutes
		_activity_title.text = data.activity_name
	else:
		_current_activity = null
		_minutes = 25
		_activity_title.text = "阅读"
	_slider.value = _minutes
	_spinbox.value = _minutes
	_countdown_label.text = _format_time(float(_minutes) * 60.0)
	_update_reward_hint()
	_show_timer()


# ═══════════════════ 视图切换 ═══════════════════

func _show_list() -> void:
	_current_view = LIST_VIEW
	_list_view.visible = true
	_timer_view.visible = false


func _show_timer() -> void:
	_current_view = TIMER_VIEW
	_list_view.visible = false
	_timer_view.visible = true
	_back_button.visible = true
	_time_row.visible = true
	_start_button.visible = true
	_cancel_button.visible = false
	_countdown_box.visible = false
	_update_reward_hint()


func _show_running() -> void:
	_current_view = RUNNING_VIEW
	_list_view.visible = false
	_timer_view.visible = true
	_activity_title.text = GameManager.get_active_activity_name()
	_back_button.visible = false
	_time_row.visible = false
	_start_button.visible = false
	_cancel_button.visible = true
	_countdown_box.visible = true
	_update_countdown_label()


# ═══════════════════ 时间设定（滑条 + 输入框双向绑定） ═══════════════════

func _on_slider_changed(v: float) -> void:
	if _suppress:
		return
	_minutes = int(v)
	if _spinbox.value != _minutes:
		_spinbox.value = _minutes
	_countdown_label.text = _format_time(float(_minutes) * 60.0)
	_update_reward_hint()


func _on_spinbox_changed(v: float) -> void:
	if _suppress:
		return
	_minutes = int(v)
	if _slider.value != _minutes:
		_slider.value = _minutes
	_countdown_label.text = _format_time(float(_minutes) * 60.0)
	_update_reward_hint()


# ═══════════════════ 开始 / 放弃 / 完成 ═══════════════════

func _on_start_pressed() -> void:
	if _minutes < 1:
		_minutes = 1
	# 委托 GameManager：墙钟计时 + 存档（支持离线收益），本弹窗只显示
	GameManager.start_activity(_current_activity, _minutes)
	_show_running()


func _on_cancel_pressed() -> void:
	GameManager.cancel_activity()
	_show_list()


func _on_activity_finished(_reward: Dictionary) -> void:
	# 弹窗开着时自然完成 → 回列表（奖励已由 GameManager 发放，HUD 滚动）
	if _current_view == RUNNING_VIEW:
		_show_list()


func _process(_delta: float) -> void:
	if _current_view == RUNNING_VIEW and GameManager.is_activity_running():
		_update_countdown_label()


# ═══════════════════ 辅助 ═══════════════════

func _update_countdown_label() -> void:
	var rem := GameManager.get_remaining_sec()
	_countdown_label.text = _format_time(rem)
	_reward_hint.text = "进行中 · 预计获得 +%d 灵感值" % GameManager.get_pending_reward()


func _update_reward_hint() -> void:
	var per_min := 0.4
	if _current_activity != null:
		per_min = _current_activity.inspiration_per_minute
	var reward := int(ceil(float(_minutes) * per_min - 0.0001))
	_reward_hint.text = "预计获得 +%d 灵感值（每分钟 +%.1f）" % [reward, per_min]


func _format_time(total_sec: float) -> String:
	var s := int(ceil(total_sec))
	var m := s / 60
	var sec := s % 60
	return "%02d:%02d" % [int(m), sec]


func _on_close() -> void:
	queue_free()
