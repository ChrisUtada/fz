extends Control
## ReceiptPanel · 收货清单弹窗（覆盖层）
##
## 列出 GameManager.get_arrived() 全部待收货物；点「确认收货」→
## GameManager.confirm_receipt()（解锁进仓库 + 清空待收）→ 关闭弹窗。
## 若无待收，显示提示并隐藏确认按钮。

@export var product_pool: Array[ProductData] = []

@onready var _list: VBoxContainer = $Card/Content/ItemList
@onready var _empty_label: Label = $Card/Content/EmptyLabel
@onready var _confirm_btn: Button = $Card/Content/ConfirmButton
@onready var _close_btn: Button = $Card/Content/TitleBar/CloseButton


func _ready() -> void:
	var bg := $Card/Bg as ColorRect
	if bg != null:
		bg.color = UITheme.BG_PANEL
	var title := $Card/Content/TitleBar/Title as Label
	if title != null:
		title.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	_confirm_btn.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	_close_btn.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	_close_btn.pressed.connect(_on_close)
	_confirm_btn.pressed.connect(_on_confirm)
	_ensure_pool()
	_populate()


func _ensure_pool() -> void:
	if not product_pool.is_empty():
		return
	for path in ["res://data/product_chair.tres", "res://data/product_desk.tres", "res://data/product_lamp.tres"]:
		var res = load(path)
		if res != null:
			product_pool.append(res)


func _populate() -> void:
	for c in _list.get_children():
		c.queue_free()
	var arrived: Array = GameManager.get_arrived()
	if arrived.is_empty():
		_empty_label.visible = true
		_confirm_btn.visible = false
		return
	_empty_label.visible = false
	_confirm_btn.visible = true
	for a in arrived:
		var p: ProductData = _find_product(a["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := _make_icon(p)
		var name_l := Label.new()
		name_l.text = a["name"]
		name_l.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(icon)
		row.add_child(name_l)
		_list.add_child(row)


func _find_product(id: String) -> ProductData:
	for p in product_pool:
		if p != null and p.id == id:
			return p
	return null


func _make_icon(p: ProductData) -> Control:
	if p != null and p.icon != null:
		var tex := TextureRect.new()
		tex.texture = p.icon
		tex.custom_minimum_size = Vector2(32, 32)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex
	var ph := ColorRect.new()
	ph.color = UITheme.BG_SURFACE
	ph.custom_minimum_size = Vector2(32, 32)
	return ph


func _on_confirm() -> void:
	GameManager.confirm_receipt()
	queue_free()


func _on_close() -> void:
	queue_free()
