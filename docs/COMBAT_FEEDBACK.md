# 战斗反馈与屏幕效果

`data/feedback.json` 是反馈强度的配置源，`DamageFeedbackManager` 负责事件分类、冷却、优先级、Hit Stop、镜头震动、慢动作、声音和 VFX。新伤害来源应传入 `Enemy.take_damage` 的 `source` 参数，不自行添加命中震屏。

| 类型 | Hit Stop | Shake | 慢动作窗口 |
|---|---:|---:|---:|
| 普通命中 | 0 ms | .01 | 0 |
| 暴击 | 8 ms | .035 | 0 |
| 爆头 | 12 ms | .045 | 0 |
| 精英击杀 | 30 ms | .18 | 220 ms |
| 多杀 | 18 ms | .12 | 120 ms |
| Boss 弱点 | 20 ms | .11 | 80 ms |
| 爆炸命中 | 5 ms | .025 | 0 |
| 元素命中 | 0 ms | 0 | 0 |

爆炸本体另发 `detonation`，Boss 砸地发 `boss_slam`。每类事件有冷却；70 ms 优先级窗口抑制较弱事件叠加震屏，Hit Stop 单次不超过 40 ms，慢动作窗口不超过 250 ms，并有 400 ms 重触发间隔。枪械开火反馈同样由管理器按武器配置调度。

屏幕后处理位于 HUD 下方，读取实际生命和中毒/燃烧状态。爆炸和 Boss 事件驱动尘埃与冲击波，效果随时间衰减。安全屋可以保存 Reduced Effects 开关：后处理强度 .2，震屏倍率 .25；血污和慢动作仍由各自设置控制。此时仍应保留关键的敌人攻击预警。

验证：`mutation-report.json` 24 项、`feedback-report.json` 25 项、`screen-report.json` 13 项、`environment-report.json` 21 项。截图为 `artifacts/mutations.png`、`screen-effects.png`、`screen-effects-reduced.png`。这些是功能证据，不代替真实玩家对手感的评价。
