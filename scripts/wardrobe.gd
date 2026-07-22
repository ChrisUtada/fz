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
##
## 阶段 0.4：服装并入统一 inventory。
##   - 背包只展示「已拥有」服装（GameManager.get_by_category(CLOTHING)）
##   - 穿搭状态存于 GameManager.equipped（slot -> item_id），本场景不再自持久化；
##     打开时从 GameManager 还原，装备/脱下即时同步给 GameManager 存档。

const ITEM_SLOT_SCENE := preload("res://scenes/clothes/item_slot.tscn")

## 衣服数据池（@export，编辑器拖入 .tres 即用）；作为回退/兜底，主数据源是统一 inventory
@export var clothes_pool: Array[ClothesData] = []

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
	GameManager.equipped_changed.connect(_refresh_worn_badges)
	_setup_layers()
	_load_outfit()
	_populate_backpack()
	# 作为常驻切屏时：每次重新可见都从 GameManager 全量同步（穿搭 + 背包），
	# 避免隐藏期间 inventory/equipped 变化导致内容失效。
	visibility_changed.connect(_on_visibility_changed)


## 切屏可见即刷新：重置图层→按 equipped 还原穿搭→重建背包（已拥有服装）
func _on_visibility_changed() -> void:
	if not visible:
		return
	_setup_layers()
	_load_outfit()
	_populate_backpack()


# ═══════════════════ 背包生成 ═══════════════════

## 背包 = 已拥有的服装（统一 inventory 的 CLOTHING 分类）。
## 每个拥有的 id 展示一个格子；元数据经注册表解析回 ClothesData 取贴图。
func _populate_backpack() -> void:
	for child in _grid_container.get_children():
		child.queue_free()
	for item_data in _owned_clothes():
		var slot: TextureButton = ITEM_SLOT_SCENE.instantiate()
		slot.setup(item_data)
		_grid_container.add_child(slot)


## 装备/脱下后实时刷新所有格子的「穿戴中」标签（由 equipped_changed 信号驱动）
func _refresh_worn_badges() -> void:
	for slot in _grid_container.get_children():
		if slot.has_method("update_worn_status"):
			slot.update_worn_status()


## 衣橱 = 永久收藏：读 GameManager.unlocked_clothes（已解锁/已制作过的服装）。
## 与 inventory 当前数量解耦——即使某件售罄归零，也始终留在衣橱里可穿搭；
## 「拥有多少件」由仓库面板（读 inventory）负责，互不干扰。
func _owned_clothes() -> Array:
	var out: Array = []
	for id in GameManager.unlocked_clothes.keys():
		var d: ItemData = GameManager.get_item(id)
		if d != null and d is ClothesData:
			out.append(d)
	return out


# ═══════════════════ 装备逻辑 ═══════════════════

func _on_clothes_dropped(data: ClothesData) -> void:
	if data != null:
		_equip(data)


## 执行装备：找到对应部位的 Sprite2D 层，仅设 texture（共享原点架构无需 offset）
## 穿搭状态同步给 GameManager.equipped（自持久化）；所有权不变（仍在 inventory）。
func _equip(data: ClothesData) -> void:
	var layer: Sprite2D = _get_layer_for_slot(data.slot)
	if layer == null:
		return
	layer.texture = data.texture
	layer.visible = true
	GameManager.equip(data.slot, data.id)


## 脱下指定部位的衣服
func _unequip(slot: int) -> void:
	var layer: Sprite2D = _get_layer_for_slot(slot)
	if layer != null:
		layer.texture = null
		layer.visible = false
		GameManager.unequip(slot)


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


## 还原穿搭：从 GameManager.equipped（slot -> item_id）读取，
## 经注册表把 id 解析回 ClothesData，套上对应部位的贴图。
func _load_outfit() -> void:
	for slot in GameManager.equipped.keys():
		var item_id: String = GameManager.equipped[slot]
		var data := GameManager.get_item(item_id) as ClothesData
		if data == null:
			continue
		var layer: Sprite2D = _get_layer_for_slot(int(slot))
		if layer == null:
			continue
		layer.texture = data.texture
		layer.visible = true


func _on_close() -> void:
	queue_free()
