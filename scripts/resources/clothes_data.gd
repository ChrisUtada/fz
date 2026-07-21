class_name ClothesData
extends ItemData
## ClothesData · 服装数据模型（继承统一 ItemData）
##
## 职责：只描述"这件衣服是什么"——穿着态贴图、背包预览图标、部位、灵感值。
## 通用字段（id/display_name/icon/price/description/category…）继承自 ItemData；
## 本类只补充服装专属字段。不持有节点/逻辑（数据-外观分离原则）。
##
## 阶段 0.4：服装并入统一 inventory[category=CLOTHING]。
##   - 拥有（所有权）→ GameManager.inventory（id -> count）
##   - 穿搭（当前穿在身上）→ GameManager.equipped（slot -> item_id），与所有权分离
##
## 重要前提：所有衣服贴图与人物底图共享同一画布尺寸和同一原点，
##          叠加时 layer.position = (0,0) 即可自动对齐，无需 equip_offset。
##
## 注意：.tres 头部仍写 `[gd_resource type="Resource" script_class="ClothesData" ...]`，
##       id/display_name/price 落到基类照样读，无需改动现有 .tres。

enum Slot { HEAD, BODY, FEET, ACCESSORY }

## 穿着态贴图（*_a.png）：与 zz 人物共享 736×414 画布，原点对齐（脚底中心）
## 程序中 layer.texture = data.texture 即可，无需额外位置计算
@export var texture: Texture2D

## 背包预览图标（*_b.png）：背包格子中显示的小图标（60×57）
@export var icon_texture: Texture2D

@export var slot: Slot = Slot.BODY                 ## 穿着部位
@export var inspiration_value: int = 5             ## 提供灵感值


func _init() -> void:
	category = Category.CLOTHING
	price = 50   # 服装默认售价；.tres 若显式写 price 会在 _init 之后覆盖此默认
