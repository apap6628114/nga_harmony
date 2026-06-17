#!/usr/bin/env node
// assert.js — 断言原语, exit 0=PASS / 1=FAIL
const { execSync } = require("child_process");
const fs = require("fs");
process.env.MSYS_NO_PATHCONV = "1";
const d = JSON.parse(fs.readFileSync("layout.json", "utf8"));
const args = process.argv.slice(2);

function walk(cb){ const st=[d]; while(st.length){ const n=st.pop(); cb(n.attributes||{}); (n.children||[]).forEach(c=>st.push(c)); } }
function parseBounds(b){ const m=String(b||"").match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/); return m?{x1:+m[1],y1:+m[2],x2:+m[3],y2:+m[4]}:null; }
function regionArg(){ const a=args.find(x=>x.startsWith("--region=")); if(!a)return null; const m=a.replace("--region=","").split(","); return {x1:+m[0],y1:+m[1],x2:+m[2],y2:+m[3]}; }
function pass(m){ console.log("PASS:",m); process.exit(0); }
function fail(m){ console.error("FAIL:",m); process.exit(1); }

const cmd = args[0];
if (cmd === "exists") {
  const sub = args[1]; let found = false;
  walk(a => { if (!found && a.text && String(a.text).includes(sub)) found = true; });
  found ? pass("exists '" + sub + "'") : fail("not found '" + sub + "'");
} else if (cmd === "count-eq") {
  const type = args[1], n = +args[2], r = regionArg(); let c = 0;
  walk(a => { if (a.type !== type) return; if (r) { const p = parseBounds(a.bounds); if (!p || p.x1 < r.x1 || p.y1 < r.y1 || p.x2 > r.x2 || p.y2 > r.y2) return; } c++; });
  c === n ? pass("count " + type + "=" + c) : fail("count " + type + "=" + c + " expected " + n);
} else if (cmd === "visible") {
  const sub = args[1], exp = args[2]; let v = "";
  walk(a => { if (v === "" && a.text && String(a.text).includes(sub)) v = a.visible; });
  v === exp ? pass("visible '" + sub + "'=" + v) : fail("visible '" + sub + "'=" + v + " expected " + exp);
} else if (cmd === "text-eq") {
  const exp = args[1]; let found = false;
  walk(a => { if (!found && a.text === exp) found = true; });
  found ? pass("text-eq '" + exp + "'") : fail("text '" + exp + "' absent");
} else if (cmd === "log-contains") {
  const pid = args[1], pat = args[2];
  let out = "";
  try { out = execSync(`timeout 3 hdc shell hilog 2>/dev/null | grep -E "${pat}" | grep " ${pid} "`, {encoding:"utf8", shell:"bash"}); } catch (e) {}
  out.trim() ? pass("log-contains '" + pat + "'") : fail("log pattern '" + pat + "' absent for pid " + pid);
} else {
  console.error("usage: assert.js exists|count-eq|visible|text-eq|log-contains ...");
  process.exit(2);
}
