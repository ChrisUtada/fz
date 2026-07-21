extends Control
## WarehousePanel · 仓库图鉴弹窗（覆盖层）
##
## 收集图鉴：从 product_pool 展示全集。
##   - 已拥有（GameManager.has_product(id)）：显示图标 + 名称
##   - 未拥有：显示「?」占位 + 名称「？？？」
## 网格布局。

signal placement_requested(data: ProductData)   ## 已拥有物品点击「摆放」时发出，由 Main 转发给 PlacementManager

@export var product_pool: Array[ProductData] = []

@onready var _grid: GridContainer = $Card/Content/Grid
@onready var _close_btn: Button = $Card/Content/TitleBar/CloseButton


func _ready() -> void:
	_close_btn.pressed.connect(_on_close)
	_ensure_pool()
	_populate()
	# 作为常驻切屏时：每次重新可见都重建网格，反映隐藏期间新到货/新拥有的物品。
	visibility_changed.connect(_on_visibility_changed)


## 切屏可见即刷新：重建图鉴网格（拥有态可能已变化）
func _on_visibility_changed() -> void:
	if visible:
		_populate()


func _ensure_pool() -> void:
	if not product_pool.is_empty():
		return
	for path in ["res://data/product_chair.tres", "res://data/product_desk.tres", "res://data/product_lamp.tres"]:
		var res = load(path)
		if res != null:
			product_pool.append(res)


func _populate() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for p in product_pool:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var owned: bool = GameManager.has_product(p.id)
		var icon := _make_icon(p, owned)
		var name_l := Label.new()
		name_l.text = p.display_name if owned else "？？？"
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(icon)
		cell.add_child(name_l)
		if owned:
			var place_btn := Button.new()
			place_btn.text = "摆放"
			place_btn.add_theme_font_size_override("font_size", 14)
			place_btn.pressed.connect(func(): placement_requested.emit(p))
			cell.add_child(place_btn)
		_grid.add_child(cell)


func _make_icon(p: ProductData, owned: bool) -> Control:
	if owned and p.icon != null:
		var tex := TextureRect.new()
		tex.texture = p.icon
		tex.custom_minimum_size = Vector2(56, 56)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex
	# 未拥有：问号占位
	var q := Label.new()
	q.text = "?"
	q.add_theme_font_size_override("font_size", 36)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q.custom_minimum_size = Vector2(56, 56)
	return q


func _on_close() -> void:
	queue_free()
