# NGA OH 架构治理设计

## 背景

退出登录流程审计发现 6 项资源泄漏/状态不一致问题，修复过程中暴露了深层历史技术债：

| # | 技术债 | 根因 |
|---|--------|------|
| 1 | `SerialQueue` 无取消能力 | 设计时未考虑"紧急停止"场景 |
| 2 | Store uid 保护策略不统一 | 无统一规范，HistoryStore/VoteStore 用入参捕获，其余用实时校验 |
| 3 | `AuthApi.logout()` 是死代码 | API 层与 Store 层职责边界模糊 |
| 4 | `clearAuth`/`logout` 职责分散 | 无集中退出入口，新加 Store 易遗漏 reset |
| 5 | setTimeout 管理各自为政 | 13 处 setTimeout 无统一取消模式 |
| 6 | 无退出流程集成测试 | 导致问题长期未被发现 |
| 7 | ArkTS 防御性编程不足 | 缺少 AbortController 等现代机制替代方案 |

## 设计

### 架构概览

```
┌──────────────────────────────────────────────────┐
│               LogoutOrchestrator                 │
│  (编排层：持有 NgaClient + AppStore 引用)         │
├──────────────────────────────────────────────────┤
│  orchestrator.logout(context) →                  │
│    1. AuthApi.logoutOnlyRemote(token)  服务端登出 │
│    2. writeQueue.cancel()              排空队列   │
│    3. writeQueue.reset()               重置队列   │
│    4. authStore.clearAuth()            清空认证   │
│    5. storeA.reset() ...              全部 Store  │
│    6. routerStore.reset()             重置导航   │
│    7. navigate to LoginPage           跳转       │
└──────────────────────────────────────────────────┘
        ↕ 调用          ↕ 继承
┌─────────────────────┐ ┌─────────────────────────┐
│    AuthApi           │ │      BaseStore<T>        │
│  (纯 API 层)         │ │  (抽象基类)               │
│                      │ │                          │
│  logoutOnlyRemote()  │ │  - state: T              │
│    → ngaClient       │ │  - init() / reset()      │
│      .logout()       │ │  - generation 保护        │
│                      │ │  - uidGuard()             │
└─────────────────────┘ │  - writeQueue 注入         │
                        └─────────────────────────┘
                                 ↕ 继承
                        ┌─────────────────────────┐
                        │  AuthStore               │
                        │  SettingsStore           │
                        │  CategoryStore           │
                        │  ProfileStore            │
                        │  NotificationStore       │
                        │  VoteStore               │
                        │  HistoryStore            │
                        └─────────────────────────┘
```

### 核心变更

#### 1. LogoutOrchestrator（新文件）

**路径：** `entry/src/main/ets/service/LogoutOrchestrator.ets`

```typescript
class LogoutOrchestrator {
  async logout(context: UIContext): Promise<void> {
    const token = appStore.auth.token
    if (token) {
      try { await AuthApi.logoutOnlyRemote(token) } catch (e) { /* 不阻塞 */ }
    }
    appStore.clearAuth()
    context.getRouter().replaceUrl({ url: 'pages/LoginPage' })
  }
}
```

**职责：**
- 持有 `NgaClient` 和 `AppStore` 引用（通过模块单例，不额外依赖注入）
- 编排"服务端登出 → 本地清理 → 导航跳转"完整流程
- 服务端登出失败不阻塞本地清理

**依赖关系：**
- `LogoutOrchestrator` → `AuthApi`（纯 API 调用）
- `LogoutOrchestrator` → `AppStore.clearAuth()`（内部编排全部 Store reset）

#### 2. BaseStore 抽象基类

**路径：** `entry/src/main/ets/store/BaseStore.ets`

```typescript
abstract class BaseStore<T> {
  abstract state: T
  protected store!: PreferencesStore
  protected writeQueue!: SerialQueue
  protected auth!: AuthState
  protected generation: number = 0

  // 子类必须实现
  abstract init(store: PreferencesStore, queue: SerialQueue, auth: AuthState): Promise<void>
  abstract reset(): void

  // 已过时判断：异步回调前调用
  protected isCurrent(gen: number): boolean {
    return gen === this.generation
  }

  // 写入队列前检查 uid 有效性
  protected uidGuard(): boolean {
    return !!this.auth.uid
  }
}
```

**改造范围（7 个 Store）：**

| Store | 当前 reset() 内容 | 改造内容 |
|-------|------------------|---------|
| AuthStore | 清 state + persistAuth | 继承 BaseStore，基类托底 generation++ |
| SettingsStore | new SettingsState() + 子域 reset | 继承 BaseStore |
| CategoryStore | 清缓存 + refreshGeneration++ | 对齐到 BaseStore.generation |
| ProfileStore | cache.clear() | 继承 BaseStore，精简 reset |
| NotificationStore | 清通知缓存 + 复位置零 | 继承 BaseStore |
| VoteStore | voteCache = {} | 继承 BaseStore + uidGuard |
| HistoryStore | historyItems = [] | 继承 BaseStore + uidGuard |

#### 3. AuthApi 瘦身

**现有：**
```typescript
AuthApi.logout(token) → destroySession(token)  // 混合 API 和 Store 操作
```

**改造为：**
```typescript
AuthApi.logoutOnlyRemote(token) → ngaClient.logout({uid, cid})  // 仅网络请求
```

移除 `destroySession` 调用，由 `LogoutOrchestrator` 统一编排本地清理。

#### 4. AppStore.clearAuth 强化

本次修复已新增的 `cancel/reset/routerStore.reset` 保持不变，追加：
- 切换到由 `LogoutOrchestrator` 统一入口调用（而非 SettingsPanel 直接调）

#### 5. HDC 集成测试

**路径：** `entry/src/test/logout-e2e.sh`

覆盖范围（中等覆盖）：
1. 退出登录端到端流程：点击退出 → 确认 → 跳转登录页 → 验证 auth 状态已清空
2. 验证 RouterStore/导航状态已重置（boardSlot = null, activityStack = []）
3. 验证重新登录后首页干净
4. 验证 votes/history 不残留写入
5. 验证 SerialQueue 的 cancel/reset
6. 验证 CategoryStore 的 generation 回调不触发
7. 验证服务端登出接口可达（不强制成功）

#### 6. 开发检查清单

在项目 CLIFFS.md 或 CLAUDE.md 中新增 Store 开发检查项：

- [ ] 是否继承了 BaseStore？
- [ ] reset() 中是否调用了 super.reset()？
- [ ] 异步回调中是否调用了 isCurrent(gen)？
- [ ] 写入前是否调用了 uidGuard()？
- [ ] 退出登录是否会触发本 Store 的 reset()？

## 实施顺序

| 阶段 | 任务 | 依赖 | 工作量 |
|------|------|------|--------|
| **1** | 创建 BaseStore 基类 | 无 | 1 个文件 ~50 行 |
| **2** | 逐个改造 7 个 Store 继承 BaseStore | 阶段 1 | 7 个文件各 ~10-30 行 |
| **3** | 创建 LogoutOrchestrator + AuthApi 瘦身 | 阶段 2 | 2 个文件 ~80 行 |
| **4** | SettingsPanel 切换到 LogoutOrchestrator | 阶段 3 | 1 个文件 ~5 行 |
| **5** | HDC 集成测试 | 阶段 4 | 1 个脚本 ~60 行 |
| **6** | 更新开发检查清单 | 阶段 5 | 1 个文件 ~5 行 |

## 边缘情况

| 场景 | 处理 |
|------|------|
| 服务端登出网络超时 | Orchestrator catch 异常，继续本地清理，不阻塞 UI |
| SerialQueue 当前有任务正在执行 | cancel() 不影响当前执行任务，reset() 切换 Promise 链 |
| 连续两次快速退出 | 第二次退出时 token 已为空，跳过服务端登出，直接清理 |
| 退出时 setTimeout 刚好触发 | generation 版本标记使过时回调自动放弃执行 |
| 退出后立即重新登录 | clearAuth + reset 全部同步完成，RouterStore 干净，登录后首页正确渲染 |

## 不做的范围

- 不改造 NgaClient 的 HTTP 请求取消机制（工程量过大，风险高）
- 不改动 PreferencesStore 的 flush 机制
- 不引入第三方依赖注入框架（ArkTS 约束 + 项目规模不必要）
