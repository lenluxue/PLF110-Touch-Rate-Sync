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

- 每 3 秒读取一次屏幕刷新率和前台应用。
- 只在目标上报率发生变化时写入。
- 每 10 秒读回当前上报率，被其他服务改写时自动恢复。
- 每次写入后读回校验。
- 屏幕关闭、应用不在白名单、模块停用或进程退出时恢复默认值。

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

使用 KernelSU 或 Magisk 安装 release zip，然后重启。模块 ID 为
`touch_rate_sync`。

手动启动与停止：

```sh
sh /data/adb/modules/touch_rate_sync/service.sh
kill "$(cat /data/adb/touch_rate_sync/pid)"
```

## 配置

编辑 `/data/adb/modules/touch_rate_sync/config.conf`：

- `POLL_INTERVAL`：刷新率和前台应用的轮询间隔，整数秒。
- `WATCHDOG_INTERVAL`：上报率读回间隔。
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

