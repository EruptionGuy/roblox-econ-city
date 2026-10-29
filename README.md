# Econ City (Roblox)

An economic game for students. Each player acts as the mayor of a 12x12 tile city over 24 months: building houses, shops, factories, schools, hospitals, parks, and roads while setting their own tax rates. Citizens only move in if there are jobs available. If taxes are too high, citizens leave and tax revenue drops.

Other documentation:

- [docs/huong-dan-choi.md](docs/huong-dan-choi.md): Student gameplay guide
- [docs/luat-choi-moi.md](docs/luat-choi-moi.md): Game rules and formulas
- [PRODUCT.md](PRODUCT.md): Target audience and game purpose
- [DESIGN.md](DESIGN.md): UI guidelines

## Testing in Studio

1. Open Roblox Studio, select File > Open from File > `EconCity.rbxlx`.
2. Press Play (F5).
3. Select a building from the Build panel on the right, then click a tile on the map. To build roads, click and hold while dragging. Every building must have a road connection leading back to the GATE tile. Once you finish building, press START.

Each month lasts 20 seconds. In Studio, there are two extra buttons for quick testing: "Tick now" (immediately advances to the next month) and "Demo build bot" (an automated bot that builds using available funds).

- Testing multiplayer: Go to Test > Clients and Servers, select 2 players, and click Start.
- Testing mobile layout: Go to Test > Device.

When the game is unpublished, data is stored temporarily and lost when you close the game (look for the yellow "Test mode" message). If Studio has API access enabled, test data is saved to data stores with the `_Studio` suffix, keeping it separate from real student data.

## Editing the Code

You can edit files directly inside Studio, but for team development, it is recommended to edit files in `src/` using VS Code and synchronize them to Studio using Rojo:

1. Install Rojo (`brew install rojo`) and the Rojo plugin in Studio.
2. Run `rojo serve` in this directory, then click Connect in the plugin.
3. Edit `.luau` files, and Studio will update automatically.
4. Rebuild the place file: `rojo build -o EconCity.rbxlx`. If you don't have Rojo, use `python3 tools/build_rbxlx.py EconCity.rbxlx`.

| Directory | Location in Game | Description |
|---|---|---|
| `src/shared/` | ReplicatedStorage.EconCity | Game rules, data, shared by both server and client |
| `src/server/` | ServerScriptService.EconCityServer | Data persistence, classrooms, leaderboards, administration |
| `src/client/` | StarterPlayerScripts.EconCityClient | User interface, 3D city, camera |
| `tests/` | | Tests running outside of Studio |
| `prototypes/luat-moi/` | | JavaScript version of the game rules, viewable in a browser |

The three most frequently edited files:

- `src/shared/Config.luau`: All numbers (prices, maintenance costs, job capacities, time limits, class limits, etc.).
- `src/shared/CityEngine.luau`: City mechanics and rules.
- `src/shared/GameTick.luau`: Events that occur every month.

## Testing

Requires Lua 5.3 or higher (`brew install lua`):

```
sh tests/run_all.sh
```

This command runs rule tests, server tests, a full simulation from start to finish (covering mouse, touch, and gamepad controls), and a balancing bot that compares its results against the JavaScript version.

## Balance Tuning

Balancing data exists in two places and must be kept identical: `src/shared/Config.luau` and `prototypes/luat-moi/engine.js`.

1. Update the numbers in both files.
2. Run `node prototypes/luat-moi/sim.js` to view the new score table.
3. Run `lua tests/balance_sim.lua --no-compare` to view the Luau version's table.
4. If everything looks good, copy the new JS table into `STRATS` in `tests/balance_sim.lua` so future tests can compare against it.

Changing the length of a month (`TICK_SECONDS`) does not affect game balance.

## Teachers

The game owner (or group owner) automatically acts as a teacher and administrator. Add other teachers using one of three methods:

- In-game: Class > Admin > Add teacher, then enter the Roblox username.
- Add the UserId to `TEACHER_USER_IDS` or `ADMIN_USER_IDS` in `Config.luau`.
- Set `TEACHER_GROUP_ID` and `TEACHER_GROUP_MIN_RANK`: anyone in the group at or above that rank becomes a teacher.

In Studio, everyone acts as a teacher for easier testing (`STUDIO_EVERYONE_IS_TEACHER`).

The game does not ask for emails, passwords, or real names. Teachers identify students by their Roblox display names. Chat is disabled. Class names and custom scenarios both pass through Roblox's text filter.

## Publishing to Roblox

1. File > Publish to Roblox.
2. Game Settings > Permissions: Set to Private while testing with your class.
3. Game Settings > Places > Max Players: Set to at least class size + 1 (for the teacher). The maximum is 61, as each class holds up to 60 students. Setting it lower will fill up private classrooms, preventing late-joining students from entering.
4. Creator Dashboard: Complete the Maturity & Compliance Questionnaire.
5. To test real data saving in Studio: Game Settings > Security > Enable Studio Access to API Services.

Private classrooms, data persistence, and cross-server leaderboards only function after the game is published.

Before letting students play:

- Students under 16 can only play if the game is part of the Roblox Kids and Select program. The publishing account must verify age and identity, enable 2-step verification, and pay registration fees (or hold Roblox Plus/Premium for 2+ months). The game must pass safety reviews: receiving 250 plays from age-verified users within 60 days, or paying 50,000 Robux for expedited review (refundable). Until then, only age-verified users 16+ can see the game.
- In Vietnam, Roblox is published by VNG and only officially licensed games are playable. You must complete regulatory procedures with VNG beforehand.

## Deleting Data upon Roblox Requests

Roblox sends data deletion requests (Right to be Forgotten) accompanied by a UserId. Go to Class > Admin > Delete all data, enter the UserId, and press it twice. This command deletes that person's data across all data stores:

| Data Store | Key | Content |
|---|---|---|
| `EconCity_Profiles_v1` | `u_<UserId>` | Player profile, active game, game history |
| `EconCity_Classes_v1` | `c_<CODE>` | Class members (`members["<UserId>"]`), class teachers |
| `EconCity_Scenarios_v1` | `t_<UserId>` | Teacher-created custom scenarios |
| `EconCity_Admin_v1` | `teachers`, `bans`, `log` | Teacher list, ban list, audit logs |
| `EconCity_LB_Global_v2`, `EconCity_LB_Class_v2_<CODE>` (Ordered) | `<UserId>` | Leaderboard scores |
| `EconCity_LB_Global_v1`, `EconCity_LB_Class_v1_<CODE>` (Ordered) | `<UserId>` | Legacy rule leaderboard scores (deprecated, still deleted) |
| MemoryStore `EconCity_ClassLive_v1` | `u_<UserId>` | Live progress (auto-expires after 2 minutes) |

## Pending Work

- New balancing has only been tested with bots, not yet with real students.
- Ongoing games using legacy rules cannot be continued; re-entering will start a new game session. Legacy game histories remain accessible.
- Private classrooms, MessagingService, MemoryStore, Ban API, and username lookup have only been tested via simulations, not yet on a published live game.
- City grid performance on low-end mobile devices has not yet been fully optimized and tested.