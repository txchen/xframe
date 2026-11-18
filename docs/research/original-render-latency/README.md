# Original 显示延迟研究与 W 验收交接

整理日期：2026-11-17。生产基线：`c32aa98`，XFrame 0.1.4。本文是后续工作的入口，不是发布或集成批准。数值来自各阶段报告，不是本次重新测量；不同实验的起点、负载和窗口不能直接混用。

## 当前结论与停止位置

> **2026-11-18 更新**：R2 区组（A W W A）已完成，见 [R2 结果](acceptance-results-r2.md)。G1–G4、G6 通过，W 降低帧龄约 6.3–7.5 ms。G5 的全屏间隔检查按冻结文字仍未通过，但生产路径 A 同样未通过，所以不是 W 特有的问题。按冻结规则，结论是「不值得集成」（点名 G5）；是否改用相对 A 的判据并集成为默认关闭的开关，待用户决定。修正后的候选为分支 `accept/original-render-worker-v2` 上的 `c32aa98..35655f4`（原 `7c39bde` 误含诊断文件，单独编译失败）。下面的内容是此前的状态。

**W 最终集成验收未完成，尚不能判断是否值得集成。** 有一个有效的生产路径 A 性能会话，但最终候选没有有效的 W 性能会话。此前小程序中的约 4.7–4.8 ms 收益是真实观察，不等于这个候选已通过真实串流验收。

生产代码和默认设置没有接入 W；没有推送、发布。到达即提交和 H5 不作为候选继续扩展。下一次只收敛 W 的剩余验收，不从 Direct 或 Moonlight 研究重新开始。

最终执行曾因模型提供商错误中断，随后只做了清理。这是执行中断，不是性能失败，也不是代码不合理的证据。

## 术语与测量边界

- **A**：0.1.4 的主线程 MTK 调度，Original 的实际待显示帧上限为 2。
- **W**：独立实时渲染线程，预计刷新前 3 ms 开始渲染，使用修正后的 reproject 选点；无 R30、无 holdover。
- **B / arrival**：帧到达或资源释放时尽快提交；与 W 共用原队列和 pending 上限。
- **H5**：到达驱动与 W 安全节拍混合；包含预测刷新去重、决策余量和缺口进入 SAFE 等新增规则。
- **R30**：连续 30 次观察到积压才额外丢一个旧帧；已否决，不属于 W。
- 解码 FIFO 与 presentation pending 是两层不同队列。几秒的解码积压不意味着画面冻结；必须同时报告帧龄、每刷新是否换帧、重复与跳帧。
- `presentedTime` 是系统报告的呈现时间，不是光子时间。probe 的 planned-feed→present 包括喂入滞后和解码；旧 live arrival→display 不含此前解码；最终验收使用 decoderInput→present。
- 不相加不同帧的分位数；丢弃与 ID 跳跃可能是同一帧的两种观测，必须去重。
- 缺口恢复超过观察窗口的事件是右删失。将其按约 4.945 s 计入的是截断统计，不是实际恢复耗时的完整均值。

## 研究结果地图

| 方向 | 结果 | 后续处理 |
| --- | --- | --- |
| 真实 VT 小程序 | 本地 H.264→硬件 VT→420v→生产 Metal shader→真实窗口显示；建立了可重复实验链 | 保留工具；不是网络/音频/完整游戏验收 |
| Direct 资格 | 同条件下 MC 开启拒绝、退出进入 Direct；真实 VT 路径也可 Direct | MC 保持关闭；不要重跑已排除的配置组合 |
| Direct 延迟 | 节拍受控的解码路径中，Direct 与 Composited 未观察到额外整帧收益 | 不能把进入 Direct 等同降低 16.7 ms |
| immediate / atTime 孤立帧 | pending=0、GPU 提前约 3.4 ms 完成仍未赶上紧接着的刷新 | 已有在途积压不是必要原因；没有证明所有 macOS API 都无法优化 |
| W 相位调度 | 小程序总延迟约 38→33.5 ms，p99 约 49→45 ms | 唯一保留的集成候选，最终验收待完成 |
| R30 / 事件后丢帧 | 真实输入中增加跳帧、后续重复；收益不够稳定 | 不加入 W |
| holdover | 只对“回调中断但显示继续”的注入有用，现场未确认该条件 | 已归档，不启用 |
| Moonlight 行为复现 | 等 drawable 与选帧顺序的收益未确立；正常段略快，缺口尾部差 | 不照搬其整套 FIFO/等待路径 |
| B 到达即提交 | 四对 full 均慢 1.6–3.3 ms，缺口段慢 8.3–11.3 ms | 否决 |
| H5 有效追加运行 | 相对 B 恢复改善；相对 W 仅 1/4 对通过非劣，平均仅快约 1 ms | 不采用，不继续堆规则 |

### Direct：已经知道什么

原 4K60 模式即可 Direct，不必换 M5 或物理连线。MonitorControl 运行、光标隐藏时仍被拒；退出 MC 后进入 Direct。MC 的 1×1 Gamma Activity Enforcer 窗口是机制嫌疑，但未单独证明窗口就是全部原因。恒等 gamma 下仍被拒，有力反驳那张 gamma 表本身是原因。

判断以无 HUD 的 Metal System Trace 为准：Direct 字段以及 layer0 是否为 app drawable。layer1/yuv 为空在两种路径下都出现，不能当作硬件平面证据。HUD 是否导致合成本身没有得到可靠隔离验证。可见光标单独是否阻断仍未确定。

官方写法、窗口层级、Game Mode、色彩空间、1080p 等早期阴性实验常有 MC/安全提示混杂，不能推广为这些因素永远无用。A′ 无节流探针的 Direct 32.7 vs Composited 48.8 ms 不能外推到 XFrame；后者为何更慢仍有未证实排队假说。

孤立 real-VT 测试仍观察到请求被下一轮 WindowServer generation 接纳、随后 flip。请求与 GPU 时间相关，不能从同一轻负载试验独立推出两个截止条件。不是“macOS 必然多一帧”的普遍证明。

### W：修复和剩余风险

最初 `lastTarget + period` 会把离格时间戳造成的偏差永久传播。改成用当前 lattice 和上次实际 submit 重新投影；确定性回归和异常注入均验证恢复。更复杂的异常样本过滤器有刷新率切换反例，未采用。

最终小程序：A/W 两对改善 4.82/4.73 ms，节奏、CPU、相位等通过，但最长解码积压门槛失败（W 6.45 vs A 5.25 s；W 5.02 vs A 3.53 s）。原失败不改判。UX 审计中这些长积压仍每刷新换帧，与配对 A 帧龄相近，不等于冻结；仅凭这个审计也不能自动批准集成。

最终代码审查修了 HUD draw/busy 计数、跨线程 scaling status 发布，以及 nextDrawable 返回后重新核验所有权，避免交还后 worker 仍提交。仍需关注 stop 超时、layer 生命周期/resize、非接管状态每 2 ms 轮询及 CPU。

### Moonlight：不要再沿用已纠正的说法

固定 Moonlight v6.2.0 `de2467e433821664cdd2224aad8c89a625be1ad9`。AUTO 按能力优先尝试 libplacebo/Vulkan/MoltenVK，不代表已实测本机选中。以前只引用 VTMetal 的 CAMetalDisplayLink latency=1 不完整。

默认路径先等待 GPU/获取 drawable，再取队首帧。**不是始终只保留最新帧**：pacer 是容量 3 的 FIFO，满时丢最旧，另有追赶规则。默认同步提交配置下，dummy render 在选帧前触发 nextDrawable。CPU 引用释放、GPU fence 完成与 CA 回收 drawable 不能混为一谈。

libplacebo `92b5ac6db79f`；SDL `829a65d769d9`；sdl2-compat `e4df8a55f20d`。MoltenVK v1.4.2 `db66022459ff` 由二进制字符串推断，未完全核实构建来源。源码中有 opaque 继承和 Direct drawable 阻塞时双缓冲退三缓冲的处理，没有找到明确消除本次额外刷新安排的机制。未发现不等于不存在，也不证明 Moonlight 本体与探针性能相同。

行为复现中固定两个 drawable 约 30 fps，nextDrawable 在旧帧被替换后才返回；启用 Moonlight 式回退后恢复。复现没有引入 Vulkan 等完整依赖，MTLEvent 等价性仍有限制。

### B 与 H5：为什么止损

B 缺口后受到 pending cap=2 限制，资源释放发生在上屏回调之后；随后的提交落在刷新之后，submit→present 可持续约 32–33 ms，W 约 19 ms。日志未发现明显丢唤醒，但内部因果仍不是干预证明。cap 命中次数是重检次数，不是丢帧数。

H5 通过 SAFE 节拍缓解了慢相位。有效追加运行中 H-B 四对恢复改善；H-W 四对只有一对非劣通过，全程快 0.78–1.17 ms，一对缺口恢复明显更差。规则复杂度与收益不匹配；不继续调参。样本内拟合的模型预测不能当独立验证。

## 最终验收：事实、缺口和接续顺序

原始冻结协议见 [acceptance-preregistration.md](acceptance-preregistration.md)，中止时完整事实见 [acceptance-status-snapshot.md](acceptance-status-snapshot.md)。这两个文件是研究分支报告的原样快照，描述当时状态；若与新证据冲突，追加说明，不重写历史结论。

已完成：

- 含诊断层的 `a8bda08` 全套 217/217 通过；候选 `7c39bde` 单独未跑全套。
- W 真实窗口首帧接管、Integer 交还/Original 再接管、帧 ID 不回退、结束和重新开流已验证。交还约 25 ms，MTK 恢复约 32.8 ms；stop 0.6/1.2 ms。
- 冻结的全屏间隔 ≤250 ms 项失败：进入/退出分别 567/633 ms notPresented。A 的一次无效会话也出现约600 ms，另一有效会话未出现；不能归因 W，也不能删去失败。
- 有效性能仅 P1-A：帧龄38.8 ms，p95 46.6、p99 48.4；14 未显示，24 重复，6 次 >40 ms；5个源缺口中3个未恢复。没有最终 W 可比较。

后续严格按此顺序，不新开研究课题：

1. 核验生产基线/分支、补丁、构建工具、会话和偏好。旧 `/tmp` 与 PID 不可信，必须现查。避免同 bundle 的正式 app 与诊断 app 同时运行。
2. 在候选 `7c39bde`（不含诊断层）跑全套；审清所有权超时/退出后的访问与真实 layer resize 边界。
3. 以同样操作做 A 的全屏进入/退出对照；旧 G5 失败保留。若增加 A/W 差分判据，必须新写前瞻附录，不能事后宣布旧门槛通过。
4. 原计划缺 W、W、A 三个180秒稳定窗口（首帧45–225秒），重试剩1次。若隔日/换环境使旧A不可比，先写新的完整平衡计划和预算，不把旧A硬拼成同条件对照。
5. 按G1–G6报告延迟、节奏、上游、CPU、生命周期、缺口体验；完整窗口和稳定窗口都保留，未恢复计右删失。不可只报submit→present或挑好段。
6. 给出“值得集成 / 不值得当前形态集成 / 证据不足”的明确依据。即便通过，原计划也只批准默认关闭的可选候选，不等于发布或默认开启。

## 工件保存与恢复

已将候选补丁、诊断补丁、冻结协议和状态快照复制到本目录，避免只依赖 `/tmp`。见 [SHA256SUMS](SHA256SUMS)。候选与诊断必须分开；诊断层不能当生产改动一起集成。

| 用途 | 提交 / 位置 |
| --- | --- |
| 生产基线 | `c32aa98` |
| 原候选 | `bd6434e`；`candidate/0001-*.patch` |
| 审查修复 | `7c39bde`；`candidate/0002-*.patch` |
| 仅诊断 | `a8bda08`；`diag-only/0001-*.patch` |
| 最终验收记录 | 研究分支 `b7dbc55` |
| 保留隔离工作树 | `/tmp/xframe-w-accept`，`accept/original-render-worker` |
| 研究工作树 | `/Users/hibiki/.paseo/worktrees/0d5k41il/original-display-latency`，`research/original-display-latency` |

从干净基线恢复时可在新隔离 worktree 顺序 `git am` 本目录 candidate 的两个补丁，再按需应用 diag-only。先检查当前分支和补丁是否已存在，不重复应用、不重置用户改动。不要直接在生产目录应用。若旧基线对象仍在仓库，可直接检出提交；否则补丁保留了审查内容，但应用到新生产版本需要重新解决差异和验收。

研究原始数据和大型 trace **没有复制进 docs**；也没有声称已远程备份。它们仍在上述研究 worktree 的 `.scratch/`、`.build/`。不要删除研究工作树或临时构建，直到需要保留的数据已归档核验。日志可能含账户/会话信息，公开提交前应单独审查。当前文档不包含原始会话导出。

## 证据索引（相对研究工作树）

| 阶段 | 报告 | 提交 |
| --- | --- | --- |
| 初始系统呈现链 | `.scratch/render-path-probe/2026-11-16-sparse-chain/README.md` | `d41c123`（含后续修订） |
| Direct正对照 | `.scratch/render-path-probe/2026-11-17-direct-evidence/B-combined/README.md` | `c9c7596` |
| MC/光标因素拆分 | 同目录 `factors/README.md` | `5e68a41` |
| VT Direct性能 | `.scratch/decode-probe/2026-11-17/direct/README.md` | `e1446ef` |
| 孤立帧 / atTime | 同目录 `isolated/README.md`、`isolated-attime/README.md` | `0de3d78`、`456a4e8` |
| W小程序最终验收 / UX | 同目录 `README-final.md`、`UX-AUDIT-final.md` | `35e8441`、`d964efb` |
| Moonlight源码三轮审查 | 同目录 `mdl/MOONLIGHT-AUDIT*.md` | `41e645f`、`dcbce72`、`ef5bb2c` |
| Moonlight行为复现 | 同目录 `pacer/README.md` | `bca4d28` |
| 到达即提交 | 同目录 `arrival/README.md` | `fd4170e` |
| H5无效 / 有效追加 | 同目录 `hybrid/README.md`、`hybrid/rerun1/README.md` | `9f30fd2`、`9c380f1` |
| 最终集成中止记录 | `.scratch/w-acceptance/README.md`、`PREREG.md`、`runs/` | `b7dbc55` |

日期目录有历史命名，不应用其推断实际运行时间；以原始记录/报告UTC时刻为准。修订后的报告优先于早期聊天里的过强结论。

## 操作约束与应避免的重复错误

- 用户要求集中M1，不转向M5；需要研究优先真实VT小程序。最终W集成验收已明确授权必要的隔离XFrame真实会话。
- MC按用户要求保持关闭，不自行恢复、卸载或修改开机启动。结束时恢复本次临时HUD/Scaling/库页布局；最后记录为Original/Compact/Grid，需实时核验。
- 不反复问CUA授权或解锁。用当前桌面、console与窗口证据交叉核验，不沿用旧锁屏字段，也不把用户常开机器等同显示始终可用。禁止输入凭据或绕过安全屏幕。
- 不读取/点击SecurityAgent；其进程或窗口存在本身不是禁止操作自己app的充分理由。普通遮挡通知可明确定位关闭，不停用户程序/Unity工作负载，不改系统通知/锁屏设置。
- 测量期间不截图、不CUA、不profiler；只读系统日志的活动重合不证明外部程序造成性能异常。
- 先验证预登记前置条件。H5曾在Direct检查失败后继续perf，属于执行错误，不得重复。
- 测量等待与End Session必须严格顺序，曾错误并行导致会话12秒被结束。菜单精确唯一定位，禁止宽松View正则误改Grid/List；退出后别用旧app绑定导致重新拉起。
- 锁屏/失可见/连续无效present时自动保存并退出；正常进程级防睡眠断言可用，不改系统设置。中止数据保留，预算内有限重试，不跑到通过。
- 用户明确不需要中间进度和重复完成通知。后续集中交付最终判断；真正无法自行解决的新阻碍才简短报告。
