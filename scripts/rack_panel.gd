extends Control
## RackPanel · 上架面板（阶段 4.3）
##
## 6 槽网格：已上架显示图标 + 名称 + 可售库存(=拥有−穿戴) + 下架按钮；
## 空槽可点选上架。点空槽 → 下方列出「可上架服装」（拥有−穿戴 > 0 且尚未上架），点一件即上架到该槽；
## 每款衣物仅可占一个槽（同款不会重复上架分裂库存）。
## 监听 inventory_changed / equipped_changed / rack_changed 实时刷新（售出后自动补充/清空）。

signal closed()

const COLUMNS := 3

var _grid: GridContainer
var _hint: Label
var _picker: VBoxContainer
var _selected_slot: int = -1


func _ready() -> void:
	_build_ui()
	_populate()
	GameManager.inventory_changed.connect(_on_inv_changed)
	GameManager.equipped_changed.connect(_on_inv_changed)
	GameManager.rack_changed.connect(_populate)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UITheme.BG_PANEL
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 16.0
	layout.offset_top = 16.0
	layout.offset_right = -16.0
	layout.offset_bottom = -16.0
	add_child(layout)

	var title := Label.new()
	title.text = "服装展架"
	title.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	title.add_theme_font_size_override("font_size", 18)
	layout.add_child(title)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	layout.add_child(_grid)

	_hint = Label.new()
	_hint.text = "点击空槽选择要上架的服装"
	_hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	layout.add_child(_hint)

	_picker = VBoxContainer.new()
	layout.add_child(_picker)

	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(_on_close)
	layout.add_child(close)


## 重建 6 槽网格
func _populate() -> void:
	_clear(_grid)
	_clear(_picker)
	_selected_slot = -1
	_hint.text = "点击空槽选择要上架的服装"
	for slot in range(GameManager.clothing_rack.size()):
		var id: String = GameManager.get_rack_item(slot)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _slot_style())
		var vbox := VBoxContainer.new()
		card.add_child(vbox)
		if id.is_empty():
			var btn := Button.new()
			btn.text = "＋ 上架"
			btn.pressed.connect(_on_empty_slot_pressed.bind(slot))
			vbox.add_child(btn)
		else:
			var data: ItemData = GameManager.get_item(id)
			var icon := TextureRect.new()
			icon.texture = data.icon if (data != null and data.icon != null) else null
			icon.custom_minimum_size = Vector2(40, 40)
			vbox.add_child(icon)
			var name_lbl := Label.new()
			name_lbl.text = data.display_name if data != null else id
			name_lbl.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
			vbox.add_child(name_lbl)
			var stock := Label.new()
			stock.text = "可售 ×%d" % GameManager.get_rack_stock(id)
			stock.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
			vbox.add_child(stock)
			var undisplay := Button.new()
			undisplay.text = "下架"
			undisplay.pressed.connect(GameManager.undisplay.bind(slot))
			vbox.add_child(undisplay)
		_grid.add_child(card)


func _on_empty_slot_pressed(slot: int) -> void:
	_selected_slot = slot
	_show_picker(slot)


func _show_picker(slot: int) -> void:
	_clear(_picker)
	_hint.text = "为槽 %d 选择服装（每款仅可上架一个槽）" % (slot + 1)
	var list := GameManager.get_displayable_clothing()
	if list.is_empty():
		var none := Label.new()
		none.text = "暂无可上架服装（需拥有且未全穿在身上）"
		none.add_theme_color_override("font_color", UITheme.TEXT_DANGER)
		_picker.add_child(none)
	else:
		for entry in list:
			var data: ItemData = entry["data"]
			var b := Button.new()
			b.text = "%s ×%d" % [data.display_name, entry["available"]]
			b.icon = data.icon if data.icon != null else null
			b.pressed.connect(_on_pick.bind(slot, entry["id"]))
			_picker.add_child(b)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(_on_cancel_pick)
	_picker.add_child(cancel)


func _on_pick(slot: int, id: String) -> void:
	GameManager.display_clothing(slot, id)
	# display_clothing 已 emit rack_changed → _populate 自动刷新


func _on_cancel_pick() -> void:
	_selected_slot = -1
	_hint.text = "点击空槽选择要上架的服装"
	_clear(_picker)


func _on_inv_changed(_v = null) -> void:
	_populate()


func _on_close() -> void:
	closed.emit()
	queue_free()


func _clear(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()


func _slot_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UITheme.BG_SURFACE
	s.set_corner_radius_all(6)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
