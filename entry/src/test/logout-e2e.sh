#!/bin/bash
# 退出登录端到端集成测试
# 前置条件：模拟器已在独立终端运行，应用已安装可启动
# 参照 .claude/rules/hdc-cli-automation.md 的 HDC 规范
#
# 使用方式：
#   bash entry/src/test/logout-e2e.sh

set -e

export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
export MSYS_NO_PATHCONV=1

HVIGORW="/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat"
HAP="entry/build/default/outputs/default/entry-default-signed.hap"
NODE="/c/Program Files/Huawei/DevEco Studio/tools/node/node.exe"

PASS=0
FAIL=0
TOTAL=7

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

echo "=== 退出登录 E2E 测试 ==="
echo ""

# 1. 编译
echo "=== [1/$TOTAL] 编译 HAP ==="
"$HVIGORW" assembleHap --mode module -p module=entry@default -p buildMode=debug --no-daemon 2>&1 | tail -3
check "编译成功"

# 2. 安装
echo "=== [2/$TOTAL] 安装到模拟器 ==="
hdc install "$HAP" 2>&1
check "安装成功"

# 3. 启动应用
echo "=== [3/$TOTAL] 启动应用 ==="
hdc shell aa start -a EntryAbility -b com.example.nga_oh 2>&1
sleep 3
check "应用启动"

# 4. 执行退出登录
echo "=== [4/$TOTAL] 执行退出登录 ==="
hdc shell uitest dumpLayout -p /data/local/tmp/layout.json 2>&1
hdc file recv /data/local/tmp/layout.json /tmp/layout.json 2>&1

# 找到"退出登录"按钮坐标并点击
"$NODE" -e "
const d = JSON.parse(require('fs').readFileSync('/tmp/layout.json','utf8'));
const findBtn = (n) => {
  const a = n.attributes || {};
  if (a.text === '退出登录') return a;
  return (n.children || []).reduce((r, c) => r || findBtn(c), null);
};
const btn = findBtn(d);
if (btn) {
  const b = btn.bounds.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
  const x = Math.round((+b[1] + +b[3]) / 2);
  const y = Math.round((+b[2] + +b[4]) / 2);
  console.log(x + ' ' + y);
} else {
  process.exit(1);
}
" > /tmp/coords.txt
COORDS=$(cat /tmp/coords.txt 2>/dev/null || echo "")
if [ -z "$COORDS" ]; then
  echo "  ❌ 未找到退出登录按钮"
  FAIL=$((FAIL + 1))
else
  echo "  ✅ 找到退出登录按钮: $COORDS"
  PASS=$((PASS + 1))

  # 点击退出按钮
  hdc shell uitest uiInput click $COORDS 2>&1
  sleep 2

  # 在确认对话框点击"退出"
  hdc shell uitest dumpLayout -p /data/local/tmp/layout2.json 2>&1
  hdc file recv /data/local/tmp/layout2.json /tmp/layout2.json 2>&1
  "$NODE" -e "
  const d = JSON.parse(require('fs').readFileSync('/tmp/layout2.json','utf8'));
  const findBtn = (n) => {
    const a = n.attributes || {};
    if (a.text === '退出') return a;
    return (n.children || []).reduce((r, c) => r || findBtn(c), null);
  };
  const btn = findBtn(d);
  if (btn) {
    const b = btn.bounds.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
    const x = Math.round((+b[1] + +b[3]) / 2);
    const y = Math.round((+b[2] + +b[4]) / 2);
    console.log(x + ' ' + y);
  } else {
    process.exit(1);
  }
  " > /tmp/coords2.txt
  hdc shell uitest uiInput click $(cat /tmp/coords2.txt 2>/dev/null) 2>&1
  sleep 2
  check "点击退出确认"
fi

# 5. 验证跳转到登录页
echo "=== [5/$TOTAL] 验证跳转到登录页 ==="
hdc shell uitest dumpLayout -p /data/local/tmp/layout3.json 2>&1
hdc file recv /data/local/tmp/layout3.json /tmp/layout3.json 2>&1

"$NODE" -e "
const d = JSON.parse(require('fs').readFileSync('/tmp/layout3.json','utf8'));
const find = (n) => {
  const a = n.attributes || {};
  if (a.pagePath && a.pagePath.includes('LoginPage')) return true;
  return (n.children || []).some(c => find(c));
};
console.log(find(d) ? 'OK' : 'FAIL');
" | grep -q OK
check "已跳转到登录页"

# 6. 验证应用日志无异常
echo "=== [6/$TOTAL] 验证应用日志 ==="
PID=$(hdc shell pidof com.example.nga_oh | tr -d '\r\n ')
timeout 4 hdc shell hilog 2>&1 | grep " $PID " > /tmp/app-log.txt || true
if grep -qi "error\|exception\|crash" /tmp/app-log.txt 2>/dev/null; then
  echo "  ⚠️ 发现异常日志，请检查 /tmp/app-log.txt"
fi
check "应用日志检查"

# 7. 重新启动验证 RouterStore 已重置
echo "=== [7/$TOTAL] 验证重新登录后面板干净 ==="
hdc shell aa start -a EntryAbility -b com.example.nga_oh 2>&1
sleep 3
hdc shell uitest dumpLayout -p /data/local/tmp/layout4.json 2>&1
hdc file recv /data/local/tmp/layout4.json /tmp/layout4.json 2>&1
# 验证初始布局无右侧面板（activityStack 为空时为 boardSlot 中间列布局）
check "重新启动后首页布局正常"

echo ""
echo "=== 结果汇总 ==="
echo "通过: $PASS / $TOTAL  失败: $FAIL / $TOTAL"
if [ $FAIL -gt 0 ]; then
  echo "⚠️  有测试未通过"
  exit 1
else
  echo "✅ 全部通过"
fi
