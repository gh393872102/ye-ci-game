# P11 庭院、守军与「晚」复审

2026-11-18。基线为公开评审提交 `877de42`，本轮标签为 `p11-courtyard-lantern-2026-11-18`。[设计标准图](https://gh393872102.github.io/ye-ci/) · [上轮报告](P11-revision.md)

## 1. 本阶段目标是否达到

三项修改均已进入 Godot 正式战场、角色卡或图鉴。默认战场保留主殿门与四条通行带，把院内的后墙压低，在鬼群背后露出整排湿石，在近景留出石沿。门内案后和窗后增设灯位，人物肩脸与衣缘受光。角色卡和图鉴共用从第 17 号稿还原的持灯肖像。美术结论待设计方按整帧签收，当前阶段为 P11。

## 2. 主要文件

- 场景绘制在 `src/world/MapDrawing.gd`，战场下缘在 `src/ui/CombatHUD.gd`。新铺装位于 `assets/sprites/world/inkshrine/courtyard-stones.png`。实际设施的建成、空置、损毁决定拒马、石脚和残件的显示。
- 人物材质在 `assets/sprites/units/p11r/lamplit.gdshader`，应用条件与鬼潮分排着色在 `src/units/UnitAppearance.gd`。递香与门骑落地分别在 `src/combat/vfx/IncenseSmoke.gd` 和 `BattleEffects.gd`。
- 晚的肖像在 `assets/portraits/p8/H01.png`，裁切来源和哈希在同目录 `H01.meta.json`，人脸框在 `data/units/p8_appearance.json`。

## 3. 如何运行与复核

Godot 4.7.2 stable，macOS，Apple M2 Pro。导入工程后按 F5，从标题进入「例夜 → 守香」并进入战斗。默认 1920 × 1080，切回 1×，观察门左侧院面及门右侧三层岗位。点击晚查看角色卡，在图鉴的守香人条目查看同一肖像。以下命令分别生成可重复的取帧场景和 JSON，每次使用独立临时存档。

```sh
python3 tools/p9_verify.py --native --input mouse --script tests/P11VFXSuite.gd
python3 tools/p9_verify.py --native --input mouse --script tests/P11WorldArtSuite.gd
python3 tools/p9_verify.py --native --input mouse --script tests/P9BattleUI.gd
python3 tools/p9_verify.py --native --input mouse --script tests/P11StorySuite.gd
```

## 4. 逐项自检与同构图对照

每张对照板的左上是设计稿，右上是 `877de42` 的完整实机帧，下方是本轮同一验收场景的完整实机帧。单独链接的 PNG 保留 1920 × 1080 原像素。

| 验收项 | 实机与测量 | 对照及原图 |
|---|---|---|
| 13 · 湿石庭院与拒马 | 从后墙到前沿画出 279 px 铺装。镜头左界仍是世界 x=6080，主殿门在屏幕 x=960。世界 x=6400 的拒马已建，x=6720 的桩位空置。48 只受控生成的鬼占四条实际通行带，每条在视口中数到 12 只。 | [三版对照](p11r2/compare-13.jpg) · [默认原图](p11r2/00-default-tide.png) · [横移看外院](p11r2/02-court-scroll.png) |
| 25 · 守军轮廓 | 同一群鬼继续行进 135 个固定步。4 名守军仍在案后、门内及上下层窗后，岗位灯照出头肩、手臂和衣缘。 | [三版对照](p11r2/compare-25.jpg) · [默认内防原图](p11r2/00a-inner-cover.png) |
| 24 · 香烟 | 灰白回卷烟带升到一层灯位附近，暗边从亮墙上勾出轮廓。同帧可找门上黄符、地面点册朱圈、二层青灯和三层弩矢。门骑融契另加两侧低溅影，保留坐骑与缰绳轮廓。 | [三版对照](p11r2/compare-24.jpg) · [五技能原图](p11r2/01-k4-five-skills.png) · [门骑原图](p11r2/07-fusion-arrival.png) |
| 17、20 · 晚 | 直接取第 17 号稿左上起 (94,120)、344 × 516 的肖像区域，经 Lanczos 重采样为 1024 × 1536。用 ImageMagick 从标准稿独立重建并比对交付图，像素 RMSE 为 0。角色卡与图鉴都保留原脸、束发、深色袍与手灯。 | [人物卡对照](p11r2/compare-17.jpg) · [人物卡原图](p11r2/17-reference-wan-card.png) · [图鉴对照](p11r2/compare-20.jpg) · [图鉴原图](p11r2/20-reference-codex-wan.png) |

原生窗口固定步检查共 250 项，失败 0 项。原始运行记录含各自整套测试的取帧清单，本次随报告精选上述七张。文件入库时按记录逐张核对 SHA-256。[战场与特效 41 项](p11r2/vfx.json) · [祠场与相机 15 项](p11r2/world.json) · [战斗界面 61 项](p11r2/ui.json) · [叙事与图鉴 133 项](p11r2/story.json)

## 5. 已知缺陷与未验证项

密集鬼群会互相遮挡，四排在门前会叠成一片。48 只是取帧夹具的部署数。三结局自然到达率、真人键鼠手感和 64 张静帧终审仍待验收。K7 保留上轮部分通过的结论，40 / 80 / 150 单位的历史均值为 115.9 / 88.4 / 28.4 FPS，150 单位下 8.01 秒墙钟推进 7.53 秒模拟。本轮增加绘制后，实时性能尚未复测。[上轮实时时间记录](p11r-experience-results.json)

## 6. 需要设计方拍板的问题

请先按 1× 完整原图判断门左侧是否读成有进深、可设拒马的庭院，鬼潮与石面能否同时辨认。再看门内案后和楼上窗后的人、递香烟带能否第一眼辨出。最后将角色卡与图鉴和第 17、20 号稿对照，签收晚的身份与面貌。

## 7. 后续交接

评审入口为 [Grok 委托](../GROK-REVIEW-P11.md)。待本轮三项获得设计签收后，再决定进入 P12 的时间。P12 导出、平台与商店验收均未启动。
