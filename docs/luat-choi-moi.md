# Econ City Game Rules: Grid-Based City Builder (Finalized)

Based on `Proposal Econ City.docx`. Maintains the original framework (8 building types, grid structure, roads, tax rates, employment/happiness formulas) while resolving missing details and inconsistencies. All figures have been tested via [prototypes/luat-moi/sim.js](../prototypes/luat-moi/sim.js) (Section 10). Playable prototype: [prototypes/luat-moi/index.html](../prototypes/luat-moi/index.html) (open directly in a browser), with rules defined in [engine.js](../prototypes/luat-moi/engine.js) and verified using `node prototypes/luat-moi/check.js`.
The Roblox game (`src/`, version 0.2) uses these exact rules; `tests/balance_sim.lua` cross-checks every single figure of the Luau version against the JS version.

## 1. Modifications & Rationale vs. Proposal

| # | Proposal | Finalized Decision | Rationale |
|---|---|---|---|
| 1 | Happiness ($H$) was purely cosmetic | $H$ determines **citizen migration (arrival/departure)** (Section 4, Step 3) | Without $H$ impact, a 100% tax rate is always optimal, rendering hospitals/schools/parks a waste of money |
| 2 | $H = 0.35E + 0.15(100 - T) + 0.50S$, taxes 0–100% | **$H = 0.35E + 0.45(100 - 2T) + 0.20S$**, taxes 0–50% | With a 0.15 weight, $H$ could still reach 85 at a 100% tax rate, meaning taxes carried almost no penalty |
| 3 | Population = $\sum$ capacities | Citizens **arrive for jobs**: target population = jobs $\times$ attractiveness, capped by housing capacity | If population filled housing based purely on $H$, building excess cheap housing would entirely offset high taxes |
| 4 | No population means $E = 0\%$ | No population means $E = 100\%$ (zero unemployment); UI displays "—" | If $E = 0$, a brand new city has low $H$ and would never attract anyone |
| 5 | $S = \min(100, 10\cdot\text{Hosp} + 5\cdot\text{Park} + 10\cdot\text{School})$ | Retains point values 10/5/10, but $S = \mathbf{\% \text{ of population served}}$, with each point serving 20 citizens | Under the proposal, 10 hospitals maxed out $S$ regardless of whether the city had 10 or 10,000 residents |
| 6 | Random worker allocation | **Proportional allocation**: uniform shortage rates across all workplaces | Stable outcomes, intuitive for students, and testable |
| 7 | "Factories supply goods to shops" without formula | Implements goods formula $G$ (Section 4, Step 5) | Gives distinct, meaningful roles to shops, factories, and offices |
| 8 | "Connecting roads" undefined | Must connect continuously to the **gate tile** at the map edge | If adjacent to any road tile were enough, roads would lose their strategic purpose |
| 9 | $\sum\text{capacities} / \sum\text{jobs}$ included unconnected buildings | Counts **connected** buildings only | The proposal conflicted directly with the rule "all buildings must be connected to roads to function" |
| 10 | Missing duration, win/loss conditions, demolition, scoring, and events | Fully defined (Sections 5–8) | |

## 2. Map and Roads

- **12 × 12 grid**. Standard and small templates occupy **1 tile**, large templates occupy **2 × 2 tiles** (Section 3), rotation is not supported.
  2×2 templates are placed using their top-left tile, expanding right and downward; they must fit entirely within the grid and all 4 tiles must be empty.
- **Gate tile**: A pre-placed road tile in the middle of the bottom edge (column 6, row 12). Indestructible.
- **Connected road tile** = a road tile reachable from the gate tile through contiguous adjacent road tiles (up/down/left/right, diagonals excluded).
- **Connected building** = has at least one adjacent tile (in 4 directions) that is a connected road tile. For 2×2 templates: only one of its 4 tiles needs such adjacency.
- Unconnected building: houses no residents, hires no workers, generates no revenue or service points, **still incurs maintenance costs**.

## 3. Buildings

Buildings have substantial capacities (housing 40, workplaces 20–30) so that each match requires placing roughly 90 structures.

| Type | Build Cost | Maint./Month | Workplaces | Revenue / Worker / Month | Housing Capacity | Service Points |
|---|---|---|---|---|---|---|
| House | \$600 | \$10 | - | - | 40 | - |
| Shop | \$1,600 | \$60 | 20 | \$105 (requires goods, see $G$) | - | - |
| Factory | \$1,200 | \$80 | 30 | \$55 | - | - |
| Office | \$3,000 | \$100 | 20 | \$160 | - | - |
| Hospital | \$2,400 | \$120 | 20 | \$0 | - | 10 |
| School | \$2,000 | \$100 | 20 | \$0 | - | 10 |
| Park | \$1,800 | \$100 | - | - | - | 5 |
| Road | \$50 | \$0 | - | - | - | - |

Each type serves a distinct role:
- **Shops**: Decent revenue per worker, but generate nothing without factory goods.
- **Factories**: Inexpensive, high job capacity, lower revenue per worker, supplies goods to shops.
- **Offices**: Expensive, highest revenue per worker, independent, requires the fewest land tiles per dollar of revenue. Highly advantageous late-game when grid space is tight.
- **Hospitals & Schools**: Provide service points while creating jobs.
- **Parks**: Require no workforce.

### Building Templates

Each land type offers a standard template (table above), a 1×1 small template, and (except healthcare and roads) a 2×2 large template. Templates inherit characteristics of their parent category (e.g., apartment is housing, supermarket is a shop requiring goods, clinic is a hospital):

| Template | Type | Size | Build Cost | Maint./Month | Workplaces | Revenue / Worker / Month | Housing Capacity | Service Points |
|---|---|---|---|---|---|---|---|---|
| Small House | House | 1 | \$350 | \$6 | - | - | 20 | - |
| Apartment | House | 2×2 | \$3,000 | \$60 | - | - | 200 | - |
| Cafe | Shop | 1 | \$900 | \$35 | 10 | \$100 | - | - |
| Supermarket | Shop | 2×2 | \$7,000 | \$260 | 90 | \$110 | - | - |
| Small Workshop | Factory | 1 | \$700 | \$45 | 15 | \$55 | - | - |
| Large Factory | Factory | 2×2 | \$5,000 | \$320 | 130 | \$58 | - | - |
| Small Office | Office | 1 | \$1,500 | \$55 | 10 | \$155 | - | - |
| Office Tower | Office | 2×2 | \$14,000 | \$420 | 90 | \$170 | - | - |
| Clinic | Hospital | 1 | \$1,200 | \$60 | 8 | \$0 | - | 5 |
| Large School | School | 2×2 | \$7,000 | \$350 | 80 | \$0 | - | 40 |
| Large Park | Park | 2×2 | \$6,000 | \$360 | - | - | - | 22 |

Template Balancing (verified via `tests/engine_spec.lua` and `tests/balance_sim.lua`):
- **Small templates** are cheap, ideal for early-game low budgets, but yield lower profit per tile. A bot using only small templates scored 1,336 points, compared to 2,155 for standard templates.
- **Large templates** are costly, but their profit (or housing/service-to-maintenance ratio) per tile is **10–30% higher**: a reward for crowded grids, though not so overpowered that spamming large templates alone guarantees a win.
- The JS prototype (`prototypes/luat-moi/`) and Section 10 tables use standard templates exclusively; the Luau version matches every single figure with the JS build for those templates.
- The "Demo build bot" only builds large templates once the city has residents and retains enough funds to cover the template cost: scoring 2,235 points (vs 2,155 for standard). Forcing the bot to buy large templates immediately upon affording them leads it to buy apartments + large parks at month 0, running out of funds for workplaces and going bankrupt by month 14; purchasing them once profitable yields only 1,587 points due to excess housing and service capacity. Lesson for players: large templates are mid-to-late-game tools for when funds are abundant and space is restricted.

## 4. Monthly Simulation Cycle

Each month = 1 turn, lasting 20 seconds (retaining current `TICK_SECONDS`). Calculations run in exact sequence:

1. **Road Connection**: Flood-fill search from the gate tile, marking connected structures.
2. **Capacity and Employment** (connected structures only):
   $C = \sum \text{housing capacity}$, $J = \sum \text{workplaces (shops, factories, offices, hospitals, schools)}$.
3. **Citizen Migration**, using $H$ from the **previous month**:
   ```
   P = \min(P, C)                                         // demolished/disconnected housing forces immediate departures
   attractiveness = 1.2 \times \text{clamp}\left(\frac{H_{\text{prev}} - 50}{25}, 0, 1\right)      // H \le 50: no arrivals; H \ge 75: maximum
   P_{\text{target}} = \min(C, \lfloor J \times \text{attractiveness}\rfloor)
   P moves halfway toward P_{\text{target}} each month (rounded up to ensure progress)
   ```
   A multiplier of 1.2 means highly attractive cities draw more residents than available jobs, spawning unemployment and pulling $H$ back down. This loop self-regulates.
4. **Employment**: $\text{employed} = \min(P, J)$, $f = \text{employed} / J$ ($0$ if $J = 0$). All workplaces experience an identical employment ratio $f$.
   $E = (\text{employed} / P) \times 100$ ($P = 0$ implies $E = 100$).
5. **Goods**: $G = \min\left(1, \frac{\sum\text{factory jobs}}{\sum\text{shop jobs}}\right)$ ($G = 1$ if no shops exist).
   Meaning 1 factory worker produces enough goods for 1 shop worker.
6. **Base Revenue**:
   $R = f \times (\sum\text{shop jobs} \times 105 \times G + \sum\text{factory jobs} \times 55 + \sum\text{office jobs} \times 160)$
7. **Budget**: $\text{tax collected} = R \times T / 100$, $\text{maintenance} = \sum \text{maintenance of ALL structures (including unconnected)}$,
   $\text{budget} += \text{tax collected} - \text{maintenance}$.
8. **Services**: $\text{points} = 10 \times \text{hospitals} + 10 \times \text{schools} + 5 \times \text{parks}$ (connected structures only, independent of staffing).
   $S = \min\left(100, \frac{\text{points} \times 20}{P} \times 100\right)$ ($P = 0$ implies $S = 100$). Example: 400 citizens, 1 hospital + 1 park = 15 points, serving 300 people, giving $S = 75$.
9. **Happiness**: $H = \text{clamp}(0.35E + 0.45(100 - 2T) + 0.20S + \text{event penalty}, 0, 100)$. Saved as $H_{\text{prev}}$ for next month.
10. **Alerts, History, Scoring, Win/Loss Conditions** (Sections 6–9).

**Tax Lesson Example (Laffer Curve):** Assume $E = 100$ and $S = 75$.
- At 30% tax: $H = 35 + 18 + 15 = 68$, attractiveness 0.86.
- At 40% tax: $H = 59$, attractiveness 0.43: half the workforce leaves, causing total tax revenue to **drop** despite the higher tax rate.

## 5. Player Actions

- **New Game**: Month 0, budget \$10,000, 20% tax, empty grid except gate tile, **paused**. Players build first, then press Play.
  Initial $H$ calculated with $P = 0$: $35 + 27 + 20 = 82$.
- **Building**: Allowed exclusively on empty tiles (2×2 templates require all 4 tiles empty and within grid bounds) when budget $\ge$ cost. Funds are deducted immediately, taking effect next tick. Available during both play and pause; disabled after game over.
- **Road Dragging**: A single drag action submits a request of up to 24 tiles. Existing road tiles are skipped. If an occupied tile is encountered or funds are insufficient for the entire span, **the entire drag is rejected**. Rationale: current rate-limiting restricts inputs to 8 requests.
- **Demolition**: Available for anything except the gate tile, refunding **50% of construction cost**. Clicking any tile of a 2×2 structure demolishes the entire building.
  Demolishing roads may disconnect adjacent buildings. Two methods: Demolish tool (DEL), or the Demolish button in the building inspection card (requires two clicks to confirm).
- **Inspection Card**: The "i" button next to each template in the Build panel opens a card displaying 3D rendering, cost, footprint, housing/workplaces, revenue per worker, service points, maintenance, and a SELECT TO BUILD button. Clicking an existing structure (when no tool is selected) opens its status card.
- **Walk Mode**: Building remains possible while exploring on foot. On touch screens, swiping rotates the camera, so gentle taps are required to place buildings.
- **Taxes**: Range 0–50%, in 1% increments. Adjustable at any time, taking effect next tick.
- **Server Validation**: Verifies validity of building types, integer grid coordinates, empty tiles, sufficient funds, and active game state.

## 6. Winning, Losing, and Scoring

- **Duration**: **24 months**, roughly 8 minutes if unpaused.
- **Loss**: Budget $< -\$5,000$ (retaining `FAIL_BUDGET`). Negative budgets are permitted to cover maintenance, but construction is locked while negative. The loss condition for population $< 30$ is removed since population starts at 0.
- **Win**: Reaching month 24 without losing.
- **Score** (leaderboard, keeping highest score): $\text{score} = \max\left(0, \text{round}\left(\frac{\text{employed} \times H}{100} + \frac{\text{budget}}{100}\right)\right)$.
  Concept: Measures employed, happy citizens plus financial health. Building excess housing to host unemployed residents yields no score.

## 7. Alerts (Informational Only, No Loss Penalty)

| Code | Condition | Player Meaning |
|---|---|---|
| `BUDGET` | Budget $< 0$ | Operating at a loss, construction disabled |
| `HAPPINESS` | $H < 50$ | No one wants to move in |
| `UNEMPLOYMENT` | $P > 0$ and $E < 80$ | Labor shortage |
| `SHORTAGE` | Shops exist and $G < 0.7$ | Shop inventory shortage, more factories needed |

## 8. Teacher Events

Replaces the 11 legacy effects (tied to demographic groups and infrastructure levels which are no longer used) with 6 new effects. These also serve as the suite for custom scenarios.

| Effect | Target | Range (Step) | Multi-Event Aggregation |
|---|---|---|---|
| Revenue Multiplier | $R$ in Step 6 | 0.5–1 (0.05) | Multiplicative |
| Maintenance Multiplier | Maintenance in Step 7 | 1–2 (0.1) | Multiplicative |
| Construction Cost Multiplier | Build cost | 1–2 (0.1) | Multiplicative |
| Goods Multiplier | Factory output in Step 5 | 0.2–1 (0.1) | Multiplicative |
| Happiness Penalty | $H$ in Step 9 | -30 to 0 (1) | Additive |
| Monthly Population Flight | $P$ after Step 3: $P -= \text{round}(P \times \text{rate})$ | 0–5% (0.5%) | Maximum value |

4 Pre-configured Events (tested, see Section 10):

| Event | Effect | Duration |
|---|---|---|
| Economic Recession | Revenue $\times 0.7$ | 4 months |
| Supply Chain Disruption | Goods $\times 0.5$ | 4 months |
| Pandemic | Population flight 2%/month, Happiness -10 | 6 months |
| Material Inflation | Build cost $\times 1.5$, Maintenance $\times 1.3$ | 5 months |

## 9. History and Class Reporting

Monthly records: Month, Budget, **Base Revenue $R$** (replacing GDP), Happiness, **Employment Rate $E$** (replacing inflation), Population.
Class CSV exports and history charts use these exact 6 columns.

Developer Tip: Keep the internal field name `gdp` for $R$ to minimize changes across ClassroomService, CSV export, and charts. Leaderboards must migrate to a new data store (`_v2`), as legacy scores are incompatible with the new scoring model.

## 10. Simulation Evidence

Tested via `node prototypes/luat-moi/sim.js`. Test bots played strictly through `engine.js` on an actual grid: a vertical road axis from the gate plus 4 horizontal road rows, comprising 89 building tiles and 55 road tiles. Each bot maintained a fixed strategy and constant tax rate across all 24 months. Final score table (F24 = bankrupted by month 24):

| Strategy | 10% | 20% | 25% | **30%** | 35% | 40% | 50% |
|---|---|---|---|---|---|---|---|
| Balanced (shop + factory + office, $S \ge 60$) | 157 | 905 | 1789 | **2155** | 2078 | 1582 | 76 |
| Office Only | 116 | 738 | 1558 | **2373** | 2236 | 1131 | 67 |
| Shop + Factory | 171 | 943 | 1811 | **2043** | 1963 | 1535 | 76 |
| Factory Only | 162 | 739 | 1244 | **1412** | 1330 | 983 | 70 |
| Shop Only (No Factories) | F24 | F24 | F24 | F24 | F24 | F24 | F24 |
| No Public Services | 204 | 182 | 99 | 25 | 20 | 9 | 0 |
| High Services ($S \ge 90$) | 153 | 798 | 1659 | **2576** | 2277 | 1254 | 66 |
| Excess Housing (capacity = $2\times$ jobs) | 135 | 614 | 1245 | 1517 | 1423 | 981 | 55 |

Conclusions:
- **Optimal tax rate is around 30%.** Rates below 15% starve the city of development funds. Rates of 40% and above drive citizens away.
- **No single building type dominates.** Offices, shop+factory combos, and balanced setups perform competitively. Relying solely on shops leads to bankruptcy.
- **Public services are worth the investment.** Eliminating public services strips the city of population. Heavy investment in services yields top scores.
- **Spamming excess housing is no longer a loophole.**
- 3,000 randomized strategies (varying building mixes, service types, tax rates): the 6 top-performing strategies all blended all 3 workplace types, utilized comprehensive hospital/school/park coverage, and set tax rates between 28% and 39%. 67 out of 3,000 went bankrupt.
- Initial simulation drafts assumed each structure consumed half a road tile. Running on the actual grid shifted scores by under 5%, preserving all qualitative conclusions.
- **Events** (applied to the balanced bot at month 6 or 12, tax rate 25–30%): scores dropped 8–12% for supply chain disruption, 13–18% for recession, 17–22% for inflation, and 24–28% for pandemic. Zero bots went bankrupt.

## 11. Areas Pending Real Player Testing (Prototype Testing)

- Under the balanced strategy at a 30% tax rate, the grid fills up around **month 20**, leaving the final 4 months dedicated strictly to tax adjustments. If this feels repetitive, expand the grid to 13×13 or reduce revenue by roughly 10%.
- Demolition refund rates and early-game pacing under the default 20% tax rate: bots cannot evaluate these subjective player experiences.
- Action count per match (roughly 90 buildings + road dragging) needs validation with real students, particularly on mobile devices and gamepads.