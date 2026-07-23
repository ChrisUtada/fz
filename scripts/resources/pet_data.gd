class_name PetData
extends Resource
## PetData · 宠物数据模型（Resource / 纯数据）
##
## 职责：只描述"这只宠物是什么 + 怎么走"——贴图、裁剪、缩放、行走参数、抽取权重。
## 不持有节点/逻辑（数据-外观分离原则）。
##
## 消费方：宠物场景（pet.tscn / pet.gd）通过 apply_data() 读取本资源，
## 据此驱动外观（Sprite 贴图/裁剪/缩放）与行走行为。场景负责"长成什么样 + 怎么动"，数据只管"是什么"。

@export var id: String = ""                       ## 唯一标识
@export var display_name: String = ""             ## 展示名
@export var texture: Texture2D                     ## 宠物贴图（外观引用随数据一起管理）
@export var region_rect: Rect2 = Rect2(0, 0, 736, 414)  ## 贴图裁剪区域（仅显示宠物本体）；默认整图，漏填也不至于贴图不可见
@export var base_scale: Vector2 = Vector2.ONE      ## 显示缩放
@export var walk_speed: float = 60.0               ## 行走速度（px/s）
@export var bob_amplitude: float = 4.0             ## 上下浮动幅度（px）
@export var bob_frequency: float = 3.0             ## 浮动频率
@export var edge_margin: float = 50.0              ## 超出屏幕多少判定消失
@export var spawn_weight: float = 1.0              ## 抽取权重（越大越常见）
