#!/usr/bin/env node
// tap.js — 按 text/id/xy 定位点击（读 layout.json）
const { execSync } = require("child_process");
const fs = require("fs");
process.env.MSYS_NO_PATHCONV = "1";
const d = JSON.parse(fs.readFileSync("layout.json", "utf8"));
const args = process.argv.slice(2);

function walk(cb){ const st=[d]; while(st.length){ const n=st.pop(); cb(n.attributes||{}); (n.children||[]).forEach(c=>st.push(c)); } }
function parseBounds(b){ const m=String(b||"").match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/); return m?{x:(+m[1]+ +m[3])/2,y:(+m[2]+ +m[4])/2}:null; }
function click(x,y){ execSync(`hdc shell uitest uiInput click ${Math.round(x)} ${Math.round(y)}`, {stdio:"inherit"}); }

let target = null;
if (args[0] === "--id") {
  const id = args[1]; walk(a => { if (!target && a.id === id) target = a; });
} else if (args[0] === "--xy") {
  click(+args[1], +args[2]); process.exit(0);
} else {
  const sub = args[0]; walk(a => { if (!target && a.text && String(a.text).includes(sub)) target = a; });
}
if (!target) { console.error("tap: target not found"); process.exit(1); }
const c = parseBounds(target.bounds);
if (!c) { console.error("tap: no bounds"); process.exit(1); }
click(c.x, c.y); process.exit(0);
