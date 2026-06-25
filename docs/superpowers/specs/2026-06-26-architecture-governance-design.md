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
                         ┌─────────────────────────────────────────┐
                         │          LogoutOrchestrator              │
                         │  (编排层：持有 NgaClient + AppStore 引用) │
                         ├─────────────────────────────────────────┤
                         │  orchestrator.logout(context) →          │
                         │    1. AuthApi.invalidateServerSession()  │
                         │    2. AppStore.clearAuth()               │
                         │        ├ writeQueue.cancel() + reset()   │
                         │        ├ authStore.clearAuth()           │
                         │        ├ storeA.reset() ...              │
                         │        ├ floatingLayerStore.clear()      │
                         │        └ routerStore.reset()             │
                         │    3. navigate to LoginPage              │
                         └─────────────────────────────────────────┘
                                 ↕ 使用              ↕ 继承
                ┌──────────────────────┐   ┌──────────────────────────┐
                │      AuthApi          │   │      BaseStore           │
                │  (纯 API 层)          │   │  (抽象基类，T 为类型标注) │
                │                       │   │                          │
                │  invalidateServer     │   │  - state: T              │
                │  Session(token)       │   │  - init() / reset()      │
                │    → ngaClient        │   │  - generation(全局版本)   │
                │      .logout()        │   │  - isCurrent(gen)        │
                └──────────────────────┘   │  - uidGuard()             │
                                           │  - writeQueue 注入        │
                                           └──────────────────────────┘
                                                    ↕ 继承
                              ┌──────────────────────────────────────────┐
                              │  AuthStore | SettingsStore | CategoryStore│
                              │  ProfileStore | NotificationStore         │
                              │  VoteStore | HistoryStore                 │
                              │  (FloatingLayerStore 有 clear() 但不继承) │
                              └──────────────────────────────────────────┘
```

### 核心变更

#### 1. LogoutOrchestrator（新文件）

**路径：** `entry/src/main/ets/service/LogoutOrchestrator.ets`

```typescript
class LogoutOrchestrator {
  async logout(context: UIContext): Promise<void> {
    const token = appStore.auth.token
    // 1. 服务端登出（纯 API，不碰 Store）
    if (token) {
      try { await AuthApi.invalidateServerSession(token) } catch (e) { /* 不阻塞 */ }
    }
    // 2. 本地清理 — 委托给 AppStore.clearAuth()
    //    clearAuth() 内部按严格顺序执行：
    //    writeQueue.cancel() → writeQueue.reset() → authStore.clearAuth()
    //    → 各 Store reset() → floatingLayerStore.clear() → routerStore.reset()
    appStore.clearAuth()
    // 3. 导航到登录页
    context.getRouter().replaceUrl({ url: 'pages/LoginPage' })
  }
}
```

**职责：**
- 编排"服务端登出 → 本地清理 → 导航跳转"完整流程
- 服务端登出失败不阻塞本地清理
- `UIContext` 由调用方（`@Component`）传入

**调用方式：**
```typescript
// SettingsPanel.ets
orchestrator.logout(this.getUIContext())
```

#### 2. BaseStore 抽象基类

**路径：** `entry/src/main/ets/store/BaseStore.ets`

```typescript
abstract class BaseStore<T> {
  abstract state: T
  protected store!: PreferencesStore
  protected writeQueue!: SerialQueue
  protected auth!: AuthState

  /**
   * Store 级全局版本号。
   * reset() 时自增，使所有已捕获 generation 的异步回调自动失效。
   * 适用于"整个 Store 重置后不应再执行旧操作"的场景。
   * 如果子类有独立的异步操作流需各自版本控制，应单独声明字段。
   */
  protected generation: number = 0

  /**
   * 供子类 init 调用的依赖注入辅助方法。
   * 各 Store init 签名不同（2 或 3 个参数），子类在自身 init 中调用此方法。
   * init 不作为基类抽象方法：ArkTS 不支持方法重载，各 Store 自行声明 init 签名。
   */
  protected setDeps(store: PreferencesStore, queue: SerialQueue, auth?: AuthState): void {
    this.store = store
    this.writeQueue = queue
    if (auth) this.auth = auth
  }

  /** 子类 reset 完成后应调用 super.reset() 触发 generation++ */
  reset(): void {
    this.generation++
  }

  /** 异步回调前调用：generation 不匹配说明已过时，放弃执行 */
  protected isCurrent(gen: number): boolean {
    return gen === this.generation
  }

  /** 写入队列前检查 uid 是否仍有效（auth 未注入时返回 true 不拦截） */
  protected uidGuard(): boolean {
    return this.auth ? !!this.auth.uid : true
  }
}
```

**关于泛型 `T` 的说明：**
- `T` 用于标注 `state` 的类型，方便子类声明时明确状态类型
- 受 ArkTS 约束限制（不支持索引访问类型、条件类型、映射类型），基类中无法编写基于 `T` 的通用逻辑（如泛型序列化），`T` 的角色是"类型文档标注"
- 各子类仍需在自身类体中完整声明 `state` 类型

**改造范围（8 个 Store）：**

| Store | 当前 reset() 内容 | 改造内容 | 继承 BaseStore？ |
|-------|------------------|---------|-----------------|
| AuthStore | 清 state + persistAuth | 继承基类，generation++ 托底 | 是 |
| SettingsStore | new SettingsState() + 子域 reset | 继承基类 | 是 |
| CategoryStore | 清缓存 + refreshGeneration++ | 对齐到 BaseStore.generation | 是 |
| ProfileStore | cache.clear() | 继承基类，精简 reset | 是 |
| NotificationStore | 清通知缓存 + 复位置零 | 继承基类 | 是 |
| VoteStore | voteCache = {} | 继承基类 + uidGuard | 是 |
| HistoryStore | historyItems = [] | 继承基类 + uidGuard | 是 |
| FloatingLayerStore | 无 reset，有 clear() | 不继承 BaseStore（纯 UI 状态，无需 init/auth/writeQueue），退出时单独调 clear() | 否 |

#### 3. AuthApi 瘦身

**现有：**
```typescript
AuthApi.logout(token) → destroySession(token)  // 混合 API 和 Store 操作
```

**改造为：**
```typescript
AuthApi.invalidateServerSession(token) → ngaClient.logout({uid, cid})  // 仅网络请求
```

移除 `destroySession` 调用，由 `LogoutOrchestrator` 统一编排本地清理。

#### 4. AppStore.clearAuth 强化

保持本次修复已新增的 `cancel/reset/routerStore.reset`，追加：
- 新增 `floatingLayerStore.clear()` 调用
- 切换到由 `LogoutOrchestrator` 统一入口调用

完整 `clearAuth()` 执行顺序：
```
writeQueue.cancel()       → 取消队列中残留的旧 uid 写入任务
writeQueue.reset()        → 重置队列，让后续 enqueue 正常执行
authStore.clearAuth()     → 清理 sessions map + 清空 AuthState + persistAuth
settingsStore.reset()
categoryStore.reset()     → generation++ 使 setTimeout 回调失效
profileStore.reset()
notificationStore.reset()
voteStore.reset()
historyStore.reset()
floatingLayerStore.clear()  → 清空弹窗栈
routerStore.reset()       → 清理导航状态
```

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

在项目 CLAUDE.md 中新增 Store 开发检查项：

- [ ] 是否继承了 BaseStore？
- [ ] reset() 中是否调用了 super.reset()？
- [ ] 异步回调中是否调用了 isCurrent(gen)？
- [ ] 写入前是否调用了 uidGuard()？
- [ ] 退出登录是否会触发本 Store 的 reset()？

## 实施顺序

| 阶段 | 任务 | 依赖 | 工作量 |
|------|------|------|--------|
| **1** | 创建 BaseStore 基类 | 无 | 1 个文件 ~50 行 |
| **2** | 逐个改造 8 个 Store（7 个继承 + FloatingLayerStore.clear） | 阶段 1 | 8 个文件各 ~10-30 行 |
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
| 退出时 FloatingLayer 有弹窗打开 | floatingLayerStore.clear() 清空弹窗栈，不残留 |

## 不做的范围

- 不改造 NgaClient 的 HTTP 请求取消机制（工程量过大，风险高）
- 不改动 PreferencesStore 的 flush 机制
- 不引入第三方依赖注入框架（ArkTS 约束 + 项目规模不必要）
- FloatingLayerStore 不继承 BaseStore（无 init/auth/writeQueue 需求）
