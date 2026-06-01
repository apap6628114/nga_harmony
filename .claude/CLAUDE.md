# 项目规则 — NGA OH (HarmonyOS ArkUI)

NGA 论坛客户端，stage 模型，API 6.1.0(23)，单 entry 模块。

## 构建命令

该工程依赖 DevEco Studio 内置工具链（非独立 CLI），需要在 DevEco Studio 所在机器上运行。

**环境变量：**
```bash
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
```

**命令（路径是 DevEco Studio 安装目录，需按实际调整）：**
- 构建 HAP（调试）:
  ```
  "/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat" \
    assembleHap --mode module -p module=entry@default -p buildMode=debug --no-daemon
  ```
- 构建 HAP（发布）:
  ```
  hvigorw assembleHap --mode module -p module=entry@default -p buildMode=release
  ```
- 清理: `hvigorw clean`
- **注意** 项目根目录无 `hvigorw` Wrapper 脚本，必须从 DevEco Studio 安装路径调用。常用别名：
  ```bash
  alias hvigorw="/c/Program\ Files/Huawei/DevEco\ Studio/tools/hvigor/bin/hvigorw.bat"
  ```

## 项目结构

`entry/src/main/ets/` 目录组织：

| 目录 | 文件数 | 职责 |
|------|--------|------|
| `pages/` | 24 | 页面级组件 |
| `common/` | 30 | 可复用 UI 组件、工具类、常量 |
| `store/` | 8 | 全局状态管理 |
| `service/` | 9 | 网络请求、外部服务调用 |
| `model/` | 11 | 数据模型定义 |
| `parser/` | 10 | BBCode 等富文本解析 |
| `entryability/` | 1 | 应用生命周期入口 |
| `entrybackupability/` | 1 | 备份恢复能力 |

## 规则索引

ArkTS 语法编译约束 @.claude/rules/ArkTS-syntax.md
HarmonyOS API 及动画规范 @.claude/rules/HarmonyOS-development.md
