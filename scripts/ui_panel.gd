extends Control
## UIPanel · 右侧滑出 UI 面板
##
## 组成：
##   - Tab (TextureButton)  面板本体（展示 ui2.png，点击切换展开/收起）
##   - Content (Control)  内容容器（放置菜单按钮/标签等）
##
## 行为：
##   默认隐藏在右侧（只露出右边缘），点击面板滑出，再点收回

signal toggled(open: bool)
signal wardrobe_requested()

const PANEL_WIDTH := 200
const TAB_VISIBLE := 24
const SLIDE_DURATION := 0.3

var _open := false

@onready var _tab: TextureButton = $Tab
@onready var _wardrobe_btn: Button = $Content/WardrobeButton


func _ready() -> void:
	_tab.pressed.connect(_on_tab_pressed)
	_wardrobe_btn.pressed.connect(func(): wardrobe_requested.emit())
	position.x = _parent_width() - TAB_VISIBLE


func _parent_width() -> float:
	var p := get_parent()
	if p is Control:
		return (p as Control).size.x
	return 0.0


func _on_tab_pressed() -> void:
	_open = not _open
	var target_x := _parent_width() - (PANEL_WIDTH if _open else TAB_VISIBLE)
	var tween := create_tween()
	tween.tween_property(self, "position:x", target_x, SLIDE_DURATION)\
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	toggled.emit(_open)
