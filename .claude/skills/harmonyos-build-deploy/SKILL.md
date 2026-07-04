---
name: harmonyos-build-deploy
description: 鸿蒙项目构建、模拟器拉起、应用安装部署。当用户要求编译、启动模拟器、安装 HAP 或在模拟器上运行应用时使用。
---

# HarmonyOS 构建部署

三步闭环：**构建 HAP → 拉起模拟器 → 安装启动**，每步先检查状态再按需执行。

## 配置

执行前先 source 配置文件：

```bash
source .claude/skills/harmonyos-build-deploy/config.sh
```

配置项说明（按需修改 `config.sh`）：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `EMULATOR_INSTANCE` | `Huawei_TripleFold` | 模拟器实例名 |
| `BUNDLE_NAME` | `com.example.nga_oh` | 应用包名 |
| `ABILITY_NAME` | `EntryAbility` | 入口 Ability |
| `BUILD_MODE` | `debug` | 构建模式 |
| `JAVA_OPTIONS` | `-Xmx1024m -Xms256m -XX:+UseSerialGC` | Java JVM 参数（爆内存时使用） |
| `NODE_OPTIONS` | `--max-old-space-size=8192` | Node.js V8 内存上限 |
| `DEVECO_STUDIO_HOME` | `C:/Program Files/Huawei/DevEco Studio` | DevEco 安装目录 |

## 步骤 0：状态检查（每次必做）

执行操作前，先全面检查当前状态，向用户汇报后再按需执行。

### 检查模拟器

```bash
hdc list targets
```

- 输出含 `127.0.0.1:5555`（或其他 IP:port）→ 模拟器已连接
- 输出 `[Empty]` → 模拟器未运行

### 检查 HAP 构建状态

```bash
# 检查 HAP 是否存在 + 源码是否比 HAP 新
HAP="${HAP_PATH}"
if [ -f "$HAP" ]; then
  # 找 entry/src/main/ets 下最新 .ts 文件时间
  NEWEST_SRC=$(find entry/src/main/ets -name "*.ts" -type f -exec stat -c %Y {} \; 2>/dev/null | sort -rn | head -1)
  HAP_TIME=$(stat -c %Y "$HAP" 2>/dev/null)
  if [ "$NEWEST_SRC" -gt "$HAP_TIME" ] 2>/dev/null; then
    echo "NEEDS_BUILD: 源码有更新"
  else
    echo "UP_TO_DATE: HAP 已是最新"
  fi
else
  echo "NEEDS_BUILD: HAP 不存在"
fi
```

> 注：以上检查仅在 Git Bash 环境有效。如 stat 不可用，保守假设需要构建。

### 检查 SDK 完整性

```bash
source .claude/skills/harmonyos-build-deploy/config.sh

# 检查 sdk-pkg.json 中的 path 字段是否匹配实际目录
if [ -f "$SDK_PKG_PATH" ]; then
  CONFIG_PATH=$(python3 -c "import json; print(json.load(open('$SDK_PKG_PATH','r'))['data']['path'])" 2>/dev/null)
  if [ -n "$CONFIG_PATH" ] && [ ! -d "${DEVECO_SDK_HOME}/default/$CONFIG_PATH" ]; then
    ACTUAL_DIR=$(ls "${DEVECO_SDK_HOME}/default/" 2>/dev/null | grep -v sdk-pkg.json | grep -v hms | head -1)
    echo "WARN: sdk-pkg.json 中 path='$CONFIG_PATH' 但该目录不存在"
    echo "      实际 SDK 目录为: $ACTUAL_DIR"
    echo "      请修改 sdk-pkg.json 中的 path 字段为: $ACTUAL_DIR"
  fi
fi
```

### 检查应用

```bash
hdc shell pidof ${BUNDLE_NAME}
```

- 有 PID 输出 → 应用正在运行
- 无输出 → 应用未运行（可能已安装但未启动，或未安装）

### 汇报格式

向用户呈现状态表格：

```
| 步骤 | 状态 | 行动 |
|------|------|------|
| 模拟器 | ✅ 已连接 / ❌ 未运行 | 跳过 / 拉起 |
| HAP    | ✅ 最新 / 🔄 需构建 | 跳过 / 构建 |
| 应用   | ✅ 运行中 / ⚠️ 未启动 | 跳过 / 安装启动 |
```

## 步骤 1：构建 HAP

```bash
source .claude/skills/harmonyos-build-deploy/config.sh

# 导出内存限制（避免 Java / Node.js 爆内存）
export _JAVA_OPTIONS="${JAVA_OPTIONS}"
export NODE_OPTIONS="${NODE_OPTIONS}"

"${HVIGORW}" assembleHap --mode module -p module=entry@default -p buildMode=${BUILD_MODE} --no-daemon
```

- `--no-daemon` 确保构建完成后进程退出
- hvigorw 自带增量编译，即使重复执行也不会浪费太多时间
- 如构建失败，检查 `DEVECO_SDK_HOME` 是否已导出

## 步骤 2：拉起模拟器

### 2.1 检查 → 启动

```bash
source .claude/skills/harmonyos-build-deploy/config.sh

# 检查是否已有设备在线
if hdc list targets | grep -qE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
  echo "模拟器已在线，跳过启动"
else
  echo "需要启动模拟器实例: ${EMULATOR_INSTANCE}"
fi
```

### 2.2 启动命令

> **⚠️ 关键**：`Emulator.exe -start` 是阻塞式进程，进程退出 = 模拟器关闭。必须：
> - 放在独立常驻后台运行（DevEco Device Manager GUI / 独立终端 / `run_in_background: true`）
> - **不能**放进会被回收的临时后台任务

使用 `run_in_background: true` 启动模拟器：

```bash
source .claude/skills/harmonyos-build-deploy/config.sh
"${EMULATOR}" -start ${EMULATOR_INSTANCE}
```

如果 Emulator.exe 已在其他终端/GUI 运行，`-start` 会自动连接现有实例。

### 2.3 等待就绪

启动后轮询等待设备上线（冷启动约 8 秒）：

```bash
# 等待 hdc 设备上线（最多等 60 秒）
for i in $(seq 1 30); do
  if hdc list targets | grep -qE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
    echo "设备已上线"
    break
  fi
  sleep 2
done
```

### 2.4 确认系统就绪

```bash
# 不能用 sys.boot.completed（模拟器上 errNum 1002），用这个代替
hdc shell "param get const.product.model"  # 返回 "emulator" 即系统就绪
```

## 步骤 3：安装并启动应用

```bash
source .claude/skills/harmonyos-build-deploy/config.sh

# 安装（-r 覆盖安装，已安装同版本也不会报错）
hdc install -r "${HAP_PATH}"

# 启动
hdc shell aa start -a ${ABILITY_NAME} -b ${BUNDLE_NAME}
```

成功标志：
- 安装：输出 `install bundle successfully`
- 启动：输出 `start ability successfully`

## 踩坑记录

| 问题 | 原因 | 解决 |
|------|------|------|
| `hdc shell -f /data/...` 被误转为 `C:/Program Files/Git/data/...` | MSYS 自动转换路径 | `export MSYS_NO_PATHCONV=1`（config.sh 已设） |
| `hdc file recv ... C:/xxx` 拼成 `cwd\C:/xxx` | hdc 不认正斜杠盘符 | local 参数用相对文件名 |
| `sys.boot.completed` 取不到 | 模拟器上该属性 errNum 1002 | 改用 `param get const.product.model` 返回 `emulator` |
| hvigorw 找不到 | 项目根目录无 wrapper 脚本 | 从 DevEco Studio 安装目录调用 |
| Java `os::commit_memory` 失败 / `页面文件太小` | Windows 虚拟内存不足 | `export _JAVA_OPTIONS="-Xmx1024m -Xms256m -XX:+UseSerialGC"`，或增大系统页面文件 |
| Node.js `Fatal process out of memory: Zone` | ArkTS 编译器 V8 内存不足 | `export NODE_OPTIONS="--max-old-space-size=8192"` |
| `SDK component missing` / 找不到 SDK | `sdk-pkg.json` 中 `path` 与实际目录名不匹配 | 检查 `DEVECO_SDK_HOME/default/sdk-pkg.json`，修正 `path` 字段 |
| 构建 unsigned HAP | 默认 product 带签名配置 | 添加 `-p product=unsigned` 参数，需先在 `build-profile.json5` 中定义 unsigned product |
| 模拟器 -start 后进程被杀则模拟器也关 | 生命周期绑定 | 用独立常驻进程（`run_in_background: true` / 独立终端 / GUI） |
| 应用 `aa start` 报错 | 可能已运行 | 先 `pidof` 检查，已运行则跳过或先 `aa stop` |
