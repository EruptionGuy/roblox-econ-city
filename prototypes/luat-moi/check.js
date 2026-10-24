// test engine.js theo docs/luat-choi-moi.md. chạy: node prototypes/luat-moi/check.js
"use strict";
const assert = require("node:assert/strict");
const E = require("./engine.js");
const N = E.CFG.size, gate = E.CFG.gate;
const at = (x, y) => y * N + x; // 0-based
const near = (a, b, msg) => assert.ok(Math.abs(a - b) < 1e-9, `${msg}: ${a} ≠ ${b}`);

// Ván mới: $10.000, thuế 20%, tạm dừng, H = 35 + 27 + 20 = 82
let s = E.newGame();
assert.equal(s.budget, 10000);
assert.equal(s.status, "PAUSED");
assert.equal(s.cells[gate], "road");
near(s.H, 82, "H ban đầu");

// nối đường: nhà kề cổng là nối, nhà xa thì không nhưng vẫn tốn bảo trì
const gx = gate % N, gy = Math.floor(gate / N);
E.build(s, "house", at(gx - 1, gy));
E.build(s, "house", at(0, 0));
let d = E.compute(s, 0);
assert.equal(d.C, 40, "chỉ nhà đã nối mới có chỗ ở");
assert.equal(d.M, 20, "nhà chưa nối vẫn tốn bảo trì");
assert.equal(E.buildRoad(s, [at(gx, gy - 1), at(gx, gy - 2)]).ok, true);
assert.equal(E.build(s, "office", at(gx + 1, gy - 2)).ok, true);
assert.equal(E.compute(s, 0).J, 20, "văn phòng cạnh đường nối về cổng");

// kéo đường qua công trình thì từ chối cả đoạn, không trừ tiền
const before = s.budget;
assert.equal(E.buildRoad(s, [at(gx - 2, gy), at(gx - 1, gy)]).ok, false);
assert.equal(s.budget, before);
assert.equal(s.cells[at(gx - 2, gy)], null);

// Phá dỡ hoàn 50%, không phá được cổng
assert.equal(E.demolish(s, at(0, 0)).refund, 300);
assert.equal(E.demolish(s, gate).ok, false);

// hàng hoá: không có nhà máy thì shop không bán được gì
s = E.newGame();
s.budget = 1e6;
E.buildRoad(s, [at(gx, gy - 1), at(gx, gy - 2), at(gx, gy - 3)]);
E.build(s, "shop", at(gx - 1, gy - 1));
d = E.compute(s, 20);
assert.equal(d.G, 0);
assert.equal(d.R, 0);
E.build(s, "factory", at(gx + 1, gy - 1)); // 30 chỗ nhà máy >= 20 chỗ shop
d = E.compute(s, 50);
assert.equal(d.G, 1);
near(d.R, 20 * 105 + 30 * 55, "doanh thu đủ người làm, đủ hàng");

// công thức H: E = 100, S = 100 (1 công viên đủ cho 100 người), thuế 30%: 35 + 18 + 20 = 73
s = E.newGame();
s.budget = 1e6;
E.buildRoad(s, [at(gx, gy - 1)]);
E.build(s, "house", at(gx - 1, gy));
E.build(s, "office", at(gx + 1, gy));
E.build(s, "office", at(gx - 1, gy - 1));
E.build(s, "park", at(gx + 1, gy - 1));
E.setTax(s, 30);
d = E.compute(s, 40);
near(d.E, 100, "E");
near(d.S, 100, "S");
near(d.H, 73, "H");
// ví dụ Laffer trong docs: A(68) = 0,864, A(59) = 0,432
near(E.attraction(68), 0.864, "A(68)");
near(E.attraction(59), 0.432, "A(59)");

// dân tiến dần tới min(C, floor(J*A)) rồi đứng yên
E.togglePause(s);
for (let m = 0; m < 10; m++) E.tick(s);
d = E.compute(s, s.pop);
assert.equal(s.pop, E.targetPop(d.C, d.J, s.H), "dân đứng yên ở mục tiêu");
assert.ok(s.pop > 0 && s.pop <= 40);

// hết 24 tháng là thắng, ngân sách < -$5.000 là thua
for (let m = s.month; m < 24; m++) E.tick(s);
assert.equal(s.status, "ENDED");
assert.equal(E.build(s, "house", at(0, 0)).ok, false, "không xây sau khi hết ván");
s = E.newGame();
for (let k = 0; k < 5; k++) assert.equal(E.build(s, "park", at(k, 0)).ok, true); // chưa nối: chỉ tốn $500/tháng
E.togglePause(s);
while (!E.finished(s)) E.tick(s);
assert.equal(s.status, "FAILED");

// bão giá: giá xây x1,5, hết sau 5 tháng
s = E.newGame();
E.addScenario(s, "prices");
assert.equal(E.priceOf(s, "house"), 900);
assert.equal(E.addScenario(s, "prices").ok, false);
E.togglePause(s);
for (let m = 0; m < 5; m++) E.tick(s);
assert.equal(s.scenarios.length, 0);
assert.equal(E.priceOf(s, "house"), 600);

console.log("check.js: tất cả kiểm tra đều đạt");
