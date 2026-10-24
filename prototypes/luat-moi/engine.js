/* Prototype luật xây thành phố, bỏ đi được, game thật không dùng.
 * Luật ở docs/luat-choi-moi.md, số trong ngoặc là số mục.
 * Hàm thuần, không đụng DOM. index.html, sim.js, check.js gọi vào đây.
 */
(function (root) {
  "use strict";

  const CFG = {
    size: 12, months: 24, tickSeconds: 20, startBudget: 10000, failBudget: -5000,
    startTax: 20, taxMax: 50, refund: 0.5, maxRoadPath: 24,
    wE: 0.35, wT: 0.45, wS: 0.2, // H = 0.35E + 0.45(100 - 2T) + 0.20S
    hLo: 50, hHi: 75, aMax: 1.2, moveRate: 0.5, residentsPerPoint: 20,
  };
  CFG.gate = (CFG.size - 1) * CFG.size + 5; // ô cổng: cột 6, hàng 12 (đếm từ 1)

  // (3) Công trình
  const B = {
    house:    { label: "Nhà",        icon: "🏠", price: 600,  maint: 10,  cap: 40 },
    shop:     { label: "Shop",       icon: "🏪", price: 1600, maint: 60,  jobs: 20, rev: 105 },
    factory:  { label: "Nhà máy",    icon: "🏭", price: 1200, maint: 80,  jobs: 30, rev: 55 },
    office:   { label: "Văn phòng",  icon: "🏢", price: 3000, maint: 100, jobs: 20, rev: 160 },
    hospital: { label: "Bệnh viện",  icon: "🏥", price: 2400, maint: 120, jobs: 20, pts: 10 },
    school:   { label: "Trường học", icon: "🏫", price: 2000, maint: 100, jobs: 20, pts: 10 },
    park:     { label: "Công viên",  icon: "🌳", price: 1800, maint: 100, pts: 5 },
    road:     { label: "Đường",      icon: "",   price: 50,   maint: 0 },
  };

  // (8) sự kiện giáo viên gán
  const EFFECT_RULES = {
    revenueMult: ["product", 1], maintMult: ["product", 1], priceMult: ["product", 1],
    goodsMult: ["product", 1], happyPenalty: ["sum", 0], leaveRate: ["max", 0],
  };
  const SCENARIOS = [
    { id: "recession", name: "Suy thoái kinh tế", months: 4, effects: { revenueMult: 0.7 }, note: "doanh thu × 0,7" },
    { id: "supply", name: "Đứt gãy chuỗi cung ứng", months: 4, effects: { goodsMult: 0.5 }, note: "hàng hoá × 0,5" },
    { id: "pandemic", name: "Đại dịch", months: 6, effects: { leaveRate: 0.02, happyPenalty: -10 }, note: "dân bỏ đi 2%/tháng, hạnh phúc -10" },
    { id: "prices", name: "Bão giá vật liệu", months: 5, effects: { priceMult: 1.5, maintMult: 1.3 }, note: "giá xây × 1,5, bảo trì × 1,3" },
  ];
  const scenarioById = (id) => SCENARIOS.find((s) => s.id === id);

  // (7) Cảnh báo
  const CRISIS_LABELS = {
    BUDGET: "Ngân sách âm: đang lỗ, không xây được",
    HAPPINESS: "Hạnh phúc dưới 50: không ai muốn chuyển đến",
    UNEMPLOYMENT: "Việc làm dưới 80%: thiếu việc",
    SHORTAGE: "Shop thiếu hàng: cần thêm nhà máy",
  };

  const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
  const fail = (err) => ({ ok: false, err });
  const finished = (s) => s.status === "ENDED" || s.status === "FAILED";
  const validCell = (i) => Number.isInteger(i) && i >= 0 && i < CFG.size * CFG.size;

  function aggregate(active) {
    const out = {};
    for (const k in EFFECT_RULES) out[k] = EFFECT_RULES[k][1];
    for (const a of active) {
      const effects = scenarioById(a.id).effects;
      for (const k in effects) {
        const rule = EFFECT_RULES[k][0], v = effects[k];
        out[k] = rule === "product" ? out[k] * v : rule === "sum" ? out[k] + v : Math.max(out[k], v);
      }
    }
    return out;
  }

  function neighbours(i) {
    const n = CFG.size, x = i % n, out = [];
    if (i >= n) out.push(i - n);
    if (i < n * (n - 1)) out.push(i + n);
    if (x > 0) out.push(i - 1);
    if (x < n - 1) out.push(i + 1);
    return out;
  }

  // (2) true/false theo ô: ô đường thông tới cổng, hoặc công trình kề một ô đường như thế
  function connectivity(cells) {
    const linked = new Array(cells.length).fill(false);
    const queue = [CFG.gate];
    linked[CFG.gate] = true;
    while (queue.length) {
      for (const j of neighbours(queue.pop())) {
        if (!linked[j] && cells[j] === "road") {
          linked[j] = true;
          queue.push(j);
        }
      }
    }
    return cells.map((t, i) => (t === "road" ? linked[i] : t !== null && neighbours(i).some((j) => linked[j])));
  }

  // (4) bước 2 và 4-9 của một tháng, với pop cho trước. không đổi state
  function compute(s, pop, eff = aggregate(s.scenarios)) {
    const conn = connectivity(s.cells);
    const slots = { shop: 0, factory: 0, office: 0 };
    let C = 0, J = 0, pts = 0, M = 0;
    s.cells.forEach((t, i) => {
      if (!t) return;
      const b = B[t];
      M += b.maint; // chưa nối vẫn tốn bảo trì
      if (!conn[i]) return;
      C += b.cap || 0;
      J += b.jobs || 0;
      pts += b.pts || 0;
      if (t in slots) slots[t] += b.jobs;
    });
    M *= eff.maintMult;
    const emp = Math.min(pop, J), f = J ? emp / J : 0;
    const E = pop ? (emp / pop) * 100 : 100;
    const G = slots.shop ? Math.min(1, (slots.factory * eff.goodsMult) / slots.shop) : 1;
    const R = f * (slots.shop * B.shop.rev * G + slots.factory * B.factory.rev + slots.office * B.office.rev) * eff.revenueMult;
    const taxIn = (R * s.tax) / 100;
    const S = pop ? Math.min(100, ((pts * CFG.residentsPerPoint) / pop) * 100) : 100;
    const parts = { E: CFG.wE * E, T: CFG.wT * (100 - 2 * s.tax), S: CFG.wS * S, event: eff.happyPenalty };
    const H = clamp(parts.E + parts.T + parts.S + parts.event, 0, 100);
    return { conn, C, J, slots, pts, emp, f, E, G, R, taxIn, M, net: taxIn - M, S, H, parts };
  }

  // Độ hấp dẫn A và dân mục tiêu P* (4, bước 3)
  const attraction = (H) => CFG.aMax * clamp((H - CFG.hLo) / (CFG.hHi - CFG.hLo), 0, 1);
  const targetPop = (C, J, H) => Math.min(C, Math.floor(J * attraction(H)));

  function migrate(pop, C, J, H, leaveRate) {
    pop = Math.min(pop, C);
    const diff = targetPop(C, J, H) - pop;
    pop += Math.sign(diff) * Math.ceil(Math.abs(diff) * CFG.moveRate);
    return pop - Math.round(pop * leaveRate);
  }

  function crises(s, d) {
    const out = [];
    if (s.budget < 0) out.push("BUDGET");
    if (d.H < 50) out.push("HAPPINESS");
    if (s.pop > 0 && d.E < 80) out.push("UNEMPLOYMENT");
    if (d.slots.shop > 0 && d.G < 0.7) out.push("SHORTAGE");
    return out;
  }

  // (5) ván mới: tháng 0, tạm dừng, lưới trống trừ ô cổng
  function newGame() {
    const cells = new Array(CFG.size * CFG.size).fill(null);
    cells[CFG.gate] = "road";
    const s = { month: 0, status: "PAUSED", budget: CFG.startBudget, tax: CFG.startTax, pop: 0, cells, scenarios: [], history: [], crises: [], score: 0 };
    s.H = compute(s, 0).H; // = 82
    return s;
  }

  // (4) chạy 1 tháng. sửa s tại chỗ, trả về số liệu tháng vừa tính
  function tick(s) {
    if (s.status !== "ACTIVE") return null;
    const eff = aggregate(s.scenarios);
    const before = compute(s, s.pop, eff);
    s.pop = migrate(s.pop, before.C, before.J, s.H, eff.leaveRate);
    const d = compute(s, s.pop, eff);
    s.budget += d.net;
    s.H = d.H;
    s.month += 1;
    for (const a of s.scenarios) a.monthsActive += 1;
    s.scenarios = s.scenarios.filter((a) => a.monthsActive < scenarioById(a.id).months);
    s.crises = crises(s, d);
    s.score = Math.max(0, Math.round((d.emp * d.H) / 100 + s.budget / 100)); // (6)
    s.history.push({ month: s.month, budget: Math.round(s.budget), revenue: Math.round(d.R), happiness: Math.round(d.H), employment: Math.round(d.E), population: s.pop });
    if (s.budget < CFG.failBudget) s.status = "FAILED";
    else if (s.month >= CFG.months) s.status = "ENDED";
    return d;
  }

  // (5) thao tác người chơi, trả về { ok, err? }. server game thật kiểm lại y như vậy
  const priceOf = (s, type) => Math.round(B[type].price * aggregate(s.scenarios).priceMult);

  function build(s, type, i) {
    if (finished(s)) return fail("Ván đã kết thúc");
    if (!Object.hasOwn(B, type)) return fail("Loại công trình không hợp lệ");
    if (!validCell(i)) return fail("Ô không hợp lệ");
    if (s.cells[i] !== null) return fail("Ô này đã có công trình");
    const cost = priceOf(s, type);
    if (s.budget < cost) return fail(`Không đủ tiền: cần ${money(cost)}`);
    s.budget -= cost;
    s.cells[i] = type;
    return { ok: true, cost };
  }

  // 1 lần kéo đường: bỏ qua ô đã là đường, gặp công trình hoặc thiếu tiền thì từ chối cả đoạn
  function buildRoad(s, path) {
    if (finished(s)) return fail("Ván đã kết thúc");
    if (!Array.isArray(path) || path.length === 0 || path.length > CFG.maxRoadPath) return fail(`Mỗi lần kéo tối đa ${CFG.maxRoadPath} ô`);
    if (!path.every(validCell)) return fail("Ô không hợp lệ");
    const todo = [...new Set(path)].filter((i) => s.cells[i] !== "road");
    if (todo.some((i) => s.cells[i] !== null)) return fail("Đoạn đường đi qua ô đã có công trình");
    const cost = todo.length * priceOf(s, "road");
    if (s.budget < cost) return fail(`Không đủ tiền: cần ${money(cost)} cho ${todo.length} ô đường`);
    s.budget -= cost;
    for (const i of todo) s.cells[i] = "road";
    return { ok: true, cost, built: todo.length };
  }

  function demolish(s, i) {
    if (finished(s)) return fail("Ván đã kết thúc");
    if (!validCell(i) || s.cells[i] === null) return fail("Ô trống");
    if (i === CFG.gate) return fail("Không phá được ô cổng");
    const refund = Math.floor(B[s.cells[i]].price * CFG.refund);
    s.budget += refund;
    s.cells[i] = null;
    return { ok: true, refund };
  }

  function setTax(s, t) {
    if (finished(s)) return fail("Ván đã kết thúc");
    if (!Number.isInteger(t) || t < 0 || t > CFG.taxMax) return fail(`Thuế từ 0 đến ${CFG.taxMax}%`);
    s.tax = t;
    return { ok: true };
  }

  function togglePause(s) {
    if (finished(s)) return fail("Ván đã kết thúc");
    s.status = s.status === "ACTIVE" ? "PAUSED" : "ACTIVE";
    return { ok: true };
  }

  function addScenario(s, id) {
    if (finished(s)) return fail("Ván đã kết thúc");
    if (!scenarioById(id)) return fail("Sự kiện không tồn tại");
    if (s.scenarios.some((a) => a.id === id)) return fail("Sự kiện đang diễn ra");
    s.scenarios.push({ id, monthsActive: 0 });
    return { ok: true };
  }

  function money(x) {
    const n = Math.round(x);
    return (n < 0 ? "-$" : "$") + Math.abs(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  }

  const api = {
    CFG, B, SCENARIOS, CRISIS_LABELS, scenarioById, aggregate, connectivity, compute, attraction, targetPop,
    newGame, tick, finished, priceOf, build, buildRoad, demolish, setTax, togglePause, addScenario, money,
  };
  root.EconGrid = api;
  if (typeof module === "object" && module.exports) module.exports = api;
})(typeof window !== "undefined" ? window : globalThis);
