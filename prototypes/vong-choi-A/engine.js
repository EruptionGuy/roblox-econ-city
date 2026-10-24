/* Prototype vòng chơi A, bỏ đi được, game thật không dùng.
 * Phần ENGINE chép 1:1 từ src/shared/{Config,EconomicEngine,PopulationEngine,GameTick}.luau,
 * chỉ thêm 3 loại hiệu ứng cho thẻ sự kiện: happy_<NHÓM>, prod_<NHÓM>, budgetPerMonth.
 * Không đụng DOM, chỉ có trang HTML gọi vào.
 */
(function (root) {
  "use strict";

  // ===== ENGINE (chép từ Luau) =====
  const F = {
    farmerConsumptionShare: 0.85, roadProductivityPerLevel: 0.02, powerProductivityPerLevel: 0.03,
    schoolProductivityPerLevel: 0.05, subsidyProductivityCap: 0.3, strikeProductivityMultiplier: 0.6,
    happinessBase: 40, happinessIncomeWeight: 30, happinessIncomeCap: 40, happinessInfraWeight: 15,
    infraQualityDivisor: 25, subsidyHappinessBonus: 5, taxPenaltyConsumption: 60, taxPenaltyIncome: 50,
    taxPenaltyCorporate: 50, hospitalSubsidyHappinessPer: 60, hospitalSubsidyHappinessCap: 5,
    discontentRiseRate: 0.3, discontentFallRate: 0.1, growthHappiness: 60, growthRate: 0.005,
    declineHappiness: 30, declineRate: 0.01, migrationDiscontent: 50, migrationMaxPerMonth: 10,
    inflationSensitivity: 0.5, inflationMin: -0.2, inflationMax: 2.0,
  };
  const CFG = {
    MONTHS: 12, FAIL_BUDGET: -5000, FAIL_POPULATION: 30, OVERHEAD_PER_CAPITA: 47,
    INFRA_MAINTENANCE_PER_LEVEL: 50, BUDGET_CLAMP: [-1e7, 1e9], INITIAL_DISCONTENT: 30, MIN_GROUP_POPULATION: 10,
    CRISIS: { budgetBelow: 0, happinessBelow: 20, inflationAbove: 1.0, strikingGroupsAtLeast: 2 },
    // CÂN BẰNG THỬ, game thật không có. ở game thật max trợ cấp + hạ tầng ngay tháng 1 là vừa lãi
    // ~$16.000/tháng vừa được hạnh phúc ~90, hết đánh đổi. 2 luật dưới để có lại đánh đổi
    SUBSIDY_COST_MULT: 4, // trợ cấp $X thật ra tốn $4X mỗi tháng
    BUILD_COST_PER_LEVEL: 2500, // lên cấp L tốn $2.500 x L, trả 1 lần. hạ cấp không hoàn tiền, lên lại cấp đã xây thì miễn phí
  };
  const GROUP_ORDER = ["FARMER", "WORKER", "INTELLECTUAL", "OWNER"];
  const GROUPS = {
    FARMER: { label: "Nông dân", startPopulation: 250, baseIncome: 100, targetIncome: 115, taxType: "consumption", sector: "farmSubsidy", strikeThreshold: 70 },
    WORKER: { label: "Công nhân", startPopulation: 250, baseIncome: 200, targetIncome: 230, taxType: "income", sector: "industrySubsidy", strikeThreshold: 65 },
    INTELLECTUAL: { label: "Trí thức", startPopulation: 150, baseIncome: 400, targetIncome: 460, taxType: "income", sector: "schoolSubsidy", strikeThreshold: 75 },
    OWNER: { label: "Chủ xưởng", startPopulation: 50, baseIncome: 800, targetIncome: 920, taxType: "corporate", sector: "industrySubsidy", strikeThreshold: 80 },
  };
  const PRODUCTIVITY_BASE = 1.04;
  const DEFAULT_POLICY = {
    incomeTax: 0.15, corporateTax: 0.2, consumptionTax: 0.1,
    farmSubsidy: 0, industrySubsidy: 0, schoolSubsidy: 0, hospitalSubsidy: 0,
    roadLevel: 0, powerLevel: 0, waterLevel: 0, schoolLevel: 0, hospitalLevel: 0,
  };
  const POLICY_FIELDS = [
    { key: "incomeTax", tab: "tax", label: "Thuế thu nhập", who: "Công nhân, trí thức trả", min: 0, max: 0.6, step: 0.01, danger: 0.4, kind: "percent" },
    { key: "corporateTax", tab: "tax", label: "Thuế doanh nghiệp", who: "Chủ xưởng trả", min: 0, max: 0.5, step: 0.01, danger: 0.35, kind: "percent" },
    { key: "consumptionTax", tab: "tax", label: "Thuế tiêu dùng", who: "Nông dân trả", min: 0, max: 0.3, step: 0.01, danger: 0.22, kind: "percent" },
    { key: "farmSubsidy", tab: "subsidy", label: "Nông trại", who: "Giúp nông dân", min: 0, max: 500, step: 10, kind: "money" },
    { key: "schoolSubsidy", tab: "subsidy", label: "Trường học", who: "Giúp trí thức", min: 0, max: 500, step: 10, kind: "money" },
    { key: "hospitalSubsidy", tab: "subsidy", label: "Bệnh viện", who: "Mọi người vui hơn", min: 0, max: 500, step: 10, kind: "money" },
    { key: "industrySubsidy", tab: "subsidy", label: "Công nghiệp", who: "Giúp công nhân, chủ xưởng", min: 0, max: 500, step: 10, kind: "money" },
    { key: "roadLevel", tab: "infra", label: "Đường xá", who: "Năng suất mọi nhóm", min: 0, max: 5, step: 1, kind: "level" },
    { key: "powerLevel", tab: "infra", label: "Lưới điện", who: "Năng suất mọi nhóm", min: 0, max: 5, step: 1, kind: "level" },
    { key: "waterLevel", tab: "infra", label: "Cấp nước", who: "Hạnh phúc", min: 0, max: 5, step: 1, kind: "level" },
    { key: "schoolLevel", tab: "infra", label: "Trường học", who: "Năng suất trí thức", min: 0, max: 5, step: 1, kind: "level" },
    { key: "hospitalLevel", tab: "infra", label: "Bệnh viện", who: "Hạnh phúc", min: 0, max: 5, step: 1, kind: "level" },
  ];
  const FIELD_BY_KEY = Object.fromEntries(POLICY_FIELDS.map((f) => [f.key, f]));

  const clamp = (x, lo, hi) => (x !== x ? lo : x < lo ? lo : x > hi ? hi : x);
  const round = (x) => Math.floor(x + 0.5);
  const roundTo = (x, d) => Math.floor(x * 10 ** d + 0.5) / 10 ** d;
  const clone = (v) => JSON.parse(JSON.stringify(v));

  const EFFECT_RULES = {
    farmProductivityPenalty: ["max", 0], industryProductivityPenalty: ["max", 0], happinessPenalty: ["sum", 0],
    gdpMultiplier: ["product", 1], populationDeclineRate: ["max", 0], consumptionTaxMultiplier: ["product", 1],
    inflationBoost: ["sum", 0], powerEfficiency: ["min", 1], waterEfficiency: ["min", 1],
    hospitalSubsidyMultiplier: ["max", 1], farmSubsidyDisabled: ["max", 0],
    // cho thẻ sự kiện, Luau không có
    budgetPerMonth: ["sum", 0],
    happy_FARMER: ["sum", 0], happy_WORKER: ["sum", 0], happy_INTELLECTUAL: ["sum", 0], happy_OWNER: ["sum", 0],
    prod_FARMER: ["sum", 0], prod_WORKER: ["sum", 0], prod_INTELLECTUAL: ["sum", 0], prod_OWNER: ["sum", 0],
  };

  function aggregate(list) {
    const out = {};
    for (const k in EFFECT_RULES) out[k] = EFFECT_RULES[k][1];
    for (const a of list || []) {
      for (const k in a.effects || {}) {
        const rule = EFFECT_RULES[k];
        const v = a.effects[k];
        if (!rule || typeof v !== "number") continue;
        if (rule[0] === "max") out[k] = Math.max(out[k], v);
        else if (rule[0] === "min") out[k] = Math.min(out[k], v);
        else if (rule[0] === "sum") out[k] += v;
        else out[k] *= v;
      }
    }
    return out;
  }

  function effectivePolicy(policy, eff) {
    if (eff.farmSubsidyDisabled > 0 && policy.farmSubsidy !== 0) return { ...policy, farmSubsidy: 0 };
    return policy;
  }

  function taxRate(type, policy, eff) {
    const d = GROUPS[type];
    if (d.taxType === "consumption") return clamp(policy.consumptionTax * (eff.consumptionTaxMultiplier || 1), 0, 0.9);
    if (d.taxType === "income") return policy.incomeTax;
    return policy.corporateTax;
  }
  function taxRevenue(g, policy, eff) {
    const rate = taxRate(g.type, policy, eff);
    if (GROUPS[g.type].taxType === "consumption") return g.income * F.farmerConsumptionShare * rate * g.population;
    return g.income * rate * g.population;
  }
  const subsidySpending = (p) => (p.farmSubsidy + p.industrySubsidy + p.schoolSubsidy + p.hospitalSubsidy) * CFG.SUBSIDY_COST_MULT;
  const INFRA_KEYS = ["roadLevel", "powerLevel", "waterLevel", "schoolLevel", "hospitalLevel"];
  // Tiền xây các cấp hạ tầng chưa từng xây
  function buildCost(policy, built) {
    let c = 0;
    for (const k of INFRA_KEYS) for (let l = (built[k] || 0) + 1; l <= policy[k]; l++) c += CFG.BUILD_COST_PER_LEVEL * l;
    return c;
  }
  const infraLevels = (p) => p.roadLevel + p.powerLevel + p.waterLevel + p.schoolLevel + p.hospitalLevel;
  const maintenanceCost = (p) => infraLevels(p) * CFG.INFRA_MAINTENANCE_PER_LEVEL;
  const totalPop = (groups) => groups.reduce((s, g) => s + g.population, 0);

  function productivity(g, policy, eff) {
    const d = GROUPS[g.type];
    let m = 1 + policy.roadLevel * F.roadProductivityPerLevel + policy.powerLevel * F.powerProductivityPerLevel * (eff.powerEfficiency ?? 1);
    if (g.type === "INTELLECTUAL") m += policy.schoolLevel * F.schoolProductivityPerLevel;
    const sub = policy[d.sector] || 0;
    if (sub > 0) m += Math.min(sub / d.targetIncome, F.subsidyProductivityCap);
    if (g.striking) m *= F.strikeProductivityMultiplier;
    if (g.type === "FARMER") m *= 1 - (eff.farmProductivityPenalty || 0);
    else if (g.type === "WORKER" || g.type === "OWNER") m *= 1 - (eff.industryProductivityPenalty || 0);
    m *= 1 + (eff["prod_" + g.type] || 0); // Luau không có
    return Math.max(0, m);
  }
  const nominalIncome = (g, prod, policy, eff) => GROUPS[g.type].baseIncome * prod * (1 - taxRate(g.type, policy, eff));

  function infraQuality(p, eff) {
    const t = p.roadLevel + p.powerLevel * (eff.powerEfficiency ?? 1) + p.waterLevel * (eff.waterEfficiency ?? 1) + p.schoolLevel + p.hospitalLevel;
    return Math.min(t / F.infraQualityDivisor, 1);
  }
  function taxPenalty(type, policy, eff) {
    const rate = taxRate(type, policy, eff);
    const t = GROUPS[type].taxType;
    return rate * (t === "consumption" ? F.taxPenaltyConsumption : t === "income" ? F.taxPenaltyIncome : F.taxPenaltyCorporate);
  }
  function happiness(g, real, policy, eff) {
    const d = GROUPS[g.type];
    let h = F.happinessBase;
    h += Math.min(F.happinessIncomeCap, (real / d.targetIncome) * F.happinessIncomeWeight);
    h += infraQuality(policy, eff) * F.happinessInfraWeight;
    if ((policy[d.sector] || 0) > 0) h += F.subsidyHappinessBonus;
    const hm = eff.hospitalSubsidyMultiplier || 1;
    h += Math.min((policy.hospitalSubsidy / F.hospitalSubsidyHappinessPer) * hm, F.hospitalSubsidyHappinessCap * hm);
    h -= taxPenalty(g.type, policy, eff);
    h += eff.happinessPenalty || 0;
    h += eff["happy_" + g.type] || 0; // Luau không có
    return clamp(h, 0, 100);
  }
  function nextDiscontent(cur, h) {
    const target = 100 - h;
    return cur + (target - cur) * (target > cur ? F.discontentRiseRate : F.discontentFallRate);
  }
  function naturalChange(pop, h) {
    if (h > F.growthHappiness) return round(pop * F.growthRate);
    if (h < F.declineHappiness) return -round(pop * F.declineRate);
    return 0;
  }
  function scenarioDecline(pop, eff, policy) {
    let rate = eff.populationDeclineRate || 0;
    if (rate <= 0) return 0;
    if (policy.hospitalSubsidy >= 200) rate *= 0.5;
    return round(pop * rate);
  }
  function migrate(byType, policy) {
    const fa = byType.FARMER, wo = byType.WORKER;
    if (policy.industrySubsidy > policy.farmSubsidy && fa.discontent > F.migrationDiscontent) {
      const moved = Math.min(F.migrationMaxPerMonth, Math.max(0, fa.population - CFG.MIN_GROUP_POPULATION));
      fa.population -= moved;
      wo.population += moved;
      return moved;
    }
    return 0;
  }
  function detectCrises(s) {
    const out = [];
    if (s.budget < CFG.CRISIS.budgetBelow) out.push("BUDGET");
    if (s.happiness < CFG.CRISIS.happinessBelow) out.push("HAPPINESS");
    if (s.inflation > CFG.CRISIS.inflationAbove) out.push("INFLATION");
    if (s.groups.filter((g) => g.striking).length >= CFG.CRISIS.strikingGroupsAtLeast) out.push("STRIKE_WAVE");
    return out;
  }

  // 1 tháng, đúng thứ tự như GameTick.processTick. sửa s tại chỗ
  function processTick(s) {
    if (s.status !== "ACTIVE") return null;
    const groups = s.groups;
    const eff = aggregate(s.scenarios);
    const policy = effectivePolicy(s.policy, eff);
    const prevInflation = s.inflation || 0;
    s.month += 1;

    let taxTotal = 0;
    for (const g of groups) taxTotal += taxRevenue(g, policy, eff);
    const subsidies = subsidySpending(policy);
    const maintenance = maintenanceCost(policy);
    const overhead = totalPop(groups) * CFG.OVERHEAD_PER_CAPITA;
    const extra = eff.budgetPerMonth || 0; // Luau không có. khoản vay, trợ giá, du lịch...
    const construction = buildCost(s.policy, s.built); // CÂN BẰNG THỬ
    for (const k of INFRA_KEYS) s.built[k] = Math.max(s.built[k] || 0, s.policy[k]);
    const budgetDelta = taxTotal - subsidies - maintenance - overhead + extra - construction;
    s.budget = clamp(s.budget + budgetDelta, CFG.BUDGET_CLAMP[0], CFG.BUDGET_CLAMP[1]);

    const prods = groups.map((g) => productivity(g, policy, eff));
    const noms = groups.map((g, i) => nominalIncome(g, prods[i], policy, eff));
    let supply = 0, demand = 0;
    groups.forEach((g, i) => {
      supply += PRODUCTIVITY_BASE * prods[i] * g.population * GROUPS[g.type].baseIncome;
      demand += (noms[i] / (1 + prevInflation)) * g.population;
    });
    let inflation = supply <= 0 ? F.inflationMax : clamp(((demand - supply) / supply) * F.inflationSensitivity, F.inflationMin, F.inflationMax);
    inflation = clamp(inflation + (eff.inflationBoost || 0), F.inflationMin, F.inflationMax);

    groups.forEach((g, i) => {
      const real = noms[i] / (1 + inflation);
      g.productivity = prods[i];
      g.income = noms[i];
      g.realIncome = real;
      g.happiness = happiness(g, real, policy, eff);
      g.discontent = clamp(nextDiscontent(g.discontent, g.happiness), 0, 100);
      g.striking = g.discontent > GROUPS[g.type].strikeThreshold;
    });

    const byType = {};
    for (const g of groups) {
      byType[g.type] = g;
      let change = naturalChange(g.population, g.happiness) - scenarioDecline(g.population, eff, policy);
      g.population = Math.max(CFG.MIN_GROUP_POPULATION, g.population + change);
    }
    const migrated = migrate(byType, policy);

    s.inflation = inflation;
    let gdp = 0;
    groups.forEach((g, i) => (gdp += PRODUCTIVITY_BASE * prods[i] * g.population * noms[i] * (1 + inflation)));
    s.gdp = gdp * (eff.gdpMultiplier || 1);
    const pop = totalPop(groups);
    s.population = pop;
    s.happiness = pop > 0 ? groups.reduce((a, g) => a + g.happiness * g.population, 0) / pop : 0;

    s.crises = detectCrises(s);
    if (s.crises.length === 0) s.crisisFreeMonths += 1;

    const kept = [], finished = [];
    for (const a of s.scenarios) {
      a.monthsActive += 1;
      (a.monthsActive >= a.durationMonths ? finished : kept).push(a);
    }
    s.scenarios = kept;

    if (s.budget < CFG.FAIL_BUDGET || pop < CFG.FAIL_POPULATION) s.status = "FAILED";
    else if (s.month >= s.maxMonths) s.status = "ENDED";

    s.history.push({
      month: s.month, budget: roundTo(s.budget, 2), gdp: roundTo(s.gdp, 2),
      happiness: roundTo(s.happiness, 2), inflation: roundTo(s.inflation, 4), population: pop,
      striking: groups.filter((g) => g.striking).map((g) => g.type),
    });
    return { month: s.month, taxRevenue: taxTotal, subsidies, maintenance, overhead, extra, construction, budgetDelta, migrated, finished, status: s.status };
  }

  // ===== VÒNG CHƠI A (phần đang thử) =====

  const CITIES = [
    {
      id: "binhyen", name: "Làng Bình Yên", budget: 10000,
      pop: { FARMER: 250, WORKER: 250, INTELLECTUAL: 150, OWNER: 50 },
      blurb: "Thành phố 700 dân, chưa có khủng hoảng nào. Hợp để làm quen.",
      brief: "Thị trưởng cũ để lại một thành phố đang lỗ khoảng $6.000 mỗi tháng. Với mức thuế hiện tại, sang tháng 2 kho bạc sẽ cạn. Hãy chỉnh thuế trước khi bấm Kết thúc tháng.",
      scripted: {},
      goals: [
        { label: "Trụ đủ 12 tháng", test: (s) => s.status === "ENDED" },
        { label: "Hạnh phúc cuối năm từ 62 trở lên", test: (s) => s.happiness >= 62, live: (s) => `đang ${s.happiness.toFixed(0)}` },
        { label: "Cuối năm còn ít nhất $10.000 (đã trừ nợ)", test: (s) => netBudget(s) >= 10000, live: (s) => `đang ${money(netBudget(s))}` },
      ],
    },
    {
      id: "ongkhoi", name: "Thị trấn Ống Khói", budget: 8000,
      pop: { FARMER: 150, WORKER: 380, INTELLECTUAL: 100, OWNER: 70 },
      discontent: { WORKER: 45 },
      blurb: "Thị trấn nhà máy, công nhân sẵn bực bội. Tháng 4 có khủng hoảng năng lượng.",
      brief: "Ống Khói sống nhờ nhà máy. Công nhân đông và đang khó chịu sẵn. Tin tình báo cho biết tháng 4 sẽ thiếu nhiên liệu.",
      scripted: { 4: "nangluong" },
      goals: [
        { label: "Trụ đủ 12 tháng", test: (s) => s.status === "ENDED" },
        { label: "Không nhóm nào đình công trong 3 tháng cuối", test: (s) => s.history.slice(-3).every((h) => h.striking.length === 0), live: (s) => (s.groups.some((g) => g.striking) ? "đang có đình công" : "chưa có đình công") },
        { label: "GDP tháng 12 từ $220.000 trở lên", test: (s) => s.gdp >= 220000, live: (s) => `đang ${money(s.gdp)}` },
      ],
    },
    {
      id: "dao", name: "Đảo Lúa Vàng", budget: 6000,
      pop: { FARMER: 400, WORKER: 150, INTELLECTUAL: 100, OWNER: 50 },
      blurb: "Đảo nông nghiệp, ít tiền. Mất mùa ở tháng 3, đại dịch ở tháng 8.",
      brief: "Đảo Lúa Vàng nghèo tiền nhưng nhiều nông dân. Năm nay sẽ không dễ dàng: mất mùa đầu năm, dịch bệnh cuối năm.",
      scripted: { 3: "matmua", 8: "daidich" },
      goals: [
        { label: "Trụ đủ 12 tháng", test: (s) => s.status === "ENDED" },
        { label: "Dân số cuối năm từ 680 trở lên", test: (s) => s.population >= 680, live: (s) => `đang ${s.population}` },
        { label: "Hạnh phúc cuối năm từ 50 trở lên", test: (s) => s.happiness >= 50, live: (s) => `đang ${s.happiness.toFixed(0)}` },
      ],
    },
  ];
  const CITY_BY_ID = Object.fromEntries(CITIES.map((c) => [c.id, c]));

  function newSession(cityId) {
    const city = CITY_BY_ID[cityId];
    const groups = GROUP_ORDER.map((type) => ({
      type, population: city.pop[type], income: GROUPS[type].baseIncome, happiness: 50,
      discontent: (city.discontent && city.discontent[type]) ?? CFG.INITIAL_DISCONTENT, productivity: 1, striking: false,
    }));
    return {
      city: cityId, month: 0, maxMonths: CFG.MONTHS, status: "ACTIVE", budget: city.budget, gdp: 0,
      happiness: 50, inflation: 0, population: totalPop(groups), crisisFreeMonths: 0,
      policy: clone(DEFAULT_POLICY), built: {}, groups, scenarios: [], crises: [], history: [], usedEvents: [], log: [],
    };
  }

  // nợ còn phải trả: phần budgetPerMonth âm còn lại của các khoản vay
  function debt(s) {
    let d = 0;
    for (const a of s.scenarios) {
      const per = a.effects.budgetPerMonth || 0;
      if (a.loan && per < 0) d += -per * (a.durationMonths - a.monthsActive);
    }
    return d;
  }
  const netBudget = (s) => s.budget - debt(s);

  function stars(s) {
    const goals = CITY_BY_ID[s.city].goals;
    if (s.status !== "ENDED") return 0;
    return goals.filter((g) => g.test(s)).length;
  }

  // dự báo = chạy thử tháng tới trên bản clone. engine không có random nên ra đúng số
  function forecast(s) {
    const c = clone(s);
    const r = processTick(c);
    return { budgetDelta: r.budgetDelta, taxRevenue: r.taxRevenue, spending: r.subsidies + r.maintenance + r.overhead + r.construction - r.extra, construction: r.construction, budget: c.budget, happiness: c.happiness, inflation: c.inflation, status: c.status, striking: c.groups.filter((g) => g.striking).map((g) => g.type) };
  }

  // ----- thẻ sự kiện -----
  // outcome: { budget, discontent:{NHÓM:+/-}, pop:{NHÓM:+/-}, policy:{key:+/-}, scenario:{name, months, effects, loan}, text }
  // gamble:  { chance, win: outcome, lose: outcome }
  const mostUpset = (s) => s.groups.slice().sort((a, b) => b.discontent - a.discontent)[0];

  const EVENTS = [
    {
      id: "luong", title: "Công nhân đòi tăng lương",
      text: "Công đoàn kéo đến trước toà thị chính: \"Giá cả tăng mà lương không tăng!\"",
      weight: (s) => (s.groups[1].discontent > 40 ? 3 : 1),
      choices: [
        { label: "Thưởng nóng cho công nhân", hint: "-$2.000 - công nhân vui hơn trong 3 tháng", out: { budget: -2000, scenario: { name: "Thưởng công nhân", months: 3, effects: { happy_WORKER: 10 } }, text: "Công nhân reo hò. Kho bạc vơi đi $2.000." } },
        { label: "Từ chối", hint: "Không tốn tiền - công nhân bực hơn", out: { discontent: { WORKER: 20 }, text: "Công đoàn bỏ về, hứa sẽ quay lại đông hơn." } },
        { label: "Thương lượng", hint: "50% êm đẹp, 50% tệ hơn", gamble: { chance: 0.5, win: { discontent: { WORKER: -15 }, text: "Bạn thuyết phục được công đoàn mà không tốn đồng nào!" }, lose: { discontent: { WORKER: 30 }, text: "Cuộc họp đổ vỡ. Công nhân còn giận hơn trước." } } },
      ],
    },
    {
      id: "nhamay", title: "Tập đoàn lạ muốn xây nhà máy",
      text: "Họ trả tiền thuê đất ngay. Nhưng khói nhà máy sẽ bay về phía đồng lúa.",
      choices: [
        { label: "Cho xây", hint: "+$4.000 - công nhân, chủ xưởng làm năng suất hơn - nông dân khó chịu 6 tháng", out: { budget: 4000, scenario: { name: "Nhà máy mới", months: 6, effects: { prod_WORKER: 0.1, prod_OWNER: 0.1, happy_FARMER: -8 } }, text: "Nhà máy mọc lên. Ống khói bắt đầu nhả khói." } },
        { label: "Từ chối", hint: "Không có gì thay đổi", out: { text: "Tập đoàn sang thành phố bên cạnh. Nông dân thở phào." } },
        { label: "Đòi gấp đôi tiền thuê", hint: "40%: +$8.000 - 60%: họ bỏ đi", gamble: { chance: 0.4, win: { budget: 8000, scenario: { name: "Nhà máy mới", months: 6, effects: { prod_WORKER: 0.1, prod_OWNER: 0.1, happy_FARMER: -8 } }, text: "Họ đồng ý! Kho bạc nhận $8.000." }, lose: { text: "Tập đoàn bỏ đi, chê thị trưởng tham." } } },
      ],
    },
    {
      id: "lehoi", title: "Lễ hội mùa xuân sắp tới",
      text: "Cả thành phố đang chờ xem năm nay thị trưởng tổ chức thế nào.",
      choices: [
        { label: "Tổ chức thật lớn", hint: "-$2.500 - mọi người vui hơn trong 2 tháng", out: { budget: -2500, scenario: { name: "Dư âm lễ hội", months: 2, effects: { happinessPenalty: 8 } }, text: "Pháo hoa rực trời. Ai cũng nói về lễ hội." } },
        { label: "Tổ chức nhỏ", hint: "-$800 - vui hơn 1 tháng", out: { budget: -800, scenario: { name: "Lễ hội nhỏ", months: 1, effects: { happinessPenalty: 4 } }, text: "Một buổi tối ấm cúng ở quảng trường." } },
        { label: "Huỷ lễ hội", hint: "Không tốn tiền - dân hơi buồn", out: { scenario: { name: "Không có lễ hội", months: 1, effects: { happinessPenalty: -4 } }, text: "Quảng trường vắng tanh. Trẻ con buồn thiu." } },
      ],
    },
    {
      id: "hanhan", title: "Hạn hán kéo dài", when: (s) => s.month >= 2,
      text: "Ba tuần không có giọt mưa. Đồng ruộng nứt nẻ.",
      choices: [
        { label: "Mua nước dự trữ", hint: "-$2.500 - đồng ruộng an toàn", out: { budget: -2500, text: "Xe bồn chở nước về kịp lúc." } },
        { label: "Chờ trời mưa", hint: "Năng suất nông dân -30% trong 3 tháng", out: { scenario: { name: "Hạn hán", months: 3, effects: { farmProductivityPenalty: 0.3 } }, text: "Lúa héo dần. Nông dân lo lắng." } },
        { label: "Thuê thầy làm mưa", hint: "-$500 - 25% mưa thật, 75% vẫn hạn", gamble: { chance: 0.25, win: { budget: -500, text: "Mưa rơi thật! Không ai hiểu vì sao." }, lose: { budget: -500, scenario: { name: "Hạn hán", months: 3, effects: { farmProductivityPenalty: 0.3 } }, text: "Trời vẫn nắng chang chang. Mất $500 tiền công." } } },
      ],
    },
    {
      id: "daihoc", title: "Sinh viên muốn có trường đại học",
      text: "Hàng trăm chữ ký gửi lên: \"Cho chúng tôi một trường đại học!\"",
      choices: [
        { label: "Xây đại học", hint: "-$4.000 - năng suất trí thức +15% đến hết năm", out: { budget: -4000, scenario: { name: "Đại học mới", months: 12, effects: { prod_INTELLECTUAL: 0.15, happy_INTELLECTUAL: 5 } }, text: "Khởi công trường đại học đầu tiên của thành phố." } },
        { label: "Để năm sau", hint: "Trí thức bất mãn", out: { discontent: { INTELLECTUAL: 15 }, text: "Sinh viên thất vọng, vài người dọa chuyển đi." } },
      ],
    },
    {
      id: "giamthue", title: "Chủ xưởng đòi giảm thuế", when: (s) => s.policy.corporateTax >= 0.25,
      text: "\"Giảm thuế đi, chúng tôi sẽ mở rộng nhà xưởng!\" Hội chủ xưởng nói.",
      choices: [
        { label: "Giảm 5% thuế doanh nghiệp", hint: "Thuế doanh nghiệp -5% - chủ xưởng vui 4 tháng", out: { policy: { corporateTax: -0.05 }, scenario: { name: "Chủ xưởng hài lòng", months: 4, effects: { happy_OWNER: 8 } }, text: "Chủ xưởng bắt tay thị trưởng. Thu thuế sẽ giảm." } },
        { label: "Giữ nguyên", hint: "Chủ xưởng bất mãn - 50% vài người bỏ đi", gamble: { chance: 0.5, win: { discontent: { OWNER: 10 }, text: "Chủ xưởng càu nhàu nhưng ở lại." }, lose: { discontent: { OWNER: 10 }, pop: { OWNER: -8 }, text: "8 chủ xưởng đóng cửa, chuyển sang thành phố khác!" } } },
      ],
    },
    {
      id: "movang", title: "Phát hiện mỏ vàng ngoài đồi!",
      text: "Một bác nông dân đào giếng thì thấy vàng lấp lánh.",
      choices: [
        { label: "Khai thác ngay", hint: "+$6.000 - ô nhiễm làm nông dân buồn 4 tháng", out: { budget: 6000, scenario: { name: "Mỏ vàng", months: 4, effects: { happy_FARMER: -10 } }, text: "Vàng chảy về kho bạc. Bụi mỏ bay khắp đồng." } },
        { label: "Bán quyền khai thác", hint: "+$3.000 - không ô nhiễm", out: { budget: 3000, text: "Một công ty mua quyền khai thác. Tiền về ngay." } },
        { label: "Biến đồi thành công viên", hint: "Mọi người vui hơn 4 tháng", out: { scenario: { name: "Công viên Đồi Vàng", months: 4, effects: { happinessPenalty: 4 } }, text: "Ngọn đồi thành nơi dạo chơi cuối tuần." } },
      ],
    },
    {
      id: "cum", title: "Dịch cúm mùa",
      text: "Bệnh viện bắt đầu đông người ho sốt.",
      choices: [
        { label: "Tiêm phòng miễn phí", hint: "-$2.000 - dập dịch ngay", out: { budget: -2000, text: "Dịch được chặn đứng sau một tuần." } },
        { label: "Phát khẩu trang", hint: "-$600 - vẫn có người ốm", out: { budget: -600, scenario: { name: "Cúm mùa (nhẹ)", months: 2, effects: { populationDeclineRate: 0.005, happinessPenalty: -2 } }, text: "Dịch chậm lại nhưng chưa hết." } },
        { label: "Không làm gì", hint: "Dân số -1%/tháng trong 2 tháng (trợ cấp bệnh viện từ $200 giảm một nửa)", out: { scenario: { name: "Cúm mùa", months: 2, effects: { populationDeclineRate: 0.01, happinessPenalty: -5 } }, text: "Dịch lan rộng khắp các khu phố." } },
      ],
    },
    {
      id: "youtuber", title: "YouTuber nổi tiếng muốn đến quay video",
      text: "Kênh có 5 triệu người theo dõi. Họ cần thành phố lo chỗ ở và an ninh.",
      choices: [
        { label: "Mời đến", hint: "-$1.000 - khách du lịch mang về +$700/tháng trong 3 tháng", out: { budget: -1000, scenario: { name: "Khách du lịch", months: 3, effects: { budgetPerMonth: 700, happinessPenalty: 3 } }, text: "Video đạt 2 triệu lượt xem. Khách du lịch kéo đến!" } },
        { label: "Từ chối", hint: "Không có gì thay đổi", out: { text: "YouTuber quay ở thành phố khác." } },
      ],
    },
    {
      id: "vayno", title: "Ngân hàng chào mời khoản vay", when: (s) => s.budget < 4000, weight: () => 4,
      text: "\"Thấy kho bạc của ngài hơi mỏng. Chúng tôi giúp được!\"",
      choices: [
        { label: "Vay $8.000", hint: "Nhận ngay $8.000 - trả $1.000/tháng trong 10 tháng", out: { budget: 8000, scenario: { name: "Trả nợ ngân hàng", months: 10, loan: true, effects: { budgetPerMonth: -1000 } }, text: "Nhận $8.000. Tổng phải trả: $10.000." } },
        { label: "Vay $3.000", hint: "Nhận ngay $3.000 - trả $400/tháng trong 9 tháng", out: { budget: 3000, scenario: { name: "Trả nợ ngân hàng", months: 9, loan: true, effects: { budgetPerMonth: -400 } }, text: "Nhận $3.000. Tổng phải trả: $3.600." } },
        { label: "Không vay", hint: "Tự xoay xở", out: { text: "Ngân hàng để lại danh thiếp rồi về." } },
      ],
    },
    {
      id: "matdien", title: "Mất điện toàn thành phố!", when: (s) => s.month >= 2 && s.policy.powerLevel < 2,
      text: "Lưới điện cũ quá tải. Nhà máy dừng chạy, đèn đường tắt ngóm.",
      choices: [
        { label: "Sửa khẩn cấp", hint: "-$1.500", out: { budget: -1500, text: "Điện có lại sau một đêm. Nên nâng cấp lưới điện thôi." } },
        { label: "Sửa từ từ", hint: "Năng suất công nghiệp -20% trong 2 tháng", out: { scenario: { name: "Mất điện", months: 2, effects: { industryProductivityPenalty: 0.2, happinessPenalty: -3 } }, text: "Thành phố sống trong bóng tối mấy tuần." } },
      ],
    },
    {
      id: "bieutinh", title: "Biểu tình trước toà thị chính", weight: () => 5,
      when: (s) => s.month >= 1 && (s.groups.some((g) => g.striking) || mostUpset(s).discontent > 55),
      text: (s) => `${GROUPS[mostUpset(s).type].label} xuống đường, giơ biểu ngữ phản đối thị trưởng.`,
      choices: (s) => {
        const g = mostUpset(s);
        const label = GROUPS[g.type].label.toLowerCase();
        const sector = GROUPS[g.type].sector;
        return [
          { label: "Ra nói chuyện, hứa cải thiện", hint: `-$1.000 - ${label} bớt bất mãn`, out: { budget: -1000, discontent: { [g.type]: -20 }, text: "Đám đông giải tán, nhưng họ sẽ theo dõi lời hứa của bạn." } },
          { label: `Tăng trợ cấp ${FIELD_BY_KEY[sector].label.toLowerCase()} thêm $100`, hint: `Chi thêm $100 mỗi tháng - ${label} bớt bất mãn`, out: { policy: { [sector]: 100 }, discontent: { [g.type]: -10 }, text: "Trợ cấp tăng. Một chiến thắng nhỏ cho người biểu tình." } },
          { label: "Đóng cửa toà thị chính", hint: "Không tốn tiền - mọi người bực hơn", out: { discontent: { FARMER: 8, WORKER: 8, INTELLECTUAL: 8, OWNER: 8 }, text: "Cửa đóng then cài. Báo chí chỉ trích thị trưởng." } },
        ];
      },
    },
    {
      id: "xang", title: "Giá xăng thế giới tăng vọt",
      text: "Xe tải chở hàng đắt đỏ hơn, giá mọi thứ sắp leo thang.",
      choices: [
        { label: "Trợ giá xăng", hint: "-$700/tháng trong 3 tháng - giá cả ổn định", out: { scenario: { name: "Trợ giá xăng", months: 3, effects: { budgetPerMonth: -700 } }, text: "Giá xăng trong thành phố đứng yên." } },
        { label: "Để thị trường tự lo", hint: "Lạm phát +8% trong 3 tháng", out: { scenario: { name: "Giá xăng cao", months: 3, effects: { inflationBoost: 0.08, happinessPenalty: -2 } }, text: "Giá cả bắt đầu tăng từng ngày." } },
      ],
    },
    {
      id: "congvien", title: "Kiến trúc sư đề xuất xây công viên",
      text: "Một bản vẽ đẹp với hồ nước, cây xanh và sân chơi.",
      choices: [
        { label: "Xây công viên", hint: "-$1.800 - dân vui hơn trong 6 tháng", out: { budget: -1800, scenario: { name: "Công viên mới", months: 6, effects: { happinessPenalty: 3 } }, text: "Cuối tuần công viên chật kín người." } },
        { label: "Cảm ơn, để sau", hint: "Không có gì thay đổi", out: { text: "Bản vẽ được cất vào ngăn kéo." } },
      ],
    },
    {
      id: "thamnhung", title: "Tin đồn quan chức ăn chặn tiền", when: (s) => s.budget > 15000,
      text: "Báo đăng tin: có người trong toà thị chính \"ăn\" tiền xây đường.",
      choices: [
        { label: "Điều tra công khai", hint: "-$1.000 - dân tin bạn hơn 3 tháng", out: { budget: -1000, scenario: { name: "Lòng tin của dân", months: 3, effects: { happinessPenalty: 5 } }, text: "Kẻ gian bị bắt. Dân khen thị trưởng minh bạch." } },
        { label: "Im lặng cho qua", hint: "50% tin đồn tự lắng - 50% vỡ lở", gamble: { chance: 0.5, win: { text: "Tin đồn tự lắng xuống." }, lose: { budget: -2000, scenario: { name: "Bê bối", months: 3, effects: { happinessPenalty: -8 } }, text: "Vụ việc vỡ lở! Mất $2.000 và lòng tin của dân." } } },
      ],
    },
    {
      id: "nhapcu", title: "Một đoàn người xin đến sống", when: (s) => s.happiness > 55,
      text: "Nghe nói thành phố bạn sống tốt, họ muốn chuyển đến.",
      choices: [
        { label: "Chào đón tất cả", hint: "+40 công nhân - thêm thuế nhưng thêm chi phí quản lý", out: { pop: { WORKER: 40 }, text: "40 công nhân mới dọn đến." } },
        { label: "Chỉ nhận người có tay nghề", hint: "+15 trí thức", out: { pop: { INTELLECTUAL: 15 }, text: "15 kỹ sư và giáo viên dọn đến." } },
        { label: "Từ chối", hint: "Không có gì thay đổi", out: { text: "Đoàn người đi tiếp sang thành phố khác." } },
      ],
    },
    // --- khủng hoảng theo kịch bản thành phố: luôn xảy ra, không rút ngẫu nhiên ---
    {
      id: "nangluong", scripted: true, title: "Khủng hoảng năng lượng!",
      text: "Nhiên liệu cạn kiệt. Nhà máy chỉ chạy được nửa công suất trong 5 tháng tới.",
      choices: [
        { label: "Nhập điện giá cao", hint: "-$800/tháng trong 5 tháng - thiệt hại giảm một nửa", out: { scenario: { name: "Khủng hoảng năng lượng (nhập điện)", months: 5, effects: { industryProductivityPenalty: 0.15, powerEfficiency: 0.75, budgetPerMonth: -800 } }, text: "Điện nhập về, nhà máy chạy cầm chừng." } },
        { label: "Chịu đựng", hint: "Năng suất công nghiệp -30% trong 5 tháng", out: { scenario: { name: "Khủng hoảng năng lượng", months: 5, effects: { industryProductivityPenalty: 0.3, powerEfficiency: 0.5 } }, text: "Nhà máy tắt bớt dây chuyền." } },
        { label: "Kêu gọi toàn dân tiết kiệm điện", hint: "Năng suất -10% - mọi người buồn 5 tháng", out: { scenario: { name: "Khủng hoảng năng lượng (tiết kiệm)", months: 5, effects: { industryProductivityPenalty: 0.1, happinessPenalty: -6 } }, text: "Nhà nào cũng tắt đèn sớm." } },
      ],
    },
    {
      id: "matmua", scripted: true, title: "Mất mùa lúa!",
      text: "Sâu bệnh phá hết nửa cánh đồng. Giá gạo bắt đầu tăng.",
      choices: [
        { label: "Nhập gạo từ nơi khác", hint: "-$900/tháng trong 5 tháng - giá gạo không tăng", out: { scenario: { name: "Mất mùa (nhập gạo)", months: 5, effects: { farmProductivityPenalty: 0.4, budgetPerMonth: -900 } }, text: "Tàu chở gạo cập cảng." } },
        { label: "Chịu đựng", hint: "Nông dân -40% năng suất, trợ cấp nông trại vô tác dụng, giá cả tăng - 5 tháng", out: { scenario: { name: "Mất mùa", months: 5, effects: { farmSubsidyDisabled: 1, farmProductivityPenalty: 0.4, consumptionTaxMultiplier: 1.5, inflationBoost: 0.05 } }, text: "Chợ vắng gạo, giá tăng từng ngày." } },
      ],
    },
    {
      id: "daidich", scripted: true, title: "Đại dịch!",
      text: "Một loại virus mới lây rất nhanh. Bệnh viện bắt đầu quá tải.",
      choices: [
        { label: "Phong toả thành phố", hint: "Dân số gần như an toàn - năng suất -20%, dân buồn 4 tháng", out: { scenario: { name: "Phong toả", months: 4, effects: { industryProductivityPenalty: 0.2, farmProductivityPenalty: 0.2, gdpMultiplier: 0.8, populationDeclineRate: 0.005, happinessPenalty: -5 } }, text: "Đường phố vắng tanh. Virus chậm lại." } },
        { label: "Mở cửa như thường", hint: "Dân số -2%/tháng trong 5 tháng (trợ cấp bệnh viện từ $200 giảm một nửa)", out: { scenario: { name: "Đại dịch", months: 5, effects: { populationDeclineRate: 0.02, gdpMultiplier: 0.9, hospitalSubsidyMultiplier: 2 } }, text: "Cuộc sống tiếp diễn, nhưng bệnh viện kín giường." } },
      ],
    },
  ];
  const EVENT_BY_ID = Object.fromEntries(EVENTS.map((e) => [e.id, e]));

  // chọn sự kiện cho đầu tháng tới, gọi khi s.month >= 1. khủng hoảng kịch bản luôn ưu tiên
  function pickEvent(s, rng = Math.random) {
    const upcoming = s.month + 1;
    const scriptedId = CITY_BY_ID[s.city].scripted[upcoming];
    if (scriptedId) return scriptedId;
    const pool = EVENTS.filter((e) => !e.scripted && !s.usedEvents.includes(e.id) && (!e.when || e.when(s)));
    if (pool.length === 0) return null;
    const weights = pool.map((e) => (e.weight ? e.weight(s) : 1));
    let r = rng() * weights.reduce((a, b) => a + b, 0);
    for (let i = 0; i < pool.length; i++) {
      r -= weights[i];
      if (r <= 0) return pool[i].id;
    }
    return pool[pool.length - 1].id;
  }

  // chốt chữ + lựa chọn theo state lúc rút, để thẻ biểu tình nhắm đúng nhóm
  function eventCard(s, id) {
    const e = EVENT_BY_ID[id];
    return {
      id, title: e.title, scripted: !!e.scripted,
      text: typeof e.text === "function" ? e.text(s) : e.text,
      choices: typeof e.choices === "function" ? e.choices(s) : e.choices,
    };
  }

  function applyOutcome(s, o, tag) {
    if (o.budget) s.budget += o.budget;
    for (const t in o.discontent || {}) {
      const g = s.groups.find((x) => x.type === t);
      g.discontent = clamp(g.discontent + o.discontent[t], 0, 100);
      g.striking = g.discontent > GROUPS[t].strikeThreshold;
    }
    for (const t in o.pop || {}) {
      const g = s.groups.find((x) => x.type === t);
      g.population = Math.max(CFG.MIN_GROUP_POPULATION, g.population + o.pop[t]);
    }
    s.population = totalPop(s.groups);
    for (const k in o.policy || {}) {
      const f = FIELD_BY_KEY[k];
      s.policy[k] = roundTo(clamp(s.policy[k] + o.policy[k], f.min, f.max), 4);
    }
    if (o.scenario) {
      s.scenarios.push({ id: tag, name: o.scenario.name, durationMonths: o.scenario.months, monthsActive: 0, loan: !!o.scenario.loan, effects: { ...o.scenario.effects } });
    }
  }

  // trả về { text, luck: "win"|"lose"|null }
  function resolveChoice(s, card, index, rng = Math.random) {
    const c = card.choices[index];
    let o = c.out, luck = null;
    if (c.gamble) {
      luck = rng() < c.gamble.chance ? "win" : "lose";
      o = c.gamble[luck];
    }
    applyOutcome(s, o, card.id + "@" + s.month);
    if (!EVENT_BY_ID[card.id].scripted) s.usedEvents.push(card.id);
    s.log.push({ month: s.month + 1, title: card.title, choice: c.label, text: o.text, luck });
    return { text: o.text, luck };
  }

  // ----- báo đầu tháng -----
  // tin xếp theo độ ưu tiên. tin thường không lặp loại đã in ở 2 số gần nhất, tin khẩn thì được
  function headline(s, prev, tick) {
    const city = CITY_BY_ID[s.city].name;
    const c = [];
    const add = (key, text, urgent = false) => c.push({ key, text, urgent });
    const newStrikes = s.groups.filter((g) => g.striking && !(prev.striking || []).includes(g.type));
    if (newStrikes.length) add("strike", `${newStrikes.map((g) => GROUPS[g.type].label).join(" và ")} đình công! Nhà máy, đồng ruộng ngừng hoạt động`, true);
    if (s.budget < 0) add("broke", `Kho bạc âm ${money(-s.budget)}. Âm quá $5.000 là thành phố phá sản`, true);
    if (tick.construction > 0) add("build", `Khởi công nâng cấp hạ tầng: ${money(tick.construction)} đổ vào công trình mới`);
    if (tick.budgetDelta < -2000) add("deficit", `${city} tiêu nhiều hơn thu ${money(-tick.budgetDelta)} trong tháng qua`);
    if (s.inflation > 0.1) add("inflation", `Giá cả tăng ${(s.inflation * 100).toFixed(0)}% trong một tháng, người dân xếp hàng mua gạo`);
    if (s.happiness - prev.happiness >= 4) add("happyUp", `Dân vui hẳn lên: hạnh phúc tăng ${(s.happiness - prev.happiness).toFixed(0)} điểm`);
    if (prev.happiness - s.happiness >= 4) add("happyDown", `Lòng dân đi xuống: hạnh phúc giảm ${(prev.happiness - s.happiness).toFixed(0)} điểm`);
    const stillStriking = s.groups.filter((g) => g.striking);
    if (stillStriking.length) add("strikeOn", `Cuộc đình công của ${GROUPS[stillStriking[0].type].label.toLowerCase()} bước sang tháng mới`);
    if (prev.gdp > 0 && Math.abs(s.gdp / prev.gdp - 1) >= 0.05) add("gdp", `Kinh tế ${s.gdp > prev.gdp ? "tăng tốc" : "chững lại"}: GDP ${s.gdp > prev.gdp ? "tăng" : "giảm"} ${(Math.abs(s.gdp / prev.gdp - 1) * 100).toFixed(0)}%`);
    if (s.inflation < -0.05) add("deflation", `Hàng ế, giá giảm ${(-s.inflation * 100).toFixed(0)}%: chủ cửa hàng than vắng khách`);
    if (tick.budgetDelta > 3000) add("surplus", `Kho bạc dư dả: thu nhiều hơn chi ${money(tick.budgetDelta)}`);
    if (s.population > prev.population) add("popUp", `Thêm ${s.population - prev.population} người chuyển đến ${city}`);
    const sorted = s.groups.slice().sort((a, b) => b.happiness - a.happiness);
    add("best", `${GROUPS[sorted[0].type].label} là nhóm hài lòng nhất thành phố (hạnh phúc ${sorted[0].happiness.toFixed(0)})`);
    add("worst", `${GROUPS[sorted[3].type].label} đang buồn nhất: hạnh phúc chỉ ${sorted[3].happiness.toFixed(0)}`);
    add("calm", `Một tháng bình yên ở ${city}`);
    const recent = (s.newsKeys || []).slice(-2);
    const pick = c.find((x) => x.urgent || !recent.includes(x.key)) || c[c.length - 1];
    s.newsKeys = [...(s.newsKeys || []), pick.key];
    return pick.text;
  }

  // ----- lời dân: mỗi nhóm 1 câu, theo lý do chính làm họ vui/buồn -----
  function quote(s, g, rng = Math.random) {
    const d = GROUPS[g.type];
    const pick = (arr) => arr[Math.floor(rng() * arr.length)];
    if (g.striking) return pick(["Chúng tôi nghỉ làm cho tới khi được đối xử công bằng!", "Đình công! Đình công!"]);
    const eff = aggregate(s.scenarios);
    const taxPct = Math.round(taxRate(g.type, s.policy, eff) * 100);
    const taxName = d.taxType === "consumption" ? "thuế tiêu dùng" : d.taxType === "income" ? "thuế thu nhập" : "thuế doanh nghiệp";
    if (taxPenalty(g.type, s.policy, eff) >= 13) return pick([`${taxName[0].toUpperCase() + taxName.slice(1)} ${taxPct}%? Cao quá rồi!`, `Làm cả tháng, ${taxName} lấy mất ${taxPct}%.`]);
    if (s.inflation > 0.08) return pick(["Giá bánh mì lại tăng nữa rồi!", "Lương chưa kịp về, giá đã lên."]);
    if (s.month > 0 && (g.realIncome || 0) / d.targetIncome < 0.75) return pick(["Lương không đủ sống.", "Tháng này lại phải ăn mì gói."]);
    if (s.month >= 3 && infraQuality(s.policy, eff) < 0.12) return pick(["Đường ổ gà, điện chập chờn...", "Bao giờ mới sửa đường đây?"]);
    if (g.happiness >= 65) return pick(["Sống ở đây thật tuyệt!", "Thị trưởng làm tốt lắm!"]);
    if (g.happiness < 40) return pick(["Tôi đang tính chuyển đi nơi khác.", "Chán thành phố này quá."]);
    return pick(["Tạm ổn, nhưng mong thị trưởng làm tốt hơn.", "Cũng được, chưa có gì đặc biệt."]);
  }

  // ----- mô tả hiệu ứng cho người chơi -----
  const GROUP_SHORT = { FARMER: "nông dân", WORKER: "công nhân", INTELLECTUAL: "trí thức", OWNER: "chủ xưởng" };
  function describeEffects(e) {
    const out = [];
    const pct = (x) => `${x > 0 ? "+" : "-"}${Math.round(Math.abs(x) * 100)}%`;
    const pts = (x) => `${x > 0 ? "+" : "-"}${Math.abs(x)}`;
    for (const k in e) {
      const v = e[k];
      if (k === "budgetPerMonth") out.push(`${v > 0 ? "+" : "-"}${money(Math.abs(v))}/tháng`);
      else if (k === "happinessPenalty") out.push(`hạnh phúc mọi nhóm ${pts(v)}`);
      else if (k.startsWith("happy_")) out.push(`${GROUP_SHORT[k.slice(6)]} ${pts(v)} hạnh phúc`);
      else if (k.startsWith("prod_")) out.push(`năng suất ${GROUP_SHORT[k.slice(5)]} ${pct(v)}`);
      else if (k === "farmProductivityPenalty") out.push(`năng suất nông dân ${pct(-v)}`);
      else if (k === "industryProductivityPenalty") out.push(`năng suất công nghiệp ${pct(-v)}`);
      else if (k === "populationDeclineRate") out.push(`dân số ${pct(-v)}/tháng`);
      else if (k === "inflationBoost") out.push(`lạm phát ${pct(v)}`);
      else if (k === "consumptionTaxMultiplier") out.push(`thuế tiêu dùng thực x${v}`);
      else if (k === "farmSubsidyDisabled") out.push("trợ cấp nông trại vô tác dụng");
      else if (k === "powerEfficiency") out.push(`lưới điện còn ${Math.round(v * 100)}%`);
      else if (k === "gdpMultiplier") out.push(`GDP x${v}`);
      else if (k === "hospitalSubsidyMultiplier") out.push(`trợ cấp bệnh viện hiệu quả x${v}`);
    }
    return out.join(" - ");
  }

  function money(x) {
    const n = Math.round(x);
    return (n < 0 ? "-$" : "$") + Math.abs(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  }

  root.EconProto = {
    GROUPS, GROUP_ORDER, POLICY_FIELDS, CITIES, CITY_BY_ID, CFG,
    INFRA_KEYS, buildCost, newSession, processTick, forecast, stars, debt, netBudget,
    pickEvent, eventCard, resolveChoice, headline, quote, describeEffects, aggregate, money, clone,
  };
})(typeof window !== "undefined" ? window : globalThis);
