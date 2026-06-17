# HDC 命令行自动化测试规范

本项目可通过 hdc + DevEco 命令行工具完整驱动模拟器，实现「编译 → 部署 → 启动 → 日志 → UI 探查 → 输入」的自动化闭环。本规则记录已实测可用的命令、路径与踩坑，供自动化测试与脚本化复用。

## 环境与路径

DevEco Studio 安装目录：`C:/Program Files/Huawei/DevEco Studio`

| 工具 | 路径 | 说明 |
|------|------|------|
| hvigorw | `tools/hvigor/bin/hvigorw.bat` | 项目根无 wrapper，必须走此路径 |
| hdc | 已在 PATH（`sdk/default/openharmony/toolchains/hdc`） | 类 adb 的设备调试工具 |
| Emulator | `tools/emulator/Emulator.exe` | 本地模拟器 |
| node | `tools/node/node.exe` | 解析控件树用（本机未装 jq） |

所有 hdc 流程前先导出环境变量：

```bash
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
export MSYS_NO_PATHCONV=1   # Git Bash 必需，见「Git Bash 踩坑」
```

## 模拟器管理

```bash
EMU="/c/Program Files/Huawei/DevEco Studio/tools/emulator/Emulator.exe"

"$EMU" -list                       # 列出已创建实例名
"$EMU" -list -details              # 含 isRunning / 分辨率 / CPU 等详情
"$EMU" -start Huawei_TripleFold    # 启动实例
"$EMU" -stop  Huawei_TripleFold    # 停止实例
```

⚠️ **`-start` 是阻塞式且模拟器生命周期绑定到该进程**：进程退出（含被超时杀）= 模拟器立即关闭。因此：
- 自动化/脚本中 `-start` 必须在**独立常驻进程**运行（独立终端窗口 / `nohup ... &` / DevEco Device Manager GUI），不能放进会被回收的后台任务
- 冷启动约 8s 后 hdc 上线：`hdc list targets` → `127.0.0.1:5555`

本机已创建实例：`Huawei_TripleFold`（三折叠，API 23 / HarmonyOS 6.1，全展开 3184×2232）、`Mate X7`、`MateBook Pro`、`MatePad Pro 13`、`Pura 90`、`Pura X Max`。

## 系统就绪判据

勿用 `sys.boot.completed`（模拟器上取不到，errNum 1002）。改用：

```bash
hdc shell "param get const.product.model"                              # 返回 emulator 即就绪
hdc shell aa start -a EntryAbility -b com.example.nga_oh               # 返回 start ability successfully
```

## 应用构建与部署

```bash
HVIGORW="/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat"
HAP=entry/build/default/outputs/default/entry-default-signed.hap

# 编译（须先 export DEVECO_SDK_HOME）
"$HVIGORW" assembleHap --mode module -p module=entry@default -p buildMode=debug --no-daemon

# 安装（覆盖重装加 -r）
hdc install "$HAP"

# 启动
hdc shell aa start -a EntryAbility -b com.example.nga_oh
```

应用信息：bundleName=`com.example.nga_oh`，启动 Ability=`EntryAbility`，首页 `pages/MainPage`。重启模拟器后应用无需重装（持久化），登录会话由 AuthStore 恢复。

## 日志获取

```bash
# 实时日志快照（timeout 控制抓取时长）
timeout 4 hdc shell hilog | tail -50

# 按应用 PID 过滤应用自身日志
PID=$(hdc shell pidof com.example.nga_oh | tr -d '\r\n ')
timeout 3 hdc shell hilog | grep " $PID "
```

应用日志 tag：`EntryAbility`（生命周期）、`JSAPP`（业务，网络日志前缀 `[NGA][REQ]` / `[NGA][RES]`）。

## UI 探查

```bash
# 控件树（结构化，推荐用于定位）
hdc shell uitest dumpLayout -p /data/local/tmp/layout.json
hdc file recv /data/local/tmp/layout.json layout.json

# 截图（像素级）
hdc shell snapshot_display -f /data/local/tmp/shot.jpeg
hdc file recv /data/local/tmp/shot.jpeg shot.jpeg
```

控件树 JSON 解析（本机无 jq，用 DevEco 自带 node）：

```bash
NODE="/c/Program Files/Huawei/DevEco Studio/tools/node/node.exe"
# 列可点击元素
"$NODE" -e 'const d=JSON.parse(require("fs").readFileSync("layout.json","utf8"));const o=[];(function w(n){const a=n.attributes||{};if(a.clickable==="true")o.push(a);(n.children||[]).forEach(w);})(d);o.forEach(a=>console.log(`[${a.type}] ${a.bounds} text=${a.text} id=${a.id}`));'
```

节点关键字段：`type`、`text`、`id`、`bounds`（`[x1,y1][x2,y2]`）、`clickable`、`bundleName`、`abilityName`、`pagePath`。点击坐标取 bounds 中心：`((x1+x2)/2, (y1+y2)/2)`。

## 输入控制

```bash
hdc shell uitest uiInput click X Y                 # 单击
hdc shell uitest uiInput doubleClick X Y            # 双击
hdc shell uitest uiInput longClick X Y              # 长按
hdc shell uitest uiInput inputText X Y "文本"       # 输入框输入
hdc shell uitest uiInput swipe x1 y1 x2 y2 speed    # 滑动
hdc shell uitest uiInput keyEvent Back              # 按键
```

底层事件注入（压力测试等）用 `hdc shell uinput`（`uinput --help` 查参数）。

## Git Bash 踩坑

| 问题 | 原因 | 解决 |
|------|------|------|
| `hdc shell -f /data/...` 报 `C:/Program Files/Git/data/...` invalid | MSYS 把设备绝对路径误转成本地路径 | `export MSYS_NO_PATHCONV=1` |
| `hdc file recv ... C:/xxx` 被拼成 `cwd\C:/xxx` | hdc 不认正斜杠盘符为绝对路径 | local 参数用**相对文件名** recv 到 cwd，再移走 |

## 完整闭环示例

```bash
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
export MSYS_NO_PATHCONV=1
HVIGORW="/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat"

# 1. 编译
"$HVIGORW" assembleHap --mode module -p module=entry@default -p buildMode=debug --no-daemon

# 2. 模拟器须已在独立终端 -start（见「模拟器管理」），并确认 hdc list targets 非空

# 3. 安装 + 启动
hdc install entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.example.nga_oh

# 4. 探查 UI 拿坐标 → 点击 → 重新 dump 验证
hdc shell uitest dumpLayout -p /data/local/tmp/layout.json
hdc file recv /data/local/tmp/layout.json layout.json
hdc shell uitest uiInput click 258 711
```

**已验证闭环**：点击「国际新闻」板块 (258,711) → hilog 抓到 `GET thread.php?fid=843` → 控件树右侧加载帖子列表（dumpLayout 文件由 85KB 增至 164KB）。
