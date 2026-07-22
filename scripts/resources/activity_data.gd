class_name ActivityData
extends Resource
## ActivityData · 灵感活动数据（Resource，纯数据）
## 由 InspirationPanel 消费，描述一个“灵感活动”的配置。
## 在编辑器的检查器中填入：名称、图标、类型（mode）、相关参数、描述。
## 新增活动只需再加一个 ActivityData 的 .tres 资源并拖入 Main 的 activity_pool，零代码改动（OCP）。

enum Mode { POMODORO, OUTING }
##  POMODORO：番茄钟计时（阅读等），靠墙钟时长 × 每分钟灵感
##  OUTING：   外出，靠真实键鼠输入统计 × 每次输入灵感（步行仅动画，不计入）

@export var mode: Mode = Mode.POMODORO            ## 活动类型
@export var activity_name: String = "阅读"          ## 活动名称
@export var icon: Texture2D                          ## 活动图标（背包/列表预览）
@export var default_duration_minutes: int = 25      ## 默认时长（分钟），仅 POMODORO 用
@export var inspiration_per_minute: float = 0.4    ## 每分钟灵感，仅 POMODORO 用
@export var inspiration_per_action: float = 0.05   ## 每次键鼠输入灵感，仅 OUTING 用
@export var description: String = ""                ## 描述（可选）
