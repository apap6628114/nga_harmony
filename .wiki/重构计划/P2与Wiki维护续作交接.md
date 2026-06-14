# P2 与 Wiki 维护 — 续作交接

> 本文档供**新会话**接续工作使用。新会话无当前 context，请先读本文档 + [模块可维护性重构计划](./模块可维护性重构计划.md) + `git log --oneline -20`，即可完整接续。

---

## 一、当前状态（截至本次会话结束 2026-06-14）

- **分支**：`refactor/modularity-plan`（保留，P2 可继续基于它）；`main` 已合并 P0+P1
- **main HEAD**：`8fd672d`（docs: 重构计划文档），其下 13 个重构 commit
- **完成**：P0（7 项）+ P1（6 项）= **13 项重构**，每项经 implementer + spec compliance review + code quality review 三阶段，**全部 BUILD SUCCESSFUL + 设备回归全通过**（BBCode/登录/分页/设置/列表等核心路径确认行为保持）
- **待做**：P2（4 项大重构）+ Wiki 维护（重构涉及的 6+ 篇 wiki 需更新）
- **完整计划文档**：[模块可维护性重构计划.md](./模块可维护性重构计划.md)（含 17 项详情、依赖图、ArkTS 约束、回归矩阵）

### 已完成的 13 项 commit（main 上）

```
8fd672d docs(wiki): 新增模块可维护性重构计划
a91b3a3 P1-6 BBCodeParser 按解析阶段拆分
a187aae P1-5 NgaClient 拆分编解码下沉 common
1b8aa44 P1-4 非状态工具移出 store 归位 common
6107202 P1-3 提取 PaginationManager 基类
9c1a80a P1-2 提取 RequestQueue 统一并发调度
4af94ec P1-1 BBCode 解析归位 parser + 合并重复
1c60385 P0-7 SettingsStore 按设置域拆分
276dac6 P0-6 common 按职责重组为子目录
3704b1a P0-5 NgaApi 按业务域拆分 api/
c53e735 P0-4 提取通用 SettingRow 组件
1884bd5 P0-3 提取 LoadingStateView/ErrorStateView/EmptyStateView
66c34e7 P0-2 提取 BaseLazyDataSource 基类
56fbd9f P0-1 领域数据类从 NgaApi 迁出 model/
```

---

## 二、P2 四项任务（详见计划文档第七章）

| 项 | 任务 | 工作量 | 依赖 | 核心风险 |
|---|---|:---:|:---:|---|
| P2-1 | HtmlThreadParser(669 行) 拆 5 类抽象（ScanState/PostArgScanner/DomMarkerExtractor/AttachParser + index 装配） | M | 无 | 手写状态机重复 4 次、DOM 提取 6 个同构函数；状态机返回 class 非元组 |
| P2-2 | BBCodeContentView(877)/PostItem(611) 按节点类型拆子组件 | L | 无 | @Builder 不能跨 struct 调用（用 @BuilderParam）、BBNode 15+ 字段逐字段 @Prop |
| P2-3 | ThreadPanel(999) 分页预取引擎下沉 store + ProfilePanel 统计 Grid 数据驱动 + 清理死代码 | L | P1-3, P0-3, P0-4 | ThreadPanel 大半是纯逻辑绑 @Component；handleCheckin/dispatchAction 死代码 |
| P2-4 | 命名归一化（Panel/Page/Component）+ 重试执行器抽取 + AppStorage key 集中注册 | M | 无 | 命名变更影响多文件；ActivityPanelComponent 路由不能用 Record 分发 |

**建议执行顺序**：P2-1 → P2-2 → P2-3 → P2-4（P2-3 依赖 P1-3/P0-3/P0-4 已满足）。也可按依赖图自由排。

---

## 三、Follow-up 清单（P0+P1 review 留下的 Minor，可批量清理）

这些是各次 code review 发现但未阻塞合并的小项，新会话可批量处理或在对应 P2 任务里顺手修：

| 来源 | follow-up | 修复成本 |
|---|---|---|
| P0-1 | `ThreadPagination` 同名：`model/ThreadResult.ets` 的 class vs `model/Thread.ets` 的 interface（建议 class 改名 ThreadPageInfo 或 interface 改名） | S |
| P0-2 | `BaseLazyDataSource.updateAt` 内联循环可复用 `this.notifyDataChange`（1 行 DRY） | S |
| P0-3 | `PageStateView.ets` 加文件头 JSDoc | S |
| P0-3 | `BlacklistPanel.ets` 空态可接入 `EmptyStateView`（规格完全一致，零成本） | S |
| P0-4 | `ProfilePanel.dispatchAction`（P0-4 产生的死代码）+ `handleCheckin`（pre-existing）→ **P2-3 计划清理** | S |
| P0-5 | `ThreadApi.ets` 同模块 import 合并（`ngaClient` + `ngaUploadFile` 两行→一行） | S |
| P0-5 | `ForumApi.extractSnippet` pre-existing 死代码 | S |
| P0-6 | `datasource/LazyDataSource.ets` 存在 common→store 的 type 反向依赖（`FavBoard`/`BlacklistEntry` 应迁 model） | S |
| P1-2 | `Throttler.ets` JSDoc 不足（迁移暴露的 pre-existing 债）；`RequestQueue` 补"不做去重"注释 | S |
| P1-3 | `PaginationManager.reset` 的 `hasMore=true` 加注释说明（与 applyState 不同） | S |
| P1-5 | `loginPassword` 通道统一（**需先扩展传输层** `httpReq`/`HttpResponse`/`ngaRequest` 透传 `response.header`，再让 loginPassword 走统一通道） | M |
| P1-5 | commit `a187aae` 标题"loginPassword 走统一通道"与实际"保守保留"不符（git history 文案，可改 commit message 或忽略） | — |
| P1-6 | `handleFlash` 未复用 `guessMediaTypeFromExt`（扩展名常量重复；FLASH 兜底使完全替换不平凡，可抽常量到 lexer） | S |
| P1-6 | `handleFormat.ets` 命名（8 个杂项标签，建议改名 `handleMisc` 或拆分） | S |
| P1-6 | `parser.ets` 承担 `parseTableContent`/`parseListItems` 辅助（循环依赖权衡，可接受） | — |

---

## 四、Wiki 维护清单（maintain-wiki 规则要求）

P0+P1 重构改变了大量模块的文件结构/代码引用，按 [.claude/rules/maintain-wiki.md](../../.claude/rules/maintain-wiki.md) 规则，以下 wiki 需同步更新（代码引用行号、架构图、文件结构表、配置参数）：

| Wiki 文档 | 影响重构 | 需更新内容 |
|---|---|---|
| `.wiki/服务层/API通信.md` | P0-1/P0-5/P1-5 | NgaApi 拆 `api/` 7 子文件、NgaClient 拆分（编解码下沉 common）、领域类迁 model、barrel re-export 模式 |
| `.wiki/服务层/BBCode解析与渲染.md` | P1-1/P1-6 | BBCodeParser 拆四部分（lexer/block-handlers/inline-parser/parser）、解析归位 `parser/bbcode/`、实体解码/附件 URL 合并、ContentParser 删除 |
| `.wiki/状态管理层/Store架构.md` | P0-7/P1-4 | SettingsStore 拆门面+8 domain 子 store、facade 转发模式、非状态工具移出 store（FilterListManager/SerialQueue/PreferencesStore/ToastManager） |
| `.wiki/公共组件模块/公共组件概述.md` | P0-2/P0-3/P0-4/P0-6 | BaseLazyDataSource 基类、页面态组件、SettingRow、common 8 子目录重组 |
| `.wiki/数据模型/数据模型概述.md` | P0-1 | 领域类迁入 model/（PostInfo/UserInfo/ThreadResult 等）、`model/Api.ets` 删除 |
| `.wiki/解析器模块/数据解析器.md` | P1-1 | BBCodeParser/BBCodeCache/BBCodeParseTask/HtmlParseTask 迁入 parser/、parser/_shared、JsonUtil→NgaJsonSanitizer |
| `.wiki/欢迎阅读.md` | — | 已更新（重构与演进引用，本次会话已做） |
| `.wiki/架构决策/` | 全部 | **新增 ADR**（见下） |

### 建议新增的 ADR（架构决策记录）

按 maintain-wiki 规则，架构决策变更需在 `.wiki/架构决策/` 新增 ADR（现有 001、002）：

- **003-barrel-re-export 模式**：NgaApi/BBCodeParser 拆分时用 barrel re-export 保持调用方零改动（vs 直接改引用方）
- **004-facade 转发模式**：SettingsStore 拆分用 facade 转发 setter 保持调用方零改动（vs 调用方改 `settingsStore.theme.xxx`）
- **005-@Observed 继承位置**：@Observed 必须在最终子类（ArkUI 状态观测按具体类注册），基类 abstract 不加
- **006-保守合并原则**：行为保持优先于字面合并（decodeHtmlEntities 保留 2 函数、resolveAttachUrl 保留 2 版本的判断依据）

---

## 五、关键约束与流程

### ArkTS 约束（违反会编译失败，P2 必守）

- 不支持解构（赋值/声明/参数/返回）→ 状态机返回 `class {value; endPos}` 非元组
- 不允许索引签名调度 → 路由/handler 保持 if 顺序，不用 `Record<string,arrow>` 分发
- 不支持对象字面量作类型 → 配置用显式 class
- `@Observed` 在最终子类（ArkUI 按具体类注册）
- `@Builder` 不能跨 struct 调用 → 拆组件用 `@BuilderParam` 传渲染回调
- 类布局编译时固定 → 迁移类不改字段类型/顺序/名称
- `@Prop` 不能传函数引用 → onClick/onChange 用普通箭头属性
- 不支持 `import * as`

### 编译验证命令（每项重构后必跑）

```bash
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
"/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat" \
  assembleHap --mode module -p module=entry@default -p buildMode=debug --no-daemon
```

### Subagent-Driven 流程（每项 P2 任务）

每项 P2 任务走三阶段（已证明有效）：
1. **implementer** subagent（general-purpose）：执行重构 + 编译 + commit + self-review
2. **spec compliance review** subagent：独立验证（不信报告）—— 行为等价、字段原样、调用方零改动、编译
3. **code quality review** subagent：设计/JSDoc/ArkTS/整洁度
- review 发现 issue → implementer fix → re-review → 通过后 complete
- **git 卫生**：每次 commit 只 add 任务文件，不 add `.claude/`/`.wiki/`/`.codegraph/`/`entry/.hvigor/`/`settings.local.json` 等工作区 dirty 文件
- **commit message** 中文 conventional commits 风格，结尾加 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

### 回归验证点（设备回归，P2 后必做）

| 路径 | 关注 | 对应 P2 |
|---|---|---|
| BBCode 渲染 | 全标签（quote/collapse/code/list/table/flash/img/url/表情/格式化） | P2-2 |
| 帖子详情翻页/预取/投票 | UI 响应式（@Observed） | P2-3 |
| 个人中心统计/签到 | Grid 数据驱动、死代码清理后签到正常 | P2-3 |
| 帖子加载（HTML 模式） | HtmlThreadParser 拆分后字段映射正确 | P2-1 |
| 全应用导航 | 命名归一化后路由正常 | P2-4 |

---

## 六、已知保守决策（经验，避免新会话重复踩坑）

P0+P1 中有几次"计划说合并/统一，实际保守保留"的判断，新会话遇到类似情况可参考：

1. **loginPassword 通道统一（P1-5）保守保留**：loginPassword 必须读 `response.header['set-cookie']`，而统一通道 `ngaRequest→httpReq` 只返回 `{status,body}` 丢弃 header。强行走统一需扩展传输层签名（影响所有 API）。→ 留 follow-up，先扩展传输层透传 header。
2. **decodeHtmlEntities 保留 2 函数（P1-1）**：BBCodeParser 版含 `<br>`→`\n`+标签剥离（BBCode 专属），套用到纯文本会吞合法 `<`。→ 保留 `decodeHtmlEntities`（BBCode）+ `unescapeHtml`（通用）。
3. **resolveAttachUrl 保留 2 版本（P1-1）**：ContentParser 版拼 `/attachments/` vs BBCodeParser 版原样返回，语义不兼容。→ `_shared/AttachUrl.resolveAttachUrl` + BBCodeParser 私有 `resolveMediaUrl`。
4. **Topic 强类型化保留 object[]（P1-3）**：无现成 `TopicItem` class，强类型化需改多处调用方。→ 保留 `object[]` + `as`（行为保持优先）。
5. **@Observed 继承（P1-3）**：查阅华为官方文档确认 @State 属性观察基于 `Object.keys(instance)`（与声明在哪个类无关），@Observed 在子类正确，无运行时风险。

**原则**：行为保持优先于字面"合并/统一"。若合并会改变运行时行为，保守保留 + follow-up，并在 commit/report 说明理由。

---

## 七、如何开始（推荐第一步）

1. **读取上下文**：本文档 + [模块可维护性重构计划.md](./模块可维护性重构计划.md) + `git log --oneline -20` + `git branch -vv`
2. **确认分支**：`refactor/modularity-plan` 保留可用；或从 main 新开 `refactor/p2`（`git checkout main && git checkout -b refactor/p2`）
3. **选择起点**：建议从 **P2-1（HtmlThreadParser 拆分）** 开始——相对独立、无前置依赖
4. **执行**：用 subagent-driven（用户原话："Subagent-Driven 进行"），每项 P2 走 implementer + spec review + code review
5. **批量化 follow-up**：可在 P2 任务间隙，或 P2 全部完成后，批量清理第三章的 Minor follow-up
6. **Wiki 维护**：P2 全部完成后（或与 P2 并行），按第四章更新 wiki + 新增 ADR；用 `npx mermaid-sonar ".wiki/**/*.md"` 校验 Mermaid 图（maintain-wiki 规则要求零 error 零 warning）

### 关键提示

- 项目无测试基建，验证 = DevEgo 编译 + 设备回归（核心路径）
- 全局规则见 `.claude/CLAUDE.md` + `.claude/rules/`（ArkTS-syntax、HarmonyOS-development、maintain-wiki、write-technical-wiki）
- 跨会话记忆已存（`refactor-modularity-progress`），新会话可召回本次进度
