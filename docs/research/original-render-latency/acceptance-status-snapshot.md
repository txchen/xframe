# W 最终集成验收：中止时的状态（未完成）

预登记见 `PREREG.md`（提交 1285e5b）。这一轮被提供商的政策拦截后中止。之后只做了安全收尾，**没有再进行任何新实验**。

## 结论
**现在还不能判断是否值得集成。** 按预登记，有效会话不够：
- 4 个性能会话（A W W A）中只完成了 1 个有效的 A，**没有任何 W 性能会话**；
- 所以 G1（延迟）、G2（节奏）、G3（上游）、G4（CPU）、G6（缺口体验）都**无法判定**。

## 已完成
- **隔离构建**：worktree `/tmp/xframe-w-accept`，分支 `accept/original-render-worker`，基线是 `c32aa98`（= master = origin/master）。
  - `bd6434e`：原补丁 8d475026；
  - `7c39bde`：审查后的最小修复（属于候选）；
  - `a8bda08`：只在验收中使用的诊断层（不属于候选）。
  - 补丁文件：`candidate/`（候选，2 个）、`diag-only/`（诊断，1 个）。
  - app：`/tmp/xframe-w-accept/.build/accept/XFrame.app`，可执行文件 sha256 `e24fa71f…`，**没有**注册到 LaunchServices。
- **审查与修复**（尚未发现阻断问题，但不等于已证明没有）：
  1. worker 接管期间，HUD 的 draw/busy 计数会冻结。改为每次尝试记一次 `.draw`，没有 permit 时记 `.busy`。A 和 W 下 `.draw` 的口径不同（120 Hz 回调对 60 Hz 尝试），不能把这个差异当作丢帧。
  2. scaling status 没有转发。改为 worker 在锁内发布，再由主线程的 tick 调用 `scalingReport`；worker 不访问 AppKit。
  3. stop 超时或交还时，卡在 `nextDrawable` 中的 worker 可能在交还之后仍然 present（双 owner）。改为 `nextDrawable` 返回后在锁内重新检查 `active && !stopped`，不满足就放弃这一帧，并归还 reservation 和 permit。
- **单元测试**：`swift test` 217/217 通过（`swift-test.log`）。这次运行的是含诊断层的 `a8bda08`，修复提交 `7c39bde` 中的测试改动包含在内。新增的断言覆盖：接管期间 draw ticks 增加；resize 后 scaling status 更新；park 之后不再 submit；策略读回存在。**`7c39bde` 单独（不含诊断层）没有单独跑过全套测试。**
- **真实窗口生命周期会话 L（W，`runs/L/`，`lifecycle.json`）**：

| 检查项 | 结果 | 依据 |
|---|---|---|
| 接管 | 通过 | 首帧后立即接管（L1、L2 都有 `worker.takeover`） |
| 策略读回 | 通过 | 读回值为 1 |
| Original→Integer 交还 | 通过 | 交还耗时 25.2 ms；交还后 32.8 ms 恢复 MTK present |
| Integer→Original 再接管 | 通过 | 有再接管事件 |
| submitted 帧 ID 不回退 | 通过 | 两个会话均为 0 次回退 |
| End Session 的 stop 耗时 | 通过 | 0.6 ms 和 1.2 ms |
| 新会话重新接管 | 通过 | L2 中再次接管 |
| UI 响应 | 通过 | CUA 操作均无超时 |
| **全屏进出时 present 间隔 ≤ 250 ms** | **未通过（按冻结的文字）** | 进入时 567 ms、退出时 633 ms 没有上屏；worker 每个刷新照常 submit，但这些帧都是 notPresented |

  - **关于全屏一项的归因（描述性，不改判定）**：无效的 A 会话（下文）中，全屏转换同样出现了约 600 ms 的间隔；而有效的 A 会话 P1-A 在进入全屏时没有出现大间隔。所以这一项是否是 W 特有的，**无法确定**。这项检查本应拿 A 作对照，却写成了绝对阈值，这是我在预登记里的设计疏漏。
- **有效的 A 性能会话 P1-A（`runs/P1-A/`）**：
  - 会话在首帧后约 287 s 因服务器端 transport failed 结束，晚于 225 s，因此按预登记仍有效。
  - 稳定窗口：帧龄 38.8 ms（p95 46.6，p99 48.4）；decoderInput→present 38.8 ms；未显示 14；重复 normal 14 / gap 10；>40 ms 间隔 6，最大 83 ms；decode p99 3.55 ms；CPU 0.36 核；视频丢包和 NACK 都是 0。
  - 5 次源缺口（约 50 ms，每 30 s 一次）中，未恢复 3 次。
  - 只有 A，没有 W 可以比较。

## 无效与偏差
- **`runs/P1-A-invalid-operator-ended-early/`**：我把「结束并退出」的 CUA 调用和测量期间的 sleep **并行发出**，导致会话在首帧后约 12 s 就被我结束。这是操作错误，占用了 1 次无效重试额度（共 2 次）。
- **生命周期之后的一次「结束」调用失败**：`toggleFS` 用了宽松的正则 `View` 去匹配元素，这和下面库页布局被改的问题很可能是同一个原因。
- **库页布局被改**：开始时库页为 Grid，后来 AX 树显示变成了 List。期间只有我的 CUA 点击了名为 View 的元素，因此判断是我误改。之后通过唯一定位到的 `radio button Description: Grid`（元素 17）恢复，读回 Grid = 1、List = 0。
- **环境**：屏幕上一直有一个 SecurityAgent 窗口（12:11 本地时间启动，我没有读取也没有操作）；运行前用 CUA 的 Close 关闭了一条普通的日历通知。

## 缺少的验收（要完成判断需要补做）
- 3 个 W/A 性能会话（W、W、A），用以判定 G1–G4 和 G6；剩余的无效重试额度为 1 次。
- 全屏转换间隔的 A 对照（同样的进出全屏操作），用以判断全屏那一项是否是 W 特有的。
- 用 `7c39bde`（不含诊断层）单独跑一次全套测试。

## 现有证据是否支持集成
**不支持作出集成的结论**，也不支持作出不集成的结论。
- 已有的支持性证据：生命周期中的交还、再接管、stop 和重新接管都正常，帧 ID 没有回退，单元测试全部通过，审查后的修复都很小。
- 还缺：真实串流中 W 对 A 的延迟收益和代价，目前**完全没有** W 的性能数据。
- 另外，冻结的 G5 全屏检查按文字未通过，而且是否是 W 特有的问题尚未查清。

## 清理状态
- 我自己的 XFrame 诊断进程已经退出（经核验为 `/tmp/xframe-w-accept/...` 中的 app）；没有 caffeinate、xctrace、DecodeProbe 或编译进程在运行。
- 用户偏好：`XFrame.VideoScaling = original`、`XFrame.PerformanceHUD = compact`，与运行前相同；`XFrame.Experimental.OriginalRenderWorker` 从未写入过。库页布局已恢复为 Grid。
- MC 保持关闭。研究分支的 `Sources/Tests` 是干净的；用户生产树 `/Users/hibiki/code/vibe/xframe` 没有改动。没有推送、发布或改动默认值。
- 保留下来的内容：`/tmp/xframe-w-accept` worktree 和分支 `accept/original-render-worker`（可以用 `git worktree remove /tmp/xframe-w-accept`，再删除分支，即可回滚）；数据在 `.scratch/w-acceptance/runs/`。
