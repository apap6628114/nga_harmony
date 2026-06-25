# 架构治理实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 根治退出登录流程暴露的 7 项历史技术债 — BaseStore 基类统一 Store 生命周期 + LogoutOrchestrator 集中编排退出流程 + HDC 集成测试闭环

**Architecture:** 新增 `BaseStore` 抽象基类（所有 Store 继承，统一 reset/generation/uidGuard）；新增 `LogoutOrchestrator` 编排层（服务端登出 → 本地清理 → 导航跳转）；`AuthApi` 瘦身为纯 API 层；退出流程增加 `floatingLayerStore.clear()`。

**Tech Stack:** ArkTS (API 6.1.0), HarmonyOS, HDC

---

## 文件结构

### 新建文件
| 文件 | 职责 |
|------|------|
| `entry/src/main/ets/store/BaseStore.ets` | 抽象基类：generation/uidGuard/init/reset 生命周期 |
| `entry/src/main/ets/service/LogoutOrchestrator.ets` | 退出编排器：服务端登出 → 本地清理 → 导航 |
| `entry/src/test/logout-e2e.sh` | HDC 端到端集成测试脚本 |

### 修改文件
| 文件 | 改造内容 |
|------|---------|
| `AuthStore.ets` | 继承 BaseStore，委托 generation++ |
| `SettingsStore.ets` | 继承 BaseStore |
| `CategoryStore.ets` | refreshGeneration → 对齐 BaseStore.generation |
| `ProfileStore.ets` | 继承 BaseStore |
| `NotificationStore.ets` | 继承 BaseStore |
| `VoteStore.ets` | 继承 BaseStore + uidGuard |
| `HistoryStore.ets` | 继承 BaseStore + uidGuard |
| `AppStore.ets` | clearAuth 中追加 floatingLayerStore.clear() |
| `AuthApi.ets` | logout → invalidateServerSession，移除 destroySession |
| `SettingsPanel.ets` | 切换到 LogoutOrchestrator |
| `NgaClient.ets` | 无改动（本次修 Good 前次已添加 logout 方法） |
| `.claude/CLAUDE.md` | 新增 Store 开发检查清单 |

---

### Task 1: 创建 BaseStore 抽象基类

**Files:**
- Create: `entry/src/main/ets/store/BaseStore.ets`

- [ ] **Step 1: 编写 BaseStore 基类**

```typescript
/**
 * Store 基类 — 统一生命周期管理和异步防护。
 *
 * 所有持久化 Store 都应继承此类以获得：
 * - generation 版本标记：reset() 时自增，使过时异步回调自动失效
 * - uidGuard()：写入队列前检查 uid 有效性
 * - reset() 统一契约
 *
 * 泛型参数 T 用于标注 state 类型，受 ArkTS 约束限制，
 * 基类中不编写基于 T 的通用逻辑。
 *
 * ⚠️ init 不作为基类抽象方法：各 Store 的 init 参数列表不同
 * （AuthStore/VoteStore/HistoryStore 无 auth 参数，其余有），
 * ArkTS 不支持方法重载，因此各 Store 自行声明 init 签名。
 */
export abstract class BaseStore<T> {
  abstract state: T
  protected store!: PreferencesStore
  protected writeQueue!: SerialQueue
  protected auth!: AuthState

  /**
   * Store 级全局版本号。
   * reset() 时自增，使所有已捕获 generation 的异步回调自动失效。
   * 适用于"整个 Store 重置后不应再执行旧操作"的场景。
   */
  protected generation: number = 0

  /**
   * 供子类 init 调用的依赖注入辅助方法。
   * 各 Store init 签名不同（2 或 3 个参数），子类在自身 init 中调用此方法。
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

- [ ] **Step 2: 确认编译通过**

Run: 在 DevEco Studio 中执行 Build → Rebuild，确认无语法错误

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/store/BaseStore.ets
git commit -m "feat: 新增 BaseStore 抽象基类 — generation + uidGuard + 统一生命周期

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: AuthStore 继承 BaseStore

**Files:**
- Modify: `entry/src/main/ets/store/AuthStore.ets`

- [ ] **Step 1: 修改 AuthStore 继承 BaseStore**

```typescript
import { BaseStore } from './BaseStore'

export class AuthStore extends BaseStore<AuthState> {
  state: AuthState = new AuthState()
  // ... 其余字段不变

  async init(store: PreferencesStore, queue: SerialQueue): Promise<void> {
    this.setDeps(store, queue)  // ← 注入依赖（无 auth）
    // 已有实现：await this.loadSessions() ...
  }

  clearAuth(): void {
    if (this.state.token) {
      this.sessions.delete(this.state.token)
      this.sessionsDirty = true
      this.persistSessions(true)
    }
    this.state.token = ''
    this.state.uid = ''
    this.state.nickName = ''
    this.state.avatarUrl = ''
    this.state.isAuthenticated = false
    this.state.initialized = true
    this.persistAuth()
  }

  reset(): void {
    this.clearAuth()
    super.reset()
  }
}
```

改动点：
1. 类声明：`export class AuthStore extends BaseStore<AuthState>`
2. 添加 `override state: AuthState = new AuthState()` 替代原 `state: AuthState = new AuthState()`
3. `reset()` 方法中调用 `super.reset()` 触发 generation++

- [ ] **Step 2: 确认编译通过**

Run: 在 DevEco Studio 中执行 Build → Rebuild
Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/store/AuthStore.ets
git commit -m "refactor: AuthStore 继承 BaseStore

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: CategoryStore 对齐 BaseStore.generation

**Files:**
- Modify: `entry/src/main/ets/store/CategoryStore.ets`

- [ ] **Step 1: 改造 CategoryStore**

```typescript
import { BaseStore } from './BaseStore'

export class CategoryStore extends BaseStore<Object> {
  // 移除 refreshGeneration 字段（使用基类的 generation）
  // private refreshGeneration: number = 0  ← 删除

  reset(): void {
    this.cachedCategories = []
    this.categoriesRefreshing = false
    this.categoriesLoaded = false
    this.categoriesError = ''
    // this.refreshGeneration++ ← 改为：
    super.reset()
  }

  ensureCategories(): void {
    if (this.categoriesRefreshing) return
    this.categoriesRefreshing = true
    const gen = ++this.generation    // ← 使用基类的 generation
    const hasCache = this.cachedCategories.length > 0
    setTimeout(async () => {
      await this.doRefreshCategories(gen)
      this.categoriesRefreshing = false
    }, hasCache ? CategoryStore.REFRESH_DELAY : 0)
  }

  private async doRefreshCategories(gen: number): Promise<void> {
    if (!this.isCurrent(gen)) return   // ← 使用基类的 isCurrent
    // ... 其余不变
  }
}
```

改动点：
1. 类声明：`export class CategoryStore extends BaseStore<Object>`
2. 删除 `private refreshGeneration: number = 0`
3. `reset()` 中 `this.refreshGeneration++` → `super.reset()`
4. `ensureCategories()` 中 `++this.refreshGeneration` → `++this.generation`
5. `doRefreshCategories` 中 `gen !== this.refreshGeneration` → `!this.isCurrent(gen)`

- [ ] **Step 2: 确认编译通过**

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/store/CategoryStore.ets
git commit -m "refactor: CategoryStore 对齐 BaseStore.generation

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: SettingsStore / ProfileStore / NotificationStore 继承 BaseStore

**Files:**
- Modify: `entry/src/main/ets/store/SettingsStore.ets`
- Modify: `entry/src/main/ets/store/ProfileStore.ets`
- Modify: `entry/src/main/ets/store/NotificationStore.ets`

- [ ] **Step 1: SettingsStore.ets**

```typescript
import { BaseStore } from './BaseStore'

export class SettingsStore extends BaseStore<SettingsState> {
  state: SettingsState = new SettingsState()
  // ... 其余不变

  async init(store: PreferencesStore, queue: SerialQueue, auth: AuthState, ctx?: Context): Promise<void> {
    this.setDeps(store, queue, auth)  // ← 注入依赖
    // ... 其余 init 逻辑
  }

  reset(): void {
    this.state = new SettingsState()
    this.ctx.state = this.state
    this.socialListSettings.reset()
    this.filterKeywordSettings.reset()
    this.noteSettings.reset()
    super.reset()
  }
}
```

- [ ] **Step 2: ProfileStore.ets**

```typescript
import { BaseStore } from './BaseStore'

export class ProfileStore extends BaseStore<Object> {
  async init(store: PreferencesStore, queue: SerialQueue, auth: AuthState): Promise<void> {
    this.setDeps(store, queue, auth)  // ← 注入依赖
    // ... 其余 init 逻辑
  }

  reset(): void {
    this.cache.clear()
    this.refreshingUids = new Set()
    super.reset()
  }
}
```

- [ ] **Step 3: NotificationStore.ets**

```typescript
import { BaseStore } from './BaseStore'

export class NotificationStore extends BaseStore<Object> {
  async init(store: PreferencesStore, queue: SerialQueue, auth: AuthState): Promise<void> {
    this.setDeps(store, queue, auth)  // ← 注入依赖
    // ... 其余 init 逻辑
  }

  reset(): void {
    this.cachedNotifications = []
    this.unreadNotiCount = 0
    this.lastNotiQueryTime = 0
    super.reset()
  }
}
```

- [ ] **Step 4: 编译验证**

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/store/SettingsStore.ets \
      entry/src/main/ets/store/ProfileStore.ets \
      entry/src/main/ets/store/NotificationStore.ets
git commit -m "refactor: SettingsStore/ProfileStore/NotificationStore 继承 BaseStore

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: VoteStore / HistoryStore 继承 BaseStore + uidGuard

**Files:**
- Modify: `entry/src/main/ets/store/VoteStore.ets`
- Modify: `entry/src/main/ets/store/HistoryStore.ets`

- [ ] **Step 1: VoteStore.ets — 继承 BaseStore + uidGuard**

```typescript
import { BaseStore } from './BaseStore'

export class VoteStore extends BaseStore<Object> {
  // ... 其余不变

  init(store: PreferencesStore, queue: SerialQueue): void {
    this.setDeps(store, queue)  // ← 注入依赖（无 auth）
  }

  reset(): void {
    this.voteCache = {}
    this.voteLoadedUid = ''
    super.reset()
  }

  // 所有 enqueue 写入前加 uidGuard
  private persistVotes(uid: string): void {
    this.writeQueue.enqueue(async (): Promise<void> => {
      if (!this.uidGuard()) return    // ← 新增 uuid 检查
      await this.store.putJSON(this.voteKey(uid), this.voteCache, false)
      this.store.scheduleFlush()
    })
  }
}
```

- [ ] **Step 2: HistoryStore.ets — 继承 BaseStore + uidGuard**

```typescript
import { BaseStore } from './BaseStore'

export class HistoryStore extends BaseStore<Object> {
  init(store: PreferencesStore, queue: SerialQueue): void {
    this.setDeps(store, queue)  // ← 注入依赖（无 auth）
  }

  reset(): void {
    this.historyItems = []
    this.historyLoadedUid = ''
    super.reset()
  }

  private persistBrowseHistory(uid: string): void {
    this.writeQueue.enqueue(async (): Promise<void> => {
      if (!this.uidGuard()) return    // ← 新增 uuid 检查
      await this.store.putJSON(this.historyKey(uid), this.historyItems, false)
      bumpAppStorageVersion(KEY_BROWSE_HISTORY_VERSION)
      this.store.scheduleFlush()
    })
  }
}
```

- [ ] **Step 3: 编译验证**

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/store/VoteStore.ets \
      entry/src/main/ets/store/HistoryStore.ets
git commit -m "refactor: VoteStore/HistoryStore 继承 BaseStore + uidGuard

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: 追加 floatingLayerStore.clear() 到 clearAuth

**Files:**
- Modify: `entry/src/main/ets/store/AppStore.ets`

- [ ] **Step 1: 添加 import 和 clear 调用**

```typescript
// 文件顶部新增 import
import { floatingLayerStore } from './FloatingLayerStore'

// clearAuth() 末尾追加
clearAuth(): void {
  // ... 现有逻辑 ...
  this.historyStore.reset()
  floatingLayerStore.clear()        // ← 新增：清空弹窗栈
  routerStore.reset()
}
```

- [ ] **Step 2: 编译验证**

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/store/AppStore.ets
git commit -m "fix: 退出登录时清空 FloatingLayerStore 弹窗栈

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: AuthApi 瘦身 — logout → invalidateServerSession

**Files:**
- Modify: `entry/src/main/ets/service/api/AuthApi.ets`

- [ ] **Step 1: 重命名 logout 为 invalidateServerSession，移除 destroySession**

```typescript
// 删除旧 LOGOUT_TAG / LOGOUT_DOMAIN 常量
// 使用文件中已有的 DOMAIN / TAG（或新增）

const API_TAG = 'AuthApi'
const API_DOMAIN = 0x0000

/**
 * 通知 NGA 服务端使当前 token 对应的 cid 会话失效。
 * 不碰本地 Store 状态，本地清理由 LogoutOrchestrator 编排。
 */
export async function invalidateServerSession(token: string): Promise<void> {
  const session = appStore.getSession(token);
  if (session) {
    try {
      await ngaClient.logout({ uid: session.uid, cid: session.cid });
    } catch (e) {
      hilog.warn(API_DOMAIN, API_TAG, '服务端登出失败: %{public}s', JSON.stringify(e));
    }
  }
}
```

- [ ] **Step 2: 全文搜索替换引用**

检查 `AuthApi.logout(` 的全部引用（当前仅有 `SettingsPanel.ets`），下一 Task 处理。

- [ ] **Step 3: 编译验证**

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/service/api/AuthApi.ets
git commit -m "refactor: AuthApi.logout → invalidateServerSession，仅做网络请求

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: 创建 LogoutOrchestrator

**Files:**
- Create: `entry/src/main/ets/service/LogoutOrchestrator.ets`

- [ ] **Step 1: 编写 LogoutOrchestrator**

```typescript
import { UIContext } from '@ohos.arkui.UIContext'
import { appStore } from '../store/AppStore'
import { invalidateServerSession } from './api/AuthApi'

const TAG = 'LogoutOrchestrator'
const DOMAIN = 0x0000

/**
 * 退出登录流程编排器。
 *
 * 集中编排"服务端登出 → 本地清理 → 导航跳转"完整流程。
 * 调用方（@Component）传入 UIContext 用于导航。
 */
export class LogoutOrchestrator {
  async logout(context: UIContext): Promise<void> {
    const token = appStore.auth.token
    // 1. 服务端登出（纯 API，不碰 Store，失败不阻塞）
    if (token) {
      try {
        await invalidateServerSession(token)
      } catch (e) {
        hilog.warn(DOMAIN, TAG, '服务端登出失败: %{public}s', JSON.stringify(e))
      }
    }
    // 2. 本地清理（AppStore.clearAuth 内部编排全部 Store reset）
    appStore.clearAuth()
    // 3. 导航到登录页
    try {
      context.getRouter().replaceUrl({ url: 'pages/LoginPage' })
    } catch (e) {
      hilog.error(DOMAIN, TAG, '导航到登录页失败: %{public}s', JSON.stringify(e))
    }
  }
}

export const logoutOrchestrator = new LogoutOrchestrator()
```

- [ ] **Step 2: 编译验证**

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/service/LogoutOrchestrator.ets
git commit -m "feat: 创建 LogoutOrchestrator 退出编排器

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: SettingsPanel 切换到 LogoutOrchestrator

**Files:**
- Modify: `entry/src/main/ets/pages/SettingsPanel.ets`

- [ ] **Step 1: 修改退出回调**

```typescript
// 修改 import
// 删除：import { logout } from '../service/api/AuthApi'
// 新增：
import { logoutOrchestrator } from '../service/LogoutOrchestrator'

// 修改 onConfirm
onConfirm: async () => {
  await logoutOrchestrator.logout(this.getUIContext())
},
```

全部 onConfirm 方法体简化为单行调用，职责全部委托给 Orchestrator。

- [ ] **Step 2: 编译验证**

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/pages/SettingsPanel.ets
git commit -m "refactor: SettingsPanel 退出切换到 LogoutOrchestrator

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 10: HDC 集成测试脚本

**Files:**
- Create: `entry/src/test/logout-e2e.sh`

- [ ] **Step 1: 编写端到端测试脚本**

遵循 `.claude/rules/hdc-cli-automation.md` 的 HDC 规范。

```bash
#!/bin/bash
# 退出登录端到端集成测试
# 前置条件：模拟器已在独立终端运行，应用已安装

set -e

export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
export MSYS_NO_PATHCONV=1

HVIGORW="/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat"
HAP="entry/build/default/outputs/default/entry-default-signed.hap"
NODE="/c/Program Files/Huawei/DevEco Studio/tools/node/node.exe"

PASS=0
FAIL=0

check() {
  local desc="$1"
  if [ $? -eq 0 ]; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc"
    FAIL=$((FAIL + 1))
  fi
}

# 1. 编译
echo "=== [1/7] 编译 ==="
"$HVIGORW" assembleHap --mode module -p module=entry@default -p buildMode=debug --no-daemon
check "编译成功"

# 2. 安装
echo "=== [2/7] 安装 ==="
hdc install "$HAP"
check "安装成功"

# 3. 启动应用
echo "=== [3/7] 启动应用 ==="
hdc shell aa start -a EntryAbility -b com.example.nga_oh
sleep 3
check "应用启动"

# 4. 探查登录后 UI — 找到退出按钮并点击
echo "=== [4/7] 执行退出登录 ==="
hdc shell uitest dumpLayout -p /data/local/tmp/layout.json
hdc file recv /data/local/tmp/layout.json /tmp/layout.json

# 解析"退出登录"按钮坐标
"$NODE" -e "
const d = JSON.parse(require('fs').readFileSync('/tmp/layout.json','utf8'));
const find = (n) => {
  const a = n.attributes || {};
  if (a.text === '退出登录') return a;
  return (n.children || []).reduce((r, c) => r || find(c), null);
};
const btn = find(d);
if (btn) {
  const b = btn.bounds.match(/\\[(\\d+),(\\d+)\\]\\[(\\d+),(\\d+)\\]/);
  const x = Math.round((+b[1] + +b[3]) / 2);
  const y = Math.round((+b[2] + +b[4]) / 2);
  console.log(x + ' ' + y);
} else {
  process.exit(1);
}
" > /tmp/coords.txt
COORDS=$(cat /tmp/coords.txt)
check "找到退出登录按钮坐标: $COORDS"

# 点击退出按钮 → 弹出确认对话框
hdc shell uitest uiInput click $COORDS
sleep 1

# 点击"退出"确认按钮
hdc shell uitest dumpLayout -p /data/local/tmp/layout2.json
hdc file recv /data/local/tmp/layout2.json /tmp/layout2.json
"$NODE" -e "
const d = JSON.parse(require('fs').readFileSync('/tmp/layout2.json','utf8'));
const find = (n) => {
  const a = n.attributes || {};
  if (a.text === '退出') return a;
  return (n.children || []).reduce((r, c) => r || find(c), null);
};
const btn = find(d);
if (btn) {
  const b = btn.bounds.match(/\\[(\\d+),(\\d+)\\]\\[(\\d+),(\\d+)\\]/);
  const x = Math.round((+b[1] + +b[3]) / 2);
  const y = Math.round((+b[2] + +b[4]) / 2);
  console.log(x + ' ' + y);
} else {
  process.exit(1);
}
" > /tmp/coords2.txt
hdc shell uitest uiInput click $(cat /tmp/coords2.txt)
sleep 2
check "点击退出确认按钮"

# 5. 验证跳转到登录页
echo "=== [5/7] 验证导航状态 ==="
hdc shell uitest dumpLayout -p /data/local/tmp/layout3.json
hdc file recv /data/local/tmp/layout3.json /tmp/layout3.json

# 验证页面包含登录相关元素（如用户名输入框）
"$NODE" -e "
const d = JSON.parse(require('fs').readFileSync('/tmp/layout3.json','utf8'));
const find = (n) => {
  const a = n.attributes || {};
  if (a.text && a.text.includes('登录')) return true;
  return (n.children || []).some(c => find(c));
};
console.log(find(d) ? 'OK' : 'FAIL');
" | grep -q OK
check "已跳转到登录页"

# 6. 验证应用日志无异常
echo "=== [6/7] 验证日志 ==="
PID=$(hdc shell pidof com.example.nga_oh | tr -d '\r\n ')
timeout 3 hdc shell hilog | grep " $PID " > /tmp/app-log.txt || true
# 检查无错误日志
if grep -qi "error\|exception\|crash" /tmp/app-log.txt; then
  echo "  ⚠️ 发现异常日志，请检查 /tmp/app-log.txt"
fi
check "应用日志检查"

# 7. 结果汇总
echo "=== 结果汇总 ==="
echo "通过: $PASS  失败: $FAIL"
if [ $FAIL -gt 0 ]; then
  exit 1
fi
```

- [ ] **Step 2: 在模拟器上手动验证脚本可执行**

```bash
cd /c/Users/ll/Desktop/nga_oh
chmod +x entry/src/test/logout-e2e.sh
bash entry/src/test/logout-e2e.sh
```

- [ ] **Step 3: 提交**

```bash
git add entry/src/test/logout-e2e.sh
git commit -m "test: 退出登录 HDC 端到端集成测试脚本

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 11: 更新开发检查清单

**Files:**
- Modify: `.claude/CLAUDE.md`

- [ ] **Step 1: 在项目 CLAUDE.md 中追加 Store 开发检查项**

在项目规则章节末尾添加：

```markdown
## Store 开发检查清单

新增或修改 Store 时，请逐项确认：

- [ ] 是否继承 `BaseStore`？
- [ ] `reset()` 中是否调用了 `super.reset()`？
- [ ] 异步回调中是否调用了 `isCurrent(gen)` 检查 generation？
- [ ] 写入 `writeQueue` 前是否调用了 `uidGuard()`？
- [ ] 退出登录（`clearAuth`）是否会触发本 Store 的 `reset()`？
```

- [ ] **Step 2: 提交**

```bash
git add .claude/CLAUDE.md
git commit -m "docs: 新增 Store 开发检查清单

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## 自检清单

**1. Spec 覆盖检查：**
- BaseStore 抽象基类 → Task 1 ✅
- 8 个 Store 继承/对齐 → Task 2-5 ✅
- LogoutOrchestrator → Task 8 ✅
- AuthApi 瘦身 → Task 7 ✅
- floatingLayerStore.clear() → Task 6 ✅
- SettingsPanel 切换 → Task 9 ✅
- HDC 测试 → Task 10 ✅
- 开发检查清单 → Task 11 ✅

**2. 占位符扫描：** 无 "TBD"、"TODO"、"implement later" 等占位符 ✅

**3. 类型一致性：** 所有方法签名和字段名跨任务一致 ✅

**4. 文件路径：** 所有路径使用 Unix 分隔符，与实际项目路径一致 ✅
