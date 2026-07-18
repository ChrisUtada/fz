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
##
## 交互：
##   拖入背包格子 → 装备（同部位自动替换）
##   轻点已装备部位 → 脱下（按绘制层级从上往下命中检测）
##   装备/脱下自动存档到 user://wardrobe.cfg，下次打开还原

const SAVE_PATH := "user://wardrobe.cfg"
const ITEM_SLOT_SCENE := preload("res://scenes/clothes/item_slot.tscn")

## 衣服数据池（@export，编辑器拖入 .tres 即用）
@export var clothes_pool: Array[ClothesData] = []

## 当前各部位装备状态（slot -> ClothesData）
var _equipped: Dictionary = {}
## 已装备贴图的内容包围盒缓存（Texture -> Rect2，纹理像素空间），用于精准命中检测
var _content_rect_cache: Dictionary = {}

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
	_char_area.clothes_unequip_requested.connect(_on_unequip_requested)
	_setup_layers()
	_load_outfit()
	_populate_backpack()


# ═══════════════════ 背包生成 ═══════════════════

func _populate_backpack() -> void:
	for child in _grid_container.get_children():
		child.queue_free()
	for item_data in clothes_pool:
		var slot: TextureButton = ITEM_SLOT_SCENE.instantiate()
		slot.setup(item_data)
		_grid_container.add_child(slot)


# ═══════════════════ 装备逻辑 ═══════════════════

func _on_clothes_dropped(data: ClothesData) -> void:
	if data != null:
		_equip(data)


## 执行装备：找到对应部位的 Sprite2D 层，仅设 texture（共享原点架构无需 offset）
func _equip(data: ClothesData) -> void:
	var layer: Sprite2D = _get_layer_for_slot(data.slot)
	if layer == null:
		return
	layer.texture = data.texture
	layer.visible = true
	_equipped[data.slot] = data
	_save_outfit()


## 脱下指定部位的衣服
func _unequip(slot: int) -> void:
	var layer: Sprite2D = _get_layer_for_slot(slot)
	if layer != null:
		layer.texture = null
		layer.visible = false
		_equipped.erase(slot)
		_save_outfit()


## 轻点请求脱下：从最上层（绘制顺序最后）往下找被点中的已装备层
func _on_unequip_requested(global_pos: Vector2) -> void:
	var ordered := [_accessory_layer, _feet_layer, _body_layer, _head_layer]
	for layer in ordered:
		if layer == null or layer.texture == null or not layer.visible:
			continue
		if _point_hits_layer(layer, global_pos):
			_unequip(_slot_for_layer(layer))
			return


## 判断全局坐标点是否落在某装备层的实际绘制像素内（非透明区域）
func _point_hits_layer(layer: Sprite2D, global_pos: Vector2) -> bool:
	var tex: Texture2D = layer.texture
	var size := tex.get_size()
	# to_local 已含父级 scale/位移，local 为 sprite 未缩放局部坐标（centered 原点居中）
	var local := layer.to_local(global_pos)
	var px := local.x + size.x * 0.5
	var py := local.y + size.y * 0.5
	if px < 0.0 or py < 0.0 or px >= size.x or py >= size.y:
		return false
	return _content_rect_for(tex).has_point(Vector2(px, py))


func _slot_for_layer(layer: Sprite2D) -> int:
	if layer == _head_layer:
		return ClothesData.Slot.HEAD
	if layer == _body_layer:
		return ClothesData.Slot.BODY
	if layer == _feet_layer:
		return ClothesData.Slot.FEET
	if layer == _accessory_layer:
		return ClothesData.Slot.ACCESSORY
	return -1


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


# ═══════════════════ 存档 ═══════════════════

## 取贴图实际绘制区域（非透明像素包围盒），缓存避免重复计算
func _content_rect_for(tex: Texture2D) -> Rect2:
	if _content_rect_cache.has(tex):
		return _content_rect_cache[tex]
	var rect := _compute_content_rect(tex)
	_content_rect_cache[tex] = rect
	return rect


func _compute_content_rect(tex: Texture2D) -> Rect2:
	var img := tex.get_image()
	if img == null:
		return Rect2(Vector2.ZERO, tex.get_size())
	return img.get_used_rect()


## 持久化当前装备：把每个部位的 ClothesData 资源路径写入 ConfigFile
func _save_outfit() -> void:
	var cfg := ConfigFile.new()
	for slot in _equipped.keys():
		var data: ClothesData = _equipped[slot]
		if data != null and not data.resource_path.is_empty():
			cfg.set_value("equipped", slot, data.resource_path)
	cfg.save(SAVE_PATH)


## 还原存档：读取 ConfigFile，按部位重新套上对应衣物
func _load_outfit() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for slot_str in cfg.get_section_keys("equipped"):
		var slot := int(slot_str)
		var path: String = cfg.get_value("equipped", slot_str, "")
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var data := load(path) as ClothesData
		if data == null:
			continue
		var layer: Sprite2D = _get_layer_for_slot(slot)
		if layer == null:
			continue
		layer.texture = data.texture
		layer.visible = true
		_equipped[slot] = data


func _on_close() -> void:
	queue_free()
