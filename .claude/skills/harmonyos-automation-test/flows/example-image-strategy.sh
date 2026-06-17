#!/usr/bin/env bash
# example-image-strategy.sh — 图片加载策略回归范例
# 验证（Avatar fix）：有自定义头像的用户，主动模式=头像 Image / 被动模式=首字母 Text（Image 数变 0）
#
# 前提（§0 门禁）：需"有自定义头像的用户"样本——本项目"网事杂谈"板块"iOS客户端闪退问题"帖
#   置顶且作者 gerraerd 有自定义头像，属稳定可得；若线上变化（帖被删/作者换头像）需重新确认。
#
# 布局（Huawei_TripleFold 全展开 3184×2232，3 列）：
#   左列=社区侧栏（板块列表 + 头像入口 (259,204)）
#   中列=活动/设置面板（设置面板在此打开）
#   右列=主题详情（打开后常驻，设置切换时 Avatar 重渲染——对照实验同页同样本）
#
# 坐标来源（dumpLayout 实测）：
#   头像入口(259,204)、图片加载模式 ActionSheet 选项：始终加载(1592,918) / 手动加载(1592,1069)
#   头像 Image 区 x≈1631-1723，故 region=1600,280,1730,2232 覆盖 4 个楼层作者头像、排除内容图
set -uo pipefail
SK="$(cd "$(dirname "$0")/.." && pwd)"
NODE="/c/Program Files/Huawei/DevEco Studio/tools/node/node.exe"
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
# 注意：不在此 export MSYS_NO_PATHCONV——它会破坏 Node 解析 /c/... 形式的 SK 路径
# （Node 把 /c/Users/... 误解析为 C:\c\Users\...）。
# lib 内部已自行处理：tap.js/assert.js 设置 process.env.MSYS_NO_PATHCONV；dump.sh 内部 export。
# 此处仅对裸 hdc 命令在调用点临时设置。
WORK="$(mktemp -d)"; cd "$WORK"
BUNDLE=com.example.nga_oh; ABILITY=EntryAbility
REGION=1600,280,1730,2232   # 右列头像区（4 楼作者）

# 进入设置面板（中列）：头像 → 设置行。假设当前已在主页且右列无主题。
open_settings() {
  "$NODE" "$SK/lib/tap.js" --xy 259 204 >/dev/null; sleep 3   # 左列头像入口 → ProfilePanel
  "$SK/lib/dump.sh"
  "$NODE" "$SK/lib/tap.js" 设置 >/dev/null; sleep 3           # ProfilePanel "设置" 行 → SettingsPanel
  "$SK/lib/dump.sh"
  "$NODE" "$SK/lib/parse.js" find 图片加载模式 >/dev/null || { echo "FAIL: 未到设置面板"; exit 2; }
}

# 切图片加载策略：$1=active|passive
set_strategy() {
  "$NODE" "$SK/lib/tap.js" 图片加载模式 >/dev/null; sleep 2   # 打开 ActionSheet
  if [ "$1" = "active" ]; then
    "$NODE" "$SK/lib/tap.js" --xy 1592 918 >/dev/null          # 始终加载（主动式）
  else
    "$NODE" "$SK/lib/tap.js" --xy 1592 1069 >/dev/null         # 手动加载（被动式）
  fi
  sleep 3                                                       # 等 Avatar 重渲染
  "$SK/lib/dump.sh"
}

avatar_images() {
  "$NODE" "$SK/lib/parse.js" count Image --region="$REGION"
}

# --- setup ---
"$SK/lib/device.sh" wait-ready
"$SK/lib/device.sh" start-app "$BUNDLE" "$ABILITY" >/dev/null
sleep 5
"$SK/lib/dump.sh"
"$NODE" "$SK/lib/parse.js" find 网事杂谈 >/dev/null || { echo "FAIL: 未到主页"; exit 2; }

# 打开主题到右列（先开主题，再切设置——右列主题常驻，设置切换触发 Avatar 重渲染）
"$NODE" "$SK/lib/tap.js" 网事杂谈 >/dev/null; sleep 4
"$SK/lib/dump.sh"
"$NODE" "$SK/lib/tap.js" iOS客户端闪退 >/dev/null; sleep 5   # 进入置顶帖（作者 gerraerd 有头像）
"$SK/lib/dump.sh"
"$NODE" "$SK/lib/parse.js" find 楼主 >/dev/null || { echo "FAIL: 未到主题详情"; exit 2; }

# --- 基线：切主动（始终加载）---
open_settings
set_strategy active
ACTIVE=$(avatar_images)

# --- action：切被动（手动加载）---
set_strategy passive
PASSIVE=$(avatar_images)

echo "active avatar images=$ACTIVE  passive=$PASSIVE"
[ "$ACTIVE" -gt 0 ] || { echo "FAIL: 主动模式无头像Image(样本无avatar?)"; exit 1; }
[ "$PASSIVE" -eq 0 ] || { echo "FAIL: 被动模式仍有头像Image($PASSIVE)，应为首字母"; exit 1; }

# --- teardown：切回主动（始终加载）---
set_strategy active
echo "PASS: 主动=$ACTIVE Image / 被动=$PASSIVE Image（首字母）"
exit 0
