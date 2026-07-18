class_name ClothesData
extends Resource
## ClothesData · 服装数据模型（Resource / 纯数据）
##
## 职责：只描述"这件衣服是什么"——穿着态贴图、背包预览图标、部位、价格、灵感值。
## 不持有节点/逻辑（数据-外观分离原则）。
##
## 重要前提：所有衣服贴图与人物底图共享同一画布尺寸和同一原点，
##          叠加时 layer.position = (0,0) 即可自动对齐，无需 equip_offset。
## 消费方：换装场景通过读取本资源，把衣服贴图套到人物对应部位并结算收益。
## 外观（如何显示、换装动画）由场景负责，数据只管属性。

enum Slot { HEAD, BODY, FEET, ACCESSORY }

@export var id: String = ""                       ## 唯一标识
@export var display_name: String = ""             ## 展示名

## 穿着态贴图（*_a.png）：与 zz 人物共享 736×414 画布，原点对齐（脚底中心）
## 程序中 layer.texture = data.texture 即可，无需额外位置计算
@export var texture: Texture2D

## 背包预览图标（*_b.png）：背包格子中显示的小图标（60×57）
@export var icon_texture: Texture2D

@export var slot: Slot = Slot.BODY                 ## 穿着部位
@export var price: int = 50                        ## 购买价（金币）
@export var inspiration_value: int = 5             ## 提供灵感值
