extends Control
## AlignTool · 衣物可视化对齐工具（开发期工具，非运行时功能）
##
## 用途：用鼠标拖动每件衣物到 zz 人物身上的正确位置，点「保存」自动写回 .tres。
##       无需手填 equip_offset 数字，所见即所得。
##
## 用法：在 Godot 编辑器中打开 scenes/clothes/align_tool.tscn，按 F6（运行当前场景）。
##       ① 侧栏点选一件衣服 ② 在人物身上拖动到正确位置 ③ 点「保存当前」或「全部保存」
##       保存后重新运行主游戏即可看到对齐效果。
##
## 注意：res:// 在导出后只读，本工具仅在编辑器/开发期使用。

const CLOTHES_PATHS := {
	"hat": "res://data/clothes_hat.tres",
	"shirt": "res://data/clothes_shirt.tres",
	"skirt": "res://data/clothes_skirt.tres",
	"shoe": "res://data/clothes_shoe.tres",
	"gt": "res://data/clothes_gt.tres",
}

var _datas: Dictionary = {}        ## key -> ClothesData
var _sprites: Dictionary = {}      ## key -> Sprite2D
var _keys: Array = []              ## 有序 key 列表（对应 ItemList 顺序）
var _active_key: String = ""
var _dragging := false
var _drag_offset := Vector2.ZERO

@onready var _base_sprite: TextureRect = $CharacterArea/BaseSprite
@onready var _layers: Node2D = $CharacterArea/AlignLayers
@onready var _item_list: ItemList = $SidePanel/ItemList
@onready var _offset_label: RichTextLabel = $SidePanel/OffsetLabel
@onready var _show_all_check: CheckBox = $SidePanel/ShowAllCheck


func _ready() -> void:
	_base_sprite.texture = load("res://assets/clothes/zz.png")
	_populate()
	_refresh_visibility()
	_update_offset_label()


## 加载所有 .tres，为每件创建一个可拖动 Sprite2D
func _populate() -> void:
	for key in CLOTHES_PATHS:
		var data: ClothesData = load(CLOTHES_PATHS[key])
		_datas[key] = data
		_keys.append(key)

		var sprite := Sprite2D.new()
		sprite.texture = data.texture
		sprite.position = data.equip_offset
		sprite.name = key.capitalize()
		_layers.add_child(sprite)
		_sprites[key] = sprite

		_item_list.add_item(data.display_name)

	_item_list.select(0)
	_active_key = _keys[0]


# ═══════════════════ 拖拽交互 ═══════════════════

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_start_drag()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var local := _layers.to_local(get_global_mouse_position())
		_sprites[_active_key].position = local + _drag_offset
		_update_offset_label()


## 尝试开始拖动当前选中的衣物（点击落在其贴图矩形内即抓取）
func _try_start_drag() -> void:
	if _active_key == "":
		return
	var sprite: Sprite2D = _sprites[_active_key]
	if sprite == null or sprite.texture == null:
		return
	var local := _layers.to_local(get_global_mouse_position())
	# Sprite2D.get_rect() 返回以 sprite 原点为中心的局部矩形，转换到父空间判断
	if sprite.get_rect().has_point(local - sprite.position):
		_dragging = true
		_drag_offset = sprite.position - local


# ═══════════════════ 侧栏交互 ═══════════════════

func _on_item_selected(index: int) -> void:
	if index >= 0 and index < _keys.size():
		_active_key = _keys[index]
		_refresh_visibility()
		_update_offset_label()


func _on_show_all_toggled(button_pressed: bool) -> void:
	_refresh_visibility()


## 根据选中状态 + 显示全部开关，控制各 Sprite 可见性
func _refresh_visibility() -> void:
	var show_all := _show_all_check.button_pressed
	for key in _sprites:
		var s: Sprite2D = _sprites[key]
		if show_all:
			s.visible = true
			s.modulate.a = 0.5 if key != _active_key else 1.0
		else:
			s.visible = (key == _active_key)
			s.modulate.a = 1.0


## 实时显示当前选中衣物的 offset（拖动时同步更新）
func _update_offset_label() -> void:
	if _active_key == "":
		_offset_label.text = "未选中"
		return
	var s: Sprite2D = _sprites[_active_key]
	var d: ClothesData = _datas[_active_key]
	var text := "[b]%s[/b]\n" % d.display_name
	text += "equip_offset = Vector2(%.0f, %.0f)\n" % [s.position.x, s.position.y]
	text += "\n[size=11]拖动衣物到正确位置后点「保存」[/size]"
	_offset_label.text = text


# ═══════════════════ 保存 / 重置 ═══════════════════

## 保存当前选中衣物的 offset 到对应 .tres
func _on_save_current() -> void:
	if _active_key == "":
		return
	_save_one(_active_key)


## 保存所有衣物的 offset
func _on_save_all() -> void:
	for key in _keys:
		_save_one(key)
	print("[align] 全部保存完成（", _keys.size(), " 件）")


func _save_one(key: String) -> void:
	var data: ClothesData = _datas[key]
	var sprite: Sprite2D = _sprites[key]
	data.equip_offset = sprite.position
	var err := ResourceSaver.save(data, CLOTHES_PATHS[key])
	if err == OK:
		print("[align] 已保存 %s -> offset=%s" % [data.display_name, sprite.position])
	else:
		push_error("[align] 保存失败 %s err=%d" % [data.display_name, err])


## 重置当前衣物 offset 为 (0,0)
func _on_reset_current() -> void:
	if _active_key == "":
		return
	_sprites[_active_key].position = Vector2.ZERO
	_update_offset_label()


## 微调：按方向键移动当前衣物 1 像素（Shift+方向键 10 像素）
func _unhandled_input(event: InputEvent) -> void:
	if _active_key == "":
		return
	if event is InputEventKey and event.pressed:
		var step := 10.0 if event.shift_pressed else 1.0
		var sprite: Sprite2D = _sprites[_active_key]
		match event.keycode:
			KEY_LEFT:
				sprite.position.x -= step
				_update_offset_label()
			KEY_RIGHT:
				sprite.position.x += step
				_update_offset_label()
			KEY_UP:
				sprite.position.y -= step
				_update_offset_label()
			KEY_DOWN:
				sprite.position.y += step
				_update_offset_label()


func _on_close() -> void:
	get_tree().quit()
