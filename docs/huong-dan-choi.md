# Econ City How-To Play Guide

## What is Econ City

You serve as the mayor of a city over a span of 24 months. Your job is to plan land use, construct buildings, and set tax rates so that citizens have jobs, live happily, and the city does not run out of money.

- Your plot of land is a 12 x 12 grid with a pre-existing entrance called the **GATE**.
- You start with **$10,000** and a **20%** tax rate.
- Each month lasts 20 seconds, making a full game approximately 8 minutes long. You can pause at any time.
- Completing 24 months marks the **end of your term**. If your budget drops below **-$5,000**, the city goes **bankrupt** and the game ends early.

Your final score is calculated based on the number of citizens who are both employed and happy, plus any remaining funds in the budget. Simply building a large amount of housing will not yield a high score.

## Main Screen Overview

Everything you need to monitor is located in the four corners of the screen, with your city in the center.

![Screen at the start of a new game](img/man-hinh-chinh.jpg)

*Main screen at the start of a new game. Image taken during a test run in Roblox Studio, which includes extra buttons like "Demo build bot", "Tick now", and yellow text that you will not see during actual gameplay.*

| Location | Component | Description |
| --- | --- | --- |
| Top Left | City Card | View the current month (e.g., Month 7 / 24) and four key metrics: Budget, Population, Jobs, Happiness |
| Top Left, Below | How to Play & Alerts Card | Follow the first 5 steps; read warning alerts when the city encounters issues |
| Top Right | Main Buttons | START, PAUSE, RESUME; changes to NEW GAME when the match ends |
| Top Right | History, Leaderboard, Class, Build | Open monthly charts, scoreboards, join a teacher's class, or toggle the Build panel |
| Right Side | Build Panel | Select land categories and building templates, click **i** for details, adjust the Tax slider |
| Bottom Left | Stats Bar | Incoming Population, Occupied Jobs, Services, Goods for Shops |
| Bottom Right | + and − Buttons, Walk Button | Zoom in/out; explore your city on foot using WASD or joystick controls |

You can still build while walking: select a template and click on a tile. On mobile devices, swiping rotates the camera, while a soft tap places a building.

## First 5 Steps

A new game always starts in a paused state, allowing you to build before clicking START. The How to Play card will mark off each step as you complete it.

1. **Drag roads from the GATE into the grid.** Select the **GT** (Transit) tile, click and hold on the GATE tile, then drag inward. Each road tile costs $50, with a maximum of 24 tiles per drag.
2. **Build houses adjacent to roads.** Select **RES** (Residential land), pick the **House** template, and click an empty tile next to a road.
3. **Build workplaces.** Office buildings function independently. Shops require an accompanying factory to supply goods for sale.
4. **Add parks, schools, or hospitals** to keep citizens happy.
5. **Click START.** Time will begin running, and citizens will gradually move in.

All buildings must be adjacent to a road tile connected back to the GATE to function. Unconnected buildings display red diagonal stripes and an **!** icon, generate no residents or revenue, but still incur maintenance costs.

**Recommended starting layout** (fits within the $10,000 budget):

| Building | Quantity | Cost | Output / Capacity |
| --- | --- | --- | --- |
| Road | ~5 tiles | $250 | Connects everything to GATE |
| House | 2 | $1,200 | 80 housing capacity |
| Office | 1 | $3,000 | 20 job capacity |
| Shop | 1 | $1,600 | 20 job capacity |
| Factory | 1 | $1,200 | 30 job capacity, supplies goods for shop |
| Park | 1 | $1,800 | Serves 100 residents |
| **Total** | | **$9,050** | Remaining budget: $950 |

With this setup, the city will reach around 80 residents after a few months and begin generating a profit. You can then use net income to gradually expand.

## Building Types

There are 8 land types, each represented by a color and a code on the Build panel. Housing provides living space, shops/factories/offices provide jobs and revenue, while health, education, and greenery keep citizens happy.

| Land Type | Template | Size | Build Cost | Maint./Month | City Contribution |
| --- | --- | --- | --- | --- | --- |
| RES - Residential | House | 1x1 | $600 | $10 | 40 housing spaces |
| RES - Residential | Small House | 1x1 | $350 | $6 | 20 housing spaces |
| RES - Residential | Apartment | 2x2 | $3,000 | $60 | 200 housing spaces |
| COM - Commercial | Shop | 1x1 | $1,600 | $60 | 20 jobs, $105/worker, requires goods |
| COM - Commercial | Cafe | 1x1 | $900 | $35 | 10 jobs, $100/worker, requires goods |
| COM - Commercial | Supermarket | 2x2 | $7,000 | $260 | 90 jobs, $110/worker, requires goods |
| IND - Industrial | Factory | 1x1 | $1,200 | $80 | 30 jobs, $55/worker |
| IND - Industrial | Small Workshop | 1x1 | $700 | $45 | 15 jobs, $55/worker |
| IND - Industrial | Large Factory | 2x2 | $5,000 | $320 | 130 jobs, $58/worker |
| OFF - Office | Office | 1x1 | $3,000 | $100 | 20 jobs, $160/worker |
| OFF - Office | Small Office | 1x1 | $1,500 | $55 | 10 jobs, $155/worker |
| OFF - Office | Office Tower | 2x2 | $14,000 | $420 | 90 jobs, $170/worker |
| HEA - Healthcare | Hospital | 1x1 | $2,400 | $120 | 10 service points, 20 jobs |
| HEA - Healthcare | Clinic | 1x1 | $1,200 | $60 | 5 service points, 8 jobs |
| EDU - Education | School | 1x1 | $2,000 | $100 | 10 service points, 20 jobs |
| EDU - Education | Large School | 2x2 | $7,000 | $350 | 40 service points, 80 jobs |
| PRK - Greenery | Park | 1x1 | $1,800 | $100 | 5 service points |
| PRK - Greenery | Large Park | 2x2 | $6,000 | $360 | 22 service points |
| TRN - Transit | Road | 1x1 | $50 | $0 | Connects buildings to GATE |

"$105/worker" represents the monthly revenue generated per employed worker. The city collects taxes on this revenue. Each service point satisfies up to 20 residents.

- **Shops** generate high revenue but require goods. Every factory worker produces enough stock to supply one shop retail worker.
- **Factories** are inexpensive and offer many jobs, but revenue per worker is lower.
- **Offices** are expensive, but yield the highest revenue per worker without dependencies. Very useful when grid space becomes limited.
- **Hospitals and schools** boost happiness while creating employment. **Parks** do not require staff.
- **Small templates** are cheap and suitable for low-budget starts. **2x2 templates** are costly but yield higher profit per tile, ideal for mid-to-late game when money is abundant and space is tight.
- 2x2 templates are anchored by their top-left tile; all 4 tiles must be empty and within grid boundaries.
- **Demolition** refunds 50% of the construction cost. Use the **DEM** tool, or select a building and press the Demolish button twice. Demolishing roads may disconnect adjacent structures.

Click the **i** button next to any template to inspect its metrics before building.

## Monthly Calculations

Citizens only move in if jobs are available and the city maintains sufficient happiness. Each month, calculations run in the following sequence:

1. **Population influx or exit.** Desired incoming population equals total job capacity multiplied by city attractiveness, capped by available housing. Population adjusts halfway toward this target each month.
2. **Workforce allocation.** If population exceeds available jobs, unemployment occurs. Employment rate reflects the percentage of employed citizens.
3. **Business revenue generation.** Shops only earn revenue up to the quantity of stock supplied by factories.
4. **Tax collection & maintenance payments.** Tax Revenue = Total Business Revenue x Tax Rate. Maintenance costs apply to all structures, including unconnected ones.
5. **Happiness score updates** based on employment rates, tax burden, and service coverage. This score determines population movement for the following month.

![Each month is a cycle: citizens move in, work, pay taxes, and you build more](img/vong-moi-thang.png)

You stand at the "You build more" phase: every construction action or tax adjustment feeds back into the loop, impacting population in subsequent months.

**City Attractiveness** depends on the previous month's happiness rating:

| Previous Month Happiness | Desired Population Growth |
| --- | --- |
| Below 50 | No incoming residents |
| 50 to 75 | Gradually increases based on happiness |
| 75 and above | Maximum capacity, equal to 1.2x total job slots |

Highly happy cities attract more residents than available jobs. This leads to unemployment, which lowers happiness, causing the city to self-regulate.

**Happiness** (scale of 0 to 100) is calculated as follows:

```
H = 0.35E + 0.45(100 - 2T) + 0.20S
```

- E represents employment rate (%).
- T represents tax rate (%). Higher taxes decrease happiness.
- S represents service coverage rate (%). Each service point covers 20 citizens.

Example: A city has 400 citizens, 1 hospital, and 1 park. These structures provide 15 service points, covering 300 residents (S = 75%). With E = 100% and T = 20%, happiness equals 35 + 27 + 15 = 77.

## Taxation

A tax rate around 30% generally yields optimal results. Excessively low taxes lead to funding shortages for construction. Excessively high taxes drive citizens away, reducing net revenue.

- Adjust the **Tax** slider at the bottom of the Build panel between 0% and 50%. Changes take effect starting the next month.
- The indicator reading "Monthly: tax income ..., maintenance ..." below the slider reflects net profit or loss.

The table below illustrates how tax rates impact happiness and incoming population interest. This scenario assumes full employment (E = 100) and 75% service coverage (S = 75).

| Tax Rate | Happiness | Desired Population relative to Job Slots |
| --- | --- | --- |
| 20% | 77 | 120% |
| 30% | 68 | 86% |
| 40% | 59 | 43% |
| 50% | 50 | 0% (No new residents) |

Raising taxes from 30% to 40% increases individual tax contributions, but cuts prospective resident interest in half, resulting in lower total tax collection. In economics, this dynamic is known as the **Laffer Curve**.

![Taxes around 30% yield the highest score; too low or too high reduces performance](img/diem-theo-thue.png)

*Test bot scores under game rules using a balanced strategy across 7 tax levels.*

You can test this yourself: run two separate games using different tax rates, then compare their performance graphs in the History tab.

## Game Completion & Scoring

A game concludes after 24 months ("Term Complete!") or if your budget falls below -$5,000 ("City Bankrupt"). Minor budget deficits are tolerated, but construction is disabled while negative.

**Score** is calculated as follows, rounded to the nearest integer (minimum 0):

```
Score = (Employed Population x Happiness / 100) + (Budget / 100)
```

Example: Ending a game with 70 employed citizens, 78 happiness, and a $24,876 budget yields a score of (70 x 78 / 100) + (24,876 / 100) = 54.6 + 248.76 = 303.36, rounding to 303.

Unemployed citizens contribute nothing to the final score. Building excess housing without providing corresponding jobs offers no benefit.

- **Summary Screen** displays final score, records, and performance metrics. You can select NEW GAME, View History, or Explore City. Matching or surpassing your previous high score triggers a "New Record!" banner.
- **History** plots monthly trends for budget, business revenue, happiness, employment rate, and population. Use it to analyze downturns and identify root causes.
- **Leaderboards** feature two tabs: Global and My Class. High scores are saved individually and update every 2 turns.

## Classroom Integration

Teachers provide a 6-character invitation code. Joining a class allows your teacher to monitor city development.

1. Click **Class** in the top right corner.
2. In the **Join Class** section, enter the invitation code (e.g., QZ7K2M) and click **Join**.
3. The class will appear under **My Class**, displaying the teacher's name.
4. If your teacher hosts a private server, click **Enter Classroom** to play alongside classmates.

Once enrolled, the My Class leaderboard tab ranks your performance against peers. Click **Leave Class** to unenroll.

Teachers can assign **events** to the entire class. Active events display their name and remaining duration on screen.

| Event | Impact | Duration |
| --- | --- | --- |
| Economic Recession | Revenue dropped to 70% | 4 months |
| Supply Chain Disruption | Factories produce half goods | 4 months |
| Pandemic | 2% monthly population drop, happiness reduced by 10 | 6 months |
| Material Inflation | Building costs +50%, maintenance +30% | 5 months |

Teachers can also construct custom scenarios with custom parameters.

## Tips and Common Issues

When city issues arise, warning alerts appear in the top left corner. Alerts do not cause immediate failure, but should be addressed promptly.

| Alert | Recommended Action |
| --- | --- |
| Negative Budget: Deficit active, construction disabled | Raise taxes slightly or demolish unused structures (50% refund) |
| Happiness below 50: Influx stopped | Lower taxes, add parks, schools, or hospitals |
| Employment below 80%: Job shortage | Build offices, shops, or factories; pause residential construction |
| Shop Stock Shortage: Needs more factories | Build additional factories or small workshops |

If building placement fails, review the red notification popup:

| Notification | Cause |
| --- | --- |
| Not enough money: Need ... | Construction cost exceeds budget. Wait a few months or select smaller templates |
| This tile is occupied | Choose an empty tile or demolish existing structures first |
| Apartment requires a 2x2 empty space | 2x2 structures require 4 open tiles relative to top-left anchor |
| ... extends beyond the grid boundary | 2x2 template placed too close to right or bottom edges |
| Road drag path crosses occupied tiles | Road path intersects an existing building, invalidating the drag |
| Maximum drag length is 24 tiles | Break long road lines into multiple segments |

**Strategy Tips:**

- Build job sites prior to expanding housing. Citizens move in for employment, not residential space alone.
- Maintain industrial job capacity equal to or greater than retail job capacity. Keep "Goods for Shops" on the stats bar at 100%.
- Provide 5 service points per 100 residents. One park supports 100 residents, while a hospital or school supports 200.
- Use PAUSE to plan layouts. Construction remains active while paused.
- Reserve 2x2 templates for mid-to-late game. Early purchases risk draining funds needed for initial job placement.
- Constructing shops without factories leads to bankruptcy due to inventory deficits.

## Post-Game Discussion Questions

After completing a match, open your History tab and evaluate the following economic concepts:

1. Why does adding residential housing fail to increase population on its own? What actually drives growth?
2. When you raise tax rates, how does monthly tax collection react over the subsequent 2–3 months? Are there scenarios where higher tax rates yield lower total revenue?
3. Hospitals, schools, and parks generate no direct revenue. Why is it still essential for a city to build them?
4. Why do shops rely on factories? Where do commercial goods originate in real-world supply chains?
5. During economic shocks like recessions or pandemics, which metrics drop first? What strategies help stabilize the city?
6. Offices cost nearly twice as much as basic shops. Under what circumstances does investing in office towers become advantageous?
7. If replaying the same scenario, what initial strategic adjustments would you implement, and why?