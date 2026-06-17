---
name: harmonyos-automation-test
description: Use when asked to verify a HarmonyOS/ArkUI app change via hdc on emulator/device, or when UI regression testing is needed for a HarmonyOS project
---

# HarmonyOS 自动化测试

## 核心原则

**测试是验证预定义预期，不是探索现象。** 断言驱动，控件树为主、视觉仅佐证。数据不满足前提时拒绝硬测。

## 何时用 / 何时不用

用：HarmonyOS app 改动需 hdc 实机/模拟器回归验证。
不用：纯逻辑可单测的代码；数据前提线上不可得且用户无法提供（见门禁）。

## §0 可行性门禁（开测前硬门禁）

接到任务后**先不设计测试**，先决策：

1. 列出测试的全部「数据/状态前提」（帖子/用户/数据/网络/设备/账号状态）。
2. 每个前提判定线上可控性：
   - 稳定可得（普通文本帖、默认设置、标准导航）→ 可自动化
   - 低概率/不可控（视频帖、特定头像用户、崩溃态、权限态）→ 需用户辅助
3. 存在「需用户辅助」项？向用户咨询三问：a) 自动化是否胜任？b) 能否提供数据/入口（指定 tid/uid、上传测试帖、定向板块、注入数据）？c) 有什么建议？
   - 能提供 → 用其数据继续
   - 不能 / 不胜任 → 拒绝

拒绝须输出：不胜任原因、缺失数据/能力清单、建议（人工测 / 构造本地数据 / 调整范围）。**禁止数据缺失时硬测。**

| 借口 | 现实 |
|---|---|
| "先试试能不能找到样本" | 线上低概率数据试错=浪费。先问 |
| "差不多能测" | 数据不满足前提则结论不可靠。拒绝或先要数据 |
| "用户没说不能测" | 默认不硬测；主动咨询是 skill 职责 |
| "上次找到过类似样本" | 线上数据会变，每次重新确认 |

## 测试全因素（接到任务即填，缺一项不开测）

| 因素 | 确定 | 怎么定 |
|---|---|---|
| 被测行为 | 定义 + 触发条件 | 读代码 |
| 可观测信号 | 行为改变什么 | 控件树字段 / log / 流量 |
| 位置 | 页面 / 入口 / 布局 | 读 wiki + grep navigateActivity + dumpLayout 通览 |
| 样本 | 什么数据体现行为 | 分析数据模型（API 字段有无） |
| 预期 expected | 三路断言值 | 控件树(主) + log(辅) + 视觉(佐证) |
| 对照 | 同样本、变哪个量、前后 | 单变量 |
| 环境 | 设备/网络/模式 | 不可控项找等效（MANUAL 代 WIFI_ONLY） |

## 工具（lib/）

通用工具，接口规格见 `reference/hdc-schema.md`。快速参考：

- `lib/device.sh emu-start|emu-stop|install|start-app|pid|wait-ready`
- `lib/dump.sh` → `./layout.json`
- `lib/snap.sh <name>` → `./<name>.jpeg`
- `lib/log.sh <pid> <pattern>`
- `lib/tap.js <text>|--id <id>|--xy <x> <y>`
- `lib/parse.js find <text> | count <type> [--region=x1,y1,x2,y2] | attr <text> <attr>`
- `lib/assert.js exists|count-eq|visible|text-eq|log-contains ...`（exit 0=PASS/1=FAIL）

node 用 DevEco 自带 `tools/node/node.exe`。**lib 内部已设 `MSYS_NO_PATHCONV`**；仅手动裸调 hdc 时才 `export MSYS_NO_PATHCONV=1`，**套件脚本调 lib 不要全局 export**（会破坏 node 对 `/c/...` 路径的解析）。

## 特化套件（flows/）

每个 feature 测试是一个 shell 脚本，四阶段 setup/action/assert/teardown。规则见 `flows/README.md`。禁止肉眼断言——assert 只用 `lib/assert.js`。

## 常见错误

- 不 dump 确认页面就操作（盲测）→ setup 必须 dump + parse find
- 数据不满足前提硬测 → 走 §0 门禁
- 靠 AI 看图下结论 → 控件树断言为主，视觉仅佐证
- 坐标硬编码 → tap 按 text/id 定位
- 重复 dump/recv 样板 → 用 lib

## 项目适配（skill 之外）

skill 主体零项目数据。项目差异三层外置：
- 静态约定/地图/数据线索 → 项目 CLAUDE.md / 项目 memory
- 运行时常量（bundle/Ability/实例名）→ 项目级配置文件，lib 读取
- 单测试细节 → flows/ 特化套件
