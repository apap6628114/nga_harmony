<div align="center">
  <img src="AppScope/resources/base/media/startIcon.png" alt="NGA OH Logo" width="120" height="120">
  <h1>NGA OH</h1>
  <p><strong>NGA 玩家社区 · 鸿蒙原生客户端</strong></p>
  <p>
    <img src="https://img.shields.io/badge/HarmonyOS-6.1.0(23)-0078D7?style=flat-square">
    <img src="https://img.shields.io/badge/ArkUI-%F0%9F%93%B1-ff69b4?style=flat-square">
    <img src="https://img.shields.io/badge/API-23-brightgreen?style=flat-square">
    <img src="https://img.shields.io/badge/license-GPL--2.0-blue?style=flat-square">
  </p>
</div>

---

## 简介

**NGA OH** 是基于 **HarmonyOS** 原生框架 **ArkUI (ArkTS)** 构建的 [NGA 玩家社区](https://nga.cn) 客户端。致力于在鸿蒙生态中提供流畅、原生的 NGA 论坛浏览与交互体验。

项目完整覆盖了 NGA 论坛的核心功能：板块浏览、帖子阅读、发帖回复、私信聊天、通知推送、AI 内容总结等，并针对手机、平板、二合一设备做了自适应布局适配。

---

## 功能特性

### 论坛浏览
- **板块列表** — 网格视图展示全部分区，支持收藏排序
- **帖子列表** — 分页加载，支持筛选（精华/收藏/作者）
- **帖子详情** — 楼层分页浏览，引用折叠，图片查看，热门回复
- **BBCode 渲染** — 完整解析 NGA 论坛 BBCode（引用、图片、表情、格式、表格、骰子、列表等）
- **HTML 降级解析** — JSON API 不可用时自动切换 HTML 解析
- **表情显示** — 内置 6 套 NGA 表情包（a2/ac/dt/ng/pg/pst）

### 用户系统
- **登录认证** — RSA 加密密码登录、Web 端登录，验证码支持
- **凭证导入/导出** — 支持从文件导入导出 NGA 登录凭证
- **用户主页** — 声望、勋章、管理版块、发帖统计
- **用户卡片** — 悬停/点击查看用户信息
- **AI 用户分析** — 发帖回帖时段分布、版块偏好分析

### 互动功能
- **发帖/回复** — BBCode 快捷工具栏，引用回复，附件上传，编辑回复
- **私信系统** — 会话列表，消息详情
- **通知中心** — 回复提醒、点赞通知、系统消息
- **投票** — 投票记录缓存
- **分享** — 帖子/主题分享

### 内容管理
- **收藏管理** — 收藏主题/版块
- **黑名单** — 用户黑名单管理
- **关键词过滤** — 自定义屏蔽关键词
- **用户备注** — 为用户添加备注标签
- **浏览历史** — 本地持久化浏览记录
- **签名控制** — 帖子中签名展开/折叠切换

### 界面与体验
- **自适应布局** — 手机/平板/二合一设备三档自适应（sm/md/lg breakpoints）
- **深色模式** — 支持浅色/深色/跟随系统主题切换
- **举手持/单手模式** — 基于运动传感器的一手操作优化
- **图片查看器** — 全屏手势缩放浏览
- **音频/视频播放** — 内置音视频播放与自适应检测
- **WebView** — 内嵌网页浏览
- **图片加载控制** — 可选择隐藏加载失败的图片

### 高级功能
- **全局搜索** — 帖子/主题搜索
- **自动签到** — 每日自动完成论坛签到
- **域名切换** — NGA 多域名自动切换与故障转移
- **请求限流** — 按域名的请求频率控制
- **AI 帖子总结** — 使用 HarmonyOS Agent 框架进行 AI 内容总结
- **语音朗读** — 基于 Core Speech Kit 的帖子内容语音播报，超长文本自动分段接力播放

---

## 架构

```
entry/src/main/ets/
├── entryability/              # 应用入口 UIAbility
├── entrybackupability/        # 备份恢复扩展能力
├── common/                    # 公共 UI 组件与工具
│   ├── BBCodeContentView      # BBCode 内容渲染组件
│   ├── PostItem               # 帖子楼层组件
│   ├── EmotionResources       # 表情资源管理
│   ├── ProfileCardPopup       # 用户卡片弹出层
│   ├── ReplyManager           # 回复管理（引用/编辑/新回复）
│   ├── ReplyDialog            # 回复编辑器弹窗
│   ├── ImageViewer            # 图片查看器
│   ├── AudioPlayer            # 音频播放器
│   ├── TtsPlayer              # 语音朗读（TTS 引擎管理）
│   ├── LazyDataSource         # 懒加载数据源合集
│   ├── Dialogs                # 通用弹窗（确认/备注/黑名单/关键词）
│   ├── Constants              # 颜色/主题/字体/域名/断点常量
│   ├── ShareUtils             # 分享工具
│   └── ...                    # Avatar, NavBar, Toast, Utils 等
├── model/                     # 数据模型与类型定义
│   ├── Forum                  # 版块模型
│   ├── Topic                  # 主题模型
│   ├── Thread                 # 帖子详情模型
│   ├── Post                   # 楼层/内容模型
│   ├── User                   # 用户模型
│   ├── Notification           # 通知模型
│   ├── Message                # 私信模型
│   └── BBCodeNode             # BBCode 解析节点类型
├── pages/                     # 页面组件
│   ├── Index                  # 启动/加载页
│   ├── LoginPage              # 登录页（密码+Web+凭证导入）
│   ├── MainPage               # 主页面（自适应三栏布局）
│   ├── ThreadPanel            # 帖子详情
│   ├── TopicListPanel         # 主题列表
│   ├── ProfilePanel           # 用户主页
│   ├── SearchPanel            # 搜索
│   ├── SettingsPanel          # 设置
│   ├── AgentAnalysisPage      # AI 用户分析
│   ├── PostSummaryPage        # AI 帖子总结
│   ├── MessageListPanel       # 私信列表
│   ├── NotificationPanel      # 通知中心
│   ├── WebViewPanel           # 内嵌网页
│   └── ...                    # 黑名单/关键词/备注/浏览历史等面板
├── parser/                    # NGA API 响应解析器
│   ├── ForumParser            # 版块列表解析
│   ├── TopicParser            # 主题列表解析
│   ├── ThreadParser           # 帖子内容解析
│   ├── HtmlThreadParser       # HTML 帖子降级解析
│   ├── NotificationParser     # 通知解析
│   ├── MessageParser          # 私信解析
│   └── JsonUtil               # JSON 预处理
├── service/                   # 业务逻辑层
│   ├── NgaClient              # HTTP 客户端（GB18030、RSA、域名故障转移、限流）
│   ├── NgaApi                 # API 业务封装
│   ├── BBCodeParser           # BBCode 解析器
│   ├── BBCodeCache            # 解析缓存（LRU）
│   ├── ContentParser          # BBCode→HTML 转换
│   ├── SessionStore           # 会话管理
│   └── Throttle               # 请求频率控制
└── store/                     # 状态管理层
    ├── AppStore               # 全局应用状态（主题/设置/收藏/缓存）
    ├── RouterStore            # 导航路由状态
    ├── FloatingLayerStore     # 弹窗/浮层管理
    ├── BrowseHistoryStore     # 浏览历史（持久化）
    ├── VoteRecordStore        # 投票记录缓存
    └── PreferencesStore       # KV 键值持久化
```

### 分层设计

| 层 | 职责 |
|---|---|
| **Pages** | 页面编排、布局、页面级状态 |
| **Store** | 全局状态管理（响应式 `@State` / `@Observed`） |
| **Service** | API 调用、数据转换、BBCode 解析、缓存 |
| **Parser** | NGA API 响应数据反序列化 |
| **Model** | 类型定义、数据实体 |
| **Common** | 可复用 UI 组件 |

---

## 技术栈

| 类别 | 技术 |
|---|---|
| **操作系统** | HarmonyOS 6.1.0 (API 23) |
| **UI 框架** | ArkUI（声明式 UI，`@Component` / `@State` / `@Entry` / `@Observed`） |
| **语言** | ArkTS（基于 TypeScript 的鸿蒙原生语言） |
| **构建工具** | Hvigor + DevEco Studio |
| **应用模型** | Stage Model |
| **网络** | `@kit.NetworkKit`（http） |
| **加密** | `@kit.CryptoArchitectureKit`（RSA） |
| **并发** | `@kit.ArkTS`（taskpool） |
| **语音** | `@kit.CoreSpeechKit`（textToSpeech） |
| **测试** | `@ohos/hypium` + `@ohos/hamock` |

---

## 快速开始

### 环境要求

- [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) 5.0+
- HarmonyOS SDK 6.1.0 (API 23)
- Node.js 20+

### 构建运行

```bash
# 克隆仓库
git clone https://github.com/<your-username>/nga_oh.git

# 使用 DevEco Studio 打开项目根目录

# 构建 debug HAP
hvigorw assembleHap --mode debug

# 构建 release HAP
hvigorw assembleHap --mode release

# 运行 ohosTest
hvigorw run ohosTest
```

> 也可直接在 DevEco Studio 中点击 `Run` 按钮部署到真机或模拟器。

### 权限说明

应用需要以下权限：

- `ohos.permission.INTERNET` — 网络访问，用于 NGA API 通信
- `ohos.permission.DETECT_GESTURE` — 手势检测，用于图片查看器等交互

入口文件：`entry/src/main/module.json5:15:22`

---

## 预览

<details>
<summary>📱 点击展开截图预览（共 7 张）</summary>

<img src="img/Screenshot_2026-05-31T204948.png" alt="截图 1" width="240">
<img src="img/Screenshot_2026-05-31T205017.png" alt="截图 2" width="240">
<img src="img/Screenshot_2026-05-31T205030.png" alt="截图 3" width="240">
<img src="img/Screenshot_2026-05-31T205043.png" alt="截图 4" width="240">
<img src="img/Screenshot_2026-05-31T205051.png" alt="截图 5" width="240">
<img src="img/Screenshot_2026-05-31T205112.png" alt="截图 6" width="240">
<img src="img/Screenshot_2026-05-31T205148.png" alt="截图 7" width="240">

</details>

---

## 开发指南

### 编码规范

本项目遵循 HarmonyOS ArkTS 严格语法约束，详细信息参见 [AGENTS.md](AGENTS.md)，主要包括：

- 不支持 `any` / `unknown` 类型
- 不支持解构赋值
- 不支持 `for..in` 遍历对象
- 不支持索引签名，使用数组替代
- 不支持 `Function.apply` / `call` / `bind`
- 不支持 `in` 运算符，使用 `instanceof` 替代

### 动画规范

- 优先使用声明式 UI 与 `@State` 驱动动画
- 复杂子组件设置 `renderGroup(true)` 减少渲染批次
- 避免在动画中改变 `width` / `height` / `padding` / `margin` 等布局属性

---

## 致谢

- [NGA 玩家社区](https://nga.cn) — 国内领先的游戏综合讨论社区
- [Justwen/NGA-CLIENT-VER-OPEN-SOURCE](https://github.com/Justwen/NGA-CLIENT-VER-OPEN-SOURCE) — Android 端开源参考实现

---

## 许可证

GNU General Public License v2.0 — 详见 [LICENSE](LICENSE)

---

<p align="center">
  用 ❤️ 和 ArkUI 构建 · 鸿蒙原生体验
</p>
