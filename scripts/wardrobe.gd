extends Control
## Wardrobe · 换装场景（编排层）
##
## 架构：分层纸娃娃（Paper-Doll）+ 共享原点
##   所有 Sprite2D 位于 CharacterRoot 下，position=(0,0)，
##   由 CharacterRoot.scale=0.5 统一缩放。
##   美术资源按共享画布/原点规范导出 → 装备时仅设 texture，无需 offset。
##
## 组成：
##   CharacterArea (EquipTarget)
##     └─ CharacterRoot (Node2D, scale=0.5, 居中)
##        ├─ BaseSprite (Sprite2D, zz.png)
##        └─ EquipLayers (Node2D)
##           ├─ HeadLayer / BodyLayer / FeetLayer / AccessoryLayer
##   BackpackArea (Panel) → GridContainer → ItemSlot
##   CloseButton

signal closed()

## 衣服数据池（@export，编辑器拖入 .tres 即用）
@export var clothes_pool: Array[ClothesData] = []

## 当前各部位装备状态（slot -> ClothesData）
var _equipped: Dictionary = {}

@onready var _char_area: Control = $CharacterArea
@onready var _equip_layers: Node2D = $CharacterArea/CharacterRoot/EquipLayers
@onready var _head_layer: Sprite2D = $CharacterArea/CharacterRoot/EquipLayers/HeadLayer
@onready var _body_layer: Sprite2D = $CharacterArea/CharacterRoot/EquipLayers/BodyLayer
@onready var _feet_layer: Sprite2D = $CharacterArea/CharacterRoot/EquipLayers/FeetLayer
@onready var _accessory_layer: Sprite2D = $CharacterArea/CharacterRoot/EquipLayers/AccessoryLayer
@onready var _grid_container: GridContainer = $BackpackArea/GridContainer
@onready var _close_button: Button = $CloseButton


func _ready() -> void:
	_close_button.pressed.connect(_on_close)
	_char_area.clothes_dropped.connect(_on_clothes_dropped)
	_populate_backpack()
	_setup_layers()


# ═══════════════════ 背包生成 ═══════════════════

func _populate_backpack() -> void:
	for child in _grid_container.get_children():
		child.queue_free()
	for item_data in clothes_pool:
		var slot_scene := preload("res://scenes/clothes/item_slot.tscn")
		var slot: TextureButton = slot_scene.instantiate()
		slot.setup(item_data)
		_grid_container.add_child(slot)


# ═══════════════════ 装备逻辑 ═══════════════════

func _on_clothes_dropped(data: ClothesData) -> void:
	if data == null:
		return
	_equip(data)


## 执行装备：找到对应部位的 Sprite2D 层，仅设 texture（共享原点架构无需 offset）
func _equip(data: ClothesData) -> void:
	var layer: Sprite2D = _get_layer_for_slot(data.slot)
	if layer == null:
		return
	layer.texture = data.texture
	layer.visible = true
	_equipped[data.slot] = data
	print("[wardrobe] equipped ", data.display_name, " to slot ", data.slot)


## 脱下指定部位的衣服
func _unequip(slot: int) -> void:
	var layer: Sprite2D = _get_layer_for_slot(slot)
	if layer != null:
		layer.texture = null
		layer.visible = false
	_equipped.erase(slot)
	print("[wardrobe] unequipped slot ", slot)


func _get_layer_for_slot(slot: int) -> Sprite2D:
	match slot:
		ClothesData.Slot.HEAD:
			return _head_layer
		ClothesData.Slot.BODY:
			return _body_layer
		ClothesData.Slot.FEET:
			return _feet_layer
		ClothesData.Slot.ACCESSORY:
			return _accessory_layer
	return null


func _setup_layers() -> void:
	for layer in [_head_layer, _body_layer, _feet_layer, _accessory_layer]:
		if layer != null:
			layer.visible = false
			layer.texture = null


func _on_close() -> void:
	closed.emit()
	queue_free()
