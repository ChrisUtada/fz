class_name CustomerData
extends Resource
## CustomerData · 顾客数据模型（Resource / 纯数据）
##
## 职责：只描述"这是什么"——贴图、裁剪区域、缩放、奖励范围、抽取权重。
## 不持有任何节点或逻辑（数据-外观分离原则）。
##
## 消费方：顾客场景（customer.tscn / customer.gd）通过 apply_data() 读取本资源，
## 据此驱动外观（Sprite 贴图/裁剪/缩放）与订单奖励。场景负责"长成什么样"，数据只管"是什么"。
##
## 编辑方式：在 Godot 编辑器里选中本脚本 → 右键"另存为资源(.tres)"，或手动创建 .tres 引用本脚本。

@export var id: String = ""                       ## 唯一标识（存档/统计用）
@export var display_name: String = ""             ## 展示名（调试/日志用）
@export var texture: Texture2D                     ## 角色贴图（外观引用随数据一起管理）
@export var region_rect: Rect2 = Rect2()           ## 贴图裁剪区域（仅显示小人本体）
@export var base_scale: Vector2 = Vector2.ONE      ## 显示缩放
@export var gold_reward_min: int = 100             ## 金币奖励下限
@export var gold_reward_max: int = 100             ## 金币奖励上限
@export var inspiration_reward_min: int = 10       ## 灵感奖励下限
@export var inspiration_reward_max: int = 10       ## 灵感奖励上限
@export var spawn_weight: float = 1.0              ## 抽取权重（越大越常见）
