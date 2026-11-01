# PLF110 Touch Rate Sync

[English](README.md) | 简体中文

面向 OnePlus PLF110 / Synaptics S3910 的系统less 触控上报率同步模块。
模块只使用系统现有的 Binder 触控接口，不修改分区，也不修改 `/system`、
`/vendor` 或 `/odm` 下的文件。

## 设备要求

服务启动前会校验 `ro.product.model`、`ro.product.vendor.model`、
`ro.product.device` 和 `ro.boot.prjname`。默认只允许：

- `ALLOWED_MODELS="PLF110"`
- `ALLOWED_PROJECTS="24825"`

设备不匹配时，服务会直接退出，不会写入触控节点。

## 功能

- 每 3 秒读取一次屏幕刷新率；仅在 `ONLY_FOR_LISTED_APPS=1` 时查询前台应用。
- 当前节点值与目标不一致时才写入，包括被其他服务重置的情况。
- 每 1.5 秒读回当前上报率，被其他服务改写时自动恢复。
- 使用 KernelSU 自带的 BusyBox standalone Shell 和内建解析，减少短生命周期子进程。
- 每次写入后读回校验。
- 屏幕关闭、应用不在白名单、模块停用或进程退出时恢复默认值。

## v1.0.7 优化思路与验证范围

本次针对子进程创建开销优化，不靠延长轮询周期掩盖活动：使用 KernelSU 自带的
BusyBox standalone Shell；HIDL 末行数字及首条显示记录改用 Shell 内建解析；
全应用模式跳过前台应用查询，状态显示 `foreground=all`。保留写后读回、重试、
设备校验、单实例锁和退出恢复；超时工具显式使用 `/system/bin/timeout`。

2026-11-01 在同一台 PLF110 上连续短测，按后台自身及已回收子进程累计 CPU 时间，
约从**单核 17.9% 降至 2.22%**（修改前 12.57 秒、修改后 12.59 秒，约下降 88%）。
对照两次均采用安装版的 3 秒显示轮询及 1.5 秒读回；旧仓库 v1.0.5 的读回默认值为
10 秒。本结果仅代表该场景，不承诺固定降幅，也不能证明所有 CPU 0–3 核 `cycles`
波动都由本模块造成。

已通过 66 项模拟断言、实际解释器语法检查、现场 120Hz/raw 288 读回、单实例启动及
优雅退出恢复 raw 0。模拟测试覆盖 144/90/60Hz 映射、应用列表筛选与熄屏目标恢复；
本次尚未实测 144Hz 游戏、实际熄屏切换、ZIP 重装及重启后自启。
`effective_target` 是配置映射标签，不是物理触控采样率测量结果。

## 速率映射

| 刷新率 | 触控上报率 | 说明 |
|---:|---:|---|
| 30Hz | 120Hz | 最低可用档位 |
| 60Hz | 120Hz | |
| 90Hz | 180Hz | |
| 120Hz | 300Hz | 写入硬件码 288，有效值 300Hz |
| 144Hz | 320Hz | 写入硬件码 360，有效值标签 320Hz |

S3910 当前只接受 `120/180/240/288/360`。可在 `config.conf` 的
`RATE_MAP` 中修改映射，`EFFECTIVE_RATE_MAP` 用于设置显示标签。

## 安装

`v1.0.7` 为 **KernelSU 专版**，需要可执行的 `/data/adb/ksu/bin/busybox`。
缺少 BusyBox 时会明确报错并停止启动；本版不支持 Magisk。

使用 KernelSU 安装发行 ZIP 后重启，模块 ID 为 `plf110_touch_rate_sync`，
与本次在设备上验证的安装版一致。

**不要与旧 ID `touch_rate_sync` 的模块并存。** 模块 ID 不同，安装新版不会自动替换旧版。
如安装了旧版，先备份自定义配置，在模块管理器卸载旧版并重启，再安装本版。
两种 ID 使用相同的运行 PID/锁目录。

手动启动与停止：

```sh
sh /data/adb/modules/plf110_touch_rate_sync/service.sh
kill "$(cat /data/adb/touch_rate_sync/pid)"
```

## 配置

编辑 `/data/adb/modules/plf110_touch_rate_sync/config.conf`：

- `POLL_INTERVAL`：刷新率和前台应用的轮询间隔，整数秒。
- `WATCHDOG_INTERVAL`：上报率读回间隔，默认 1.5 秒。
- `RATE_MAP`：刷新率到上报率的映射。
- `EFFECTIVE_RATE_MAP`：硬件码到有效值标签的映射。
- `FALLBACK`：未配置刷新率的回退策略。
- `ONLY_FOR_LISTED_APPS=1`：只对 `apps.txt` 中的包生效。
- `DRY_RUN=1`：只记录日志，不写入触点。
- `RESTORE_RATE`：失活时恢复的值，默认 `0`。
- `ALLOWED_MODELS`：允许的设备型号，默认 `PLF110`。
- `ALLOWED_PROJECTS`：允许的项目号，默认 `24825`。

## 运行文件

- 状态：`/data/adb/touch_rate_sync/status`
- 日志：`/data/adb/touch_rate_sync/daemon.log`
- PID：`/data/adb/touch_rate_sync/pid`

点击模块管理器的 Action 按钮会显示状态并生成中文诊断压缩包，优先保存到
`/sdcard/Download`。采集内容包括设备与模块状态、触控节点、刷新率、模块日志及
相关系统日志；脚本只读取信息，不会写入触控节点，也不会收集账户令牌或完整系统属性。

## 构建

```sh
./build.sh
```

脚本会生成 `PLF110-Touch-Rate-Sync-<version>.zip`。

## 注意

- 较高的触控上报率会增加触控 IC 的功耗和发热。
- 设置 `ONLY_FOR_LISTED_APPS=1` 可以只在指定包中生效。
- 本模块仅适用于 PLF110 / S3910。

## 许可证

MIT

