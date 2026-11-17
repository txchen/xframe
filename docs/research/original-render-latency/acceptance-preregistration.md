# W（Original RT render worker，reprojection，lead 3 ms，无 R30、无 holdover）最终集成验收：预登记

本文写于任何实测之前，冻结后不再修改；偏离一律写入 README。

## 候选与构建
- **基线**：master = origin/master = `c32aa98`（0.1.4）。
- **隔离 worktree**：`/tmp/xframe-w-accept`，分支 `accept/original-render-worker`，共三个提交：
  1. `bd6434e`：原集成补丁 `8d475026`；
  2. `7c39bde`：审查后的最小修复（候选的一部分），见「审查发现」；
  3. `a8bda08`：**只用于验收的诊断层**（不属于候选），只有设置了 `XFRAME_ACCEPT_DIR` 才生效：
     - FrameTrace 容量可调（`XFRAME_ACCEPT_TRACE_CAPACITY`），并公开 `origin`；
     - 每秒记录进程 CPU，每 5 s 记录流计数（解码 / 上屏 / 丢帧、视频包 / 丢包 / NACK、音频包 / 能量）；
     - 记录所有权转换、worker 策略读回、stop 耗时；
     - 会话结束后，在主线程一次性写出 production `diagnosticReport`（含 frame trace），测量期间不做序列化。
- **候选补丁**为 `c32aa98..7c39bde`。默认关闭：开关是 UserDefaults 中的 `XFrame.Experimental.OriginalRenderWorker`，从未写入用户偏好。
- **app**：`/tmp/xframe-w-accept/.build/accept/XFrame.app`，可执行文件 sha256 为 `e24fa71f…2e24`。没有注册到 LaunchServices，bundle ID `win.xframe.app` 与正式版共用登录状态，**运行期间不同时运行正式版**。
- **A 与 W**：同一个二进制，用启动参数（argument domain，不持久化）`-XFrame.Experimental.OriginalRenderWorker NO` 或 `YES` 区分。
- **测试**：`swift test` 217/217 通过（含更新后的 `workerRendersFollowsResize…`：接管期间 draw ticks 增加；scaling status 随 resize 更新；park 之后不再 submit；策略读回存在）。

## 审查发现（尚未发现阻断问题，不等于已证明没有）
- **已修复**（`7c39bde`，只涉及口径和所有权安全，不扩展算法）：
  1. worker 接管期间，HUD 的 draw ticks 和 draw interval 会冻结。改为每次渲染尝试记一次 `.draw`，没有 GPU permit 时记 `.busy`。
     - 口径：A 下 `.draw` 是 MTK 以 120 Hz 发出的回调次数，W 下是 worker 以 60 Hz 发出的尝试次数。**两者不能互比，也不代表丢帧或 fps**。帧率和丢帧以 present / 未显示为准。
  2. scaling status 没有转发（resize 后 HUD 和设置中显示的输出尺寸会过时）。改为 worker 在自己的锁内发布 status，由主线程 tick 读取后调用 `scalingReport`。worker 不读写 AppKit view，也不调用主线程回调。
  3. stop 超时或交还时，如果 worker 正卡在 `nextDrawable`，可能在所有权已交回 MTK 之后仍提交一帧，形成双 owner。改为 `nextDrawable` 返回后在锁内重新检查 `active && !stopped`，不满足就放弃这一帧，并归还 reservation 和 permit。
- **尺寸同步策略**：drawableSize 由 MTKView 在主线程设置；worker 只读取 `nextDrawable` 返回的 texture 的尺寸，这一尺寸由 CAMetalLayer 在内部保证一致。
- **未修，需实测确认的项**：
  - stop 在主线程上最多等待 1 s；
  - worker 未接管时（首帧之前、交还期间、非 Original 模式）每 2 ms 轮询一次；
  - 停用之后 worker 线程仍然存活（直到 renderer 释放或下一次 play）。
  - 实测中报告 End/交还耗时、UI 是否卡顿，以及非 Original 模式下 W 的 CPU。

## 实测设计
- **内容**：Account → Cloud Games → A Game About Digging A Hole，Standard / Balanced，停在标题菜单，不发送游戏输入。HUD 保持用户当前设置 Compact，Scaling 保持 Original（运行前已读回）。生命周期会话改动的设置在结束后恢复。
- **会话 L（生命周期，W）**，只用于验证正确性，不作性能比较。首帧后依次执行：
  1. 等待接管；
  2. View → Video Scaling → Integer，等 5 s，再切回 Original；
  3. 进入全屏，等 5 s，再退出全屏；
  4. End Session；
  5. 再开一个新会话（重新 play），确认再次接管，然后 End Session。
  - **检查**：
    - 接管和交还事件都存在，交还耗时 < 100 ms；
    - 交还后 100 ms 内 present 恢复；
    - submitted 帧 ID 严格递增（不回退到旧帧）；
    - 全屏进出期间 present 继续，任何间隔都不超过 250 ms；
    - stop < 1 s；
    - 每次 End 之后 trace 中不再有 submit；
    - 新会话中重新接管；
    - UI 能够响应（CUA 操作没有超时）。
  - 任一项不通过即为阻断。
- **性能会话**：4 个连续会话，按 A、W、W、A 的顺序。
  - 每个会话：首帧后约 20 s 内进入全屏；测量窗口为首帧后 45–225 s（180 s，作为稳定窗口）；同时报告全程（从首帧开始，含接管与初始化）。
  - 测量期间不用 CUA、不开 profiler，也不操作其他程序。之后退出全屏，End Session，退出 app，并确认进程已经退出。
  - **说明**：独立的云会话无法保证源的到达相位和服务器负载匹配。这 4 个会话只是本次的证据，不能当作随机化因果证明。相邻配对是 A1–W2 与 W3–A4。场景或码流明显不同的情况，按下面「无效」的规则处理，不在事后挑窗口。
- **端到端口径**：起点是 production FrameTrace 的 `decoderInput`（本机把已收到的编码帧交给 VT 的时刻），终点是 `presentedTime`。这不是输入到光子的延迟。
  - 刷新栅格由 presentedTime 的中位周期重建。每次刷新所显示的帧，是 presentedTime ≤ 刷新时刻 + 0.5 ms 的最后一帧。
  - **帧龄** = 刷新时刻 − 该帧的 decoderInput 时刻，按 RTP 关联。
- **源缺口事件**：相邻两次 decoderInput 的间隔 > 40 ms。每个事件计算：
  - **基线**：缺口前 2 s 内帧龄的中位数；
  - **恢复**：从缺口结束起，连续 30 次刷新的帧龄 ≤ 基线 + 8.33 ms；5 s 内达不到就记为未恢复，右删失时间计为 4.945 s。均值**包含**右删失的事件，另外单独报告只计已恢复事件的均值和样本数；
  - 3 s 内的超额帧龄面积，以及峰值；
  - 该事件期间的最长解码积压（每次取帧时，由 trace 重建的队列深度 ≥ 2 的连续段）；
  - 缺口区内的重复刷新数和 >40 ms 间隔数。

## 门槛（冻结；沿用 live PREREG-W-vs-A 与 PROTOCOL-final）
- **G1 延迟**：两个相邻对都要满足：稳定窗口内刷新帧龄均值 A − W ≥ 2 ms，计划→present（decoderInput→present）均值 A − W ≥ 2 ms。同时报告 p95 / p99。
- **G2 节奏**（每对）：唯一未显示帧/min ≤ A + 1.5；重复刷新/min ≤ A + 1.5；>40 ms 间隔 ≤ A + 1；上屏/交付 ≥ A − 0.002。
- **G3 上游**（每对）：decoderInput 速率差 ≤ 0.05 帧/s；decode p99 ≤ A + 1 ms。视频丢包、NACK 和音频包、能量照实报告。
- **G4 CPU**（每对）：W 的进程 CPU − A ≤ 5 个百分点（以单核计）。
- **G5 生命周期**：会话 L 的所有检查都通过。
- **G6 缺口体验**（产品判断用的界限，前瞻设定，依据是「是否会造成可见的额外冻结或重复」，不是统计门槛）：
  - 每对中，缺口区的重复刷新数 + >40 ms 间隔数，W ≤ A + 1；
  - 合并 4 个会话后，未恢复事件的比例 W ≤ A + 0.10；
  - 右删失均值恢复时间 W − A ≤ 0.25 s。
- 小 app 最终验收中第 4 项（最长积压）**失败的结论保留**，不会因为这次结果改为通过。

## 判定（冻结）
- G1–G6 全部通过：**值得集成**，形式为默认关闭的可选开关，即候选 `c32aa98..7c39bde`。不启用默认，也不发布。
- G1 未通过（收益不稳定或小于 2 ms），或 G2、G4、G5 有任一项失败：**不值得集成**，并点名是哪一项。
- 只有 G3 或 G6 未通过：**不值得在当前形态集成**，写明是哪一项、什么机制。
- 有效会话不足：**仍不能判断**，并写明缺少什么。

## 预算与无效
- **有效会话**：L 一个，加上 A、W、W、A 四个。无效重试一共最多 2 次，之后不再追加。
- **会话无效的情形**：
  - 在首帧后 225 s 之前断开；
  - 重连、黑屏或解码错误；
  - 游戏、画质或节奏不对；
  - 锁屏或失去可见性；
  - 测量期间误用了 CUA；
  - 同 bundle 的 XFrame 实例并行运行；
  - 开关读回与该会话的设定不符（例如 W 会话中没有出现 `worker.takeover`）。
- 无效数据保留并标注，不作为结果依据。证据足够即停止，不跑到通过为止。
