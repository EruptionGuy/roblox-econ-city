// prototype, bỏ đi được: bot chơi trên lưới bằng engine.js để soát cân bằng docs/luat-choi-moi.md
// node prototypes/luat-moi/sim.js [thuế%]: in điểm cuối ván theo thuế cho từng chiến thuật,
// có thuế% thì in thêm từng tháng của chiến thuật cân bằng
"use strict";
const E = require("./engine.js");
const { CFG, B } = E;
const N = CFG.size, gx = CFG.gate % N;

// bố cục bot: 1 trục dọc ở cột cổng, đường ngang ở các hàng ROAD_ROWS, công trình đặt sát đường
const ROAD_ROWS = [N - 2, N - 5, N - 8, N - 11];
const roadRowOf = (y) => ROAD_ROWS.find((r) => Math.abs(r - y) === 1);
const SLOTS = [];
for (let y = 0; y < N; y++) {
  for (let x = 0; x < N; x++) {
    if (!ROAD_ROWS.includes(y) && !(x === gx && y >= 1)) SLOTS.push({ x, y, i: y * N + x });
  }
}
SLOTS.sort((a, b) => roadRowOf(b.y) - roadRowOf(a.y) || Math.abs(a.x - gx) - Math.abs(b.x - gx));

// ô đường còn thiếu để slot nối về cổng: trục dọc tới hàng đường của slot, rồi đoạn ngang tới cột của nó
function roadsFor(s, slot) {
  const r = roadRowOf(slot.y), out = [];
  for (let y = r; y < N; y++) out.push(y * N + gx);
  for (let x = Math.min(gx, slot.x); x <= Math.max(gx, slot.x); x++) out.push(r * N + x);
  return out.filter((i) => s.cells[i] !== "road");
}

const JOBS = ["shop", "factory", "office", "hospital", "school"];
const count = (s, t) => s.cells.filter((c) => c === t).length;

// giữ chỗ ở = việc làm x houseRatio, giữ S dự kiến (lúc đủ người) >= st.S, còn lại xây việc làm theo mix
function act(s, st) {
  for (;;) {
    const slot = SLOTS.find((p) => s.cells[p.i] === null);
    if (!slot) return;
    const C = count(s, "house") * B.house.cap;
    const J = JOBS.reduce((a, t) => a + count(s, t) * B[t].jobs, 0);
    const d = E.compute(s, Math.max(1, Math.min(C, J)));
    let pick;
    if (C < J * st.houseRatio || (C === 0 && J === 0)) pick = "house";
    else if (d.S < st.S) pick = st.service[(count(s, "hospital") + count(s, "school") + count(s, "park")) % st.service.length];
    else {
      const total = Object.keys(st.mix).reduce((a, t) => a + count(s, t) * B[t].jobs, 0) + 1;
      const gap = (t) => (count(s, t) * B[t].jobs) / total - st.mix[t];
      pick = Object.keys(st.mix).sort((a, b) => gap(a) - gap(b))[0];
    }
    const roads = roadsFor(s, slot);
    const cost = E.priceOf(s, pick) + roads.length * E.priceOf(s, "road");
    if (s.budget < cost || s.budget - cost < st.reserveMonths * d.M) return;
    if (roads.length) E.buildRoad(s, roads);
    E.build(s, pick, slot.i);
  }
}

function run(st, tax, onMonth) {
  const s = E.newGame();
  E.setTax(s, tax);
  E.togglePause(s);
  let fullAt = null;
  while (!E.finished(s)) {
    act(s, st);
    if (fullAt === null && !SLOTS.some((p) => s.cells[p.i] === null)) fullAt = s.month;
    const d = E.tick(s);
    if (onMonth) onMonth(s, d);
  }
  return { s, fullAt };
}

const base = { mix: { shop: 0.4, factory: 0.4, office: 0.2 }, S: 60, service: ["park", "hospital", "school"], houseRatio: 1.2, reserveMonths: 2 };
const STRATS = {
  "cân bằng": base,
  "chỉ văn phòng": { ...base, mix: { office: 1 } },
  "shop + nhà máy": { ...base, mix: { shop: 0.5, factory: 0.5 } },
  "chỉ shop (không nhà máy)": { ...base, mix: { shop: 1 } },
  "chỉ nhà máy": { ...base, mix: { factory: 1 } },
  "không dịch vụ công": { ...base, S: 0 },
  "dịch vụ cao (S ≥ 90)": { ...base, S: 90 },
  "chỉ công viên": { ...base, service: ["park"] },
  "chỉ bệnh viện": { ...base, service: ["hospital"] },
  "thừa nhà (×2)": { ...base, houseRatio: 2 },
  "thiếu nhà (×0,7)": { ...base, houseRatio: 0.7 },
  "liều (không dự trữ)": { ...base, reserveMonths: 0 },
};

module.exports = { STRATS, run, SLOTS };
if (require.main !== module) return;

const TAXES = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50];
const pad = (x, n) => String(x).padStart(n);
console.log(`Bố cục bot: ${SLOTS.length} ô công trình, ${N * N - SLOTS.length} ô đường (kể cả cổng)`);
console.log("Điểm cuối ván theo thuế (F<tháng> = phá sản):");
console.log(pad("", 28) + TAXES.map((t) => pad(t + "%", 6)).join(""));
for (const [name, st] of Object.entries(STRATS)) {
  const row = TAXES.map((t) => {
    const { s } = run(st, t);
    return pad(s.status === "FAILED" ? "F" + s.month : s.score, 6);
  });
  console.log(name.padEnd(28) + row.join(""));
}

if (process.argv[2]) {
  const tax = Number(process.argv[2]);
  console.log(`\nChi tiết chiến thuật cân bằng, thuế ${tax}%`);
  const { fullAt } = run(base, tax, (s, d) =>
    console.log(`T${pad(s.month, 2)} ngân sách ${pad(Math.round(s.budget), 7)} dân ${pad(s.pop, 5)} chỗ ở ${pad(d.C, 5)} việc ${pad(d.J, 5)} E ${pad(Math.round(d.E), 3)} S ${pad(Math.round(d.S), 3)} H ${pad(Math.round(d.H), 3)} DT ${pad(Math.round(d.R), 6)} bảo trì ${pad(d.M, 5)} điểm ${s.score}`));
  console.log(fullAt === null ? "Lưới chưa đầy khi hết ván" : `Lưới đầy trước lượt tính tháng ${fullAt + 1}`);
}
