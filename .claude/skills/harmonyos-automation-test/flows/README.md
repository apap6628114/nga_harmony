# 特化测试套件编写规则

每个 feature 测试是一个 shell 脚本，遵循四阶段：

| 阶段 | 职责 |
|---|---|
| setup | 导航到测试页面 + 选样本。必须 `dump.sh` 后 `parse.js find` 确认到达目标页 |
| action | 触发被测行为（切模式 / 输入 / 等待） |
| assert | 调 `lib/assert.js` 比对预定义 expected。禁止肉眼断言 |
| teardown | 恢复状态（如切回默认模式） |

## 硬性规则

1. setup 必须 dump + parse find 确认到达目标页（防盲测）。
2. 样本必须满足"能体现被测行为"的数据条件；不满足先走 SKILL.md §0 门禁咨询用户。
3. assert 只用 `lib/assert.js` 原语；expected 在脚本内写死。
4. 验证状态切换：同页同样本，action 前后两次断言（对照实验）。

## 模板

```bash
#!/usr/bin/env bash
set -uo pipefail
SK="$(cd "$(dirname "$0")/.." && pwd)"   # skill 根
NODE="/c/Program Files/Huawei/DevEco Studio/tools/node/node.exe"
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
cd "$(mktemp -d)"                         # 隔离工作目录放 layout.json/截图
# 注意：不要 `export MSYS_NO_PATHCONV=1`——它会破坏 Node 解析 /c/... 形式的 SK 路径
# （Node 把 /c/Users/... 误解析为 C:\c\Users\...）。lib 内部已自行处理 MSYS_NO_PATHCONV
# （tap.js/assert.js 设 process.env；dump.sh 内部 export）。脚本中裸 hdc 调用在调用点
# 临时设置即可，如：MSYS_NO_PATHCONV=1 hdc shell uitest uiInput keyEvent Back

# setup
"$SK/lib/device.sh" wait-ready
"$SK/lib/dump.sh"
"$NODE" "$SK/lib/parse.js" find <确认文本> >/dev/null || { echo "未到达目标页"; exit 2; }

# action
...

# assert
"$NODE" "$SK/lib/assert.js" <断言> || exit 1

# teardown
...
```

运行：`bash <skill>/flows/<feature>-test.sh`，exit 0=通过。
