# Crafting Station System

**Resource**: dps-towjob
**Date**: 2025-12-30

---

## Overview

Each tow depot has a crafting station where tow drivers can craft roadside repair items. This integrates with qs-inventory's crafting system.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      CRAFTING SYSTEM OVERVIEW                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                         ┌─────────────────────┐                             │
│                         │   MATERIAL SOURCES  │                             │
│                         └──────────┬──────────┘                             │
│                                    │                                        │
│              ┌─────────────────────┼─────────────────────┐                  │
│              │                     │                     │                  │
│              ▼                     ▼                     ▼                  │
│    ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐         │
│    │   SCAVENGING    │   │   PURCHASING    │   │    TRADING      │         │
│    │  (PVE Tows)     │   │  (Stores)       │   │  (Other Players)│         │
│    │                 │   │                 │   │                 │         │
│    │  30% chance to  │   │  Buy basic      │   │  Trade with     │         │
│    │  find materials │   │  materials      │   │  mechanics      │         │
│    └────────┬────────┘   └────────┬────────┘   └────────┬────────┘         │
│             │                     │                     │                  │
│             └─────────────────────┼─────────────────────┘                  │
│                                   │                                        │
│                                   ▼                                        │
│                     ┌─────────────────────────┐                            │
│                     │   PLAYER INVENTORY      │                            │
│                     │   (Raw Materials)       │                            │
│                     │                         │                            │
│                     │  metalscrap, rubber,    │                            │
│                     │  plastic, copper_wire,  │                            │
│                     │  steel, adhesive, etc.  │                            │
│                     └───────────┬─────────────┘                            │
│                                 │                                          │
│                                 ▼                                          │
│                     ┌─────────────────────────┐                            │
│                     │    CRAFTING STATION     │                            │
│                     │    (Tow Depot)          │                            │
│                     │                         │                            │
│                     │  Check grade for tier   │                            │
│                     │  Consume materials      │                            │
│                     │  Roll success chance    │                            │
│                     └───────────┬─────────────┘                            │
│                                 │                                          │
│                   ┌─────────────┼─────────────┐                            │
│                   │             │             │                            │
│                   ▼             ▼             ▼                            │
│          ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                   │
│          │  SUCCESS    │ │   FAIL      │ │  PARTIAL    │                   │
│          │             │ │             │ │  (75-99%)   │                   │
│          │ Item added  │ │ Materials   │ │ Some mats   │                   │
│          │ to inventory│ │ lost        │ │ returned    │                   │
│          └─────────────┘ └─────────────┘ └─────────────┘                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Tier Progression System

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CRAFTING TIER PROGRESSION                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  TIER 1 ─ BASIC                    TIER 2 ─ INTERMEDIATE                   │
│  Grade 0+ (All Drivers)            Grade 2+ (Senior Driver)                │
│  ┌───────────────────────┐         ┌───────────────────────┐               │
│  │                       │         │                       │               │
│  │  ┌─────────────────┐  │         │  ┌─────────────────┐  │               │
│  │  │  repair_kit     │  │         │  │tyre_replacement │  │               │
│  │  │  100% success   │  │         │  │  95% success    │  │               │
│  │  └─────────────────┘  │         │  └─────────────────┘  │               │
│  │                       │         │                       │               │
│  │  ┌─────────────────┐  │         │  ┌─────────────────┐  │               │
│  │  │   duct_tape     │  │         │  │advancedrepairkit│  │               │
│  │  │  100% success   │  │         │  │  90% success    │  │               │
│  │  └─────────────────┘  │         │  └─────────────────┘  │               │
│  │                       │         │                       │               │
│  │  ┌─────────────────┐  │         │  ┌─────────────────┐  │               │
│  │  │tyre_repair_kit  │  │         │  │ jumper_cables   │  │               │
│  │  │  100% success   │  │         │  │  100% success   │  │               │
│  │  └─────────────────┘  │         │  └─────────────────┘  │               │
│  │                       │         │                       │               │
│  └───────────────────────┘         └───────────────────────┘               │
│            │                                  │                             │
│            │          TIER 3 ─ ADVANCED       │                             │
│            │          Grade 4+ (Supervisor)   │                             │
│            │         ┌───────────────────────┐│                             │
│            │         │                       ││                             │
│            │         │  ┌─────────────────┐  ││                             │
│            └────────►│  │  electronickit  │  │◄──────────┘                  │
│                      │  │  85% success    │  │                              │
│                      │  └─────────────────┘  │                              │
│                      │                       │                              │
│                      │  ┌─────────────────┐  │                              │
│                      │  │    nitrous      │  │                              │
│                      │  │  75% success    │  │                              │
│                      │  └─────────────────┘  │                              │
│                      │                       │                              │
│                      │  ┌─────────────────┐  │                              │
│                      │  │    harness      │  │                              │
│                      │  │  90% success    │  │                              │
│                      │  └─────────────────┘  │                              │
│                      │                       │                              │
│                      └───────────────────────┘                              │
│                                                                             │
│  Legend: Higher tiers = better items but lower success chance              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Scavenging System

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        VEHICLE SCAVENGING FLOW                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                    ┌─────────────────────────┐                              │
│                    │  Driver completes PVE   │                              │
│                    │  tow (NPC vehicle)      │                              │
│                    └───────────┬─────────────┘                              │
│                                │                                            │
│                                ▼                                            │
│                    ┌─────────────────────────┐                              │
│                    │  Roll scavenge chance   │                              │
│                    │  (30% by default)       │                              │
│                    └───────────┬─────────────┘                              │
│                                │                                            │
│              ┌─────────────────┼─────────────────┐                          │
│              │                                   │                          │
│              ▼                                   ▼                          │
│    ┌─────────────────┐                 ┌─────────────────┐                  │
│    │    SUCCESS      │                 │     FAIL        │                  │
│    │    (30%)        │                 │     (70%)       │                  │
│    └────────┬────────┘                 └─────────────────┘                  │
│             │                                                               │
│             ▼                                                               │
│    ┌─────────────────────────────────────────────────────────────────┐     │
│    │            DETERMINE MATERIAL BY VEHICLE CLASS                   │     │
│    ├─────────────────────────────────────────────────────────────────┤     │
│    │                                                                  │     │
│    │   COMPACTS        SEDANS          SUVs           SPORTS         │     │
│    │   ┌─────────┐     ┌─────────┐     ┌─────────┐    ┌─────────┐   │     │
│    │   │ plastic │     │metalscrap│    │metalscrap│   │ aluminum│   │     │
│    │   │ rubber  │     │ plastic │     │  steel  │    │electronic│  │     │
│    │   └─────────┘     │ rubber  │     │ rubber  │    │ rubber  │   │     │
│    │                   └─────────┘     └─────────┘    └─────────┘   │     │
│    │                                                                  │     │
│    │   MUSCLE          TRUCKS                                        │     │
│    │   ┌─────────┐     ┌─────────┐                                   │     │
│    │   │  steel  │     │  steel  │                                   │     │
│    │   │  iron   │     │  iron   │                                   │     │
│    │   │metalscrap│    │copper_wire│                                  │     │
│    │   └─────────┘     └─────────┘                                   │     │
│    │                                                                  │     │
│    └──────────────────────────────┬──────────────────────────────────┘     │
│                                   │                                        │
│                                   ▼                                        │
│                    ┌─────────────────────────┐                             │
│                    │  Random amount (1-3)    │                             │
│                    │  added to inventory     │                             │
│                    │                         │                             │
│                    │  "Found 2x metalscrap"  │                             │
│                    └─────────────────────────┘                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Crafting Station Locations

| Shop | Location | Access |
|------|----------|--------|
| LS Customs Burton | vec3(-339.0, -136.0, 39.0) | tow job only |
| Benny's Strawberry | vec3(-205.0, -1312.0, 31.0) | tow job only |
| LS Customs La Mesa | vec3(731.0, -1088.0, 22.0) | tow job only |
| Beeker's Paleto | vec3(110.0, 6626.0, 32.0) | tow job only |
| Hayes Auto | vec3(-1420.0, -450.0, 36.0) | tow job only |

---

## Craftable Items

### Tier 1 - Basic (No Grade Requirement)

| Item | Description | Materials | Time | Chance |
|------|-------------|-----------|------|--------|
| `repair_kit` | Basic vehicle repair | 2x metalscrap, 1x rubber, 1x duct_tape | 5s | 100% |
| `duct_tape` | Quick patch material | 1x plastic, 1x adhesive | 3s | 100% |
| `tyre_repair_kit` | Temporary tire patch | 1x rubber, 1x adhesive | 4s | 100% |

### Tier 2 - Intermediate (Grade 2+)

| Item | Description | Materials | Time | Chance |
|------|-------------|-----------|------|--------|
| `tyre_replacement` | Full spare tire | 3x rubber, 2x steel, 1x iron | 8s | 95% |
| `advancedrepairkit` | Better repairs | 3x metalscrap, 2x rubber, 1x plastic, 1x steel | 10s | 90% |
| `jumper_cables` | Battery jumpstart tool | 2x copper_wire, 1x rubber, 1x plastic | 6s | 100% |

### Tier 3 - Advanced (Grade 4+)

| Item | Description | Materials | Time | Chance |
|------|-------------|-----------|------|--------|
| `electronickit` | Electronic repairs | 2x electronic_components, 1x copper_wire, 1x plastic | 12s | 85% |
| `nitrous` | NOS system | 3x aluminum, 2x steel, 1x electronic_components | 15s | 75% |
| `harness` | Racing harness | 4x fabric, 2x steel, 1x plastic | 10s | 90% |

---

## Configuration (config/crafting.lua)

```lua
Config.Crafting = {
    enabled = true,

    -- Materials that tow drivers can gather from broken down vehicles
    scavengeEnabled = true,
    scavengeChance = 0.3, -- 30% chance per vehicle
    scavengeMaterials = {
        'metalscrap',
        'rubber',
        'plastic',
        'copper_wire'
    },

    -- Crafting stations per shop
    stations = {
        ['lscustoms_burton'] = {
            label = 'Tow Shop Workbench',
            coords = vec3(-339.0, -136.0, 39.0),
            job = 'tow',
            grades = 'all'
        },
        ['bennys_strawberry'] = {
            label = 'Tow Shop Workbench',
            coords = vec3(-205.0, -1312.0, 31.0),
            job = 'tow',
            grades = 'all'
        },
        ['lscustoms_lamesa'] = {
            label = 'Tow Shop Workbench',
            coords = vec3(731.0, -1088.0, 22.0),
            job = 'tow',
            grades = 'all'
        },
        ['beekers_paleto'] = {
            label = 'Tow Shop Workbench',
            coords = vec3(110.0, 6626.0, 32.0),
            job = 'tow',
            grades = 'all'
        },
        ['hayes_auto'] = {
            label = 'Tow Shop Workbench',
            coords = vec3(-1420.0, -450.0, 36.0),
            job = 'tow',
            grades = 'all'
        }
    }
}

-- Crafting recipes
Config.CraftingRecipes = {
    -- Tier 1: Basic
    [1] = {
        name = 'repair_kit',
        amount = 1,
        info = {},
        costs = {
            ['metalscrap'] = 2,
            ['rubber'] = 1,
            ['duct_tape'] = 1
        },
        type = 'item',
        slot = 1,
        time = 5000,
        chance = 100,
        minGrade = 0
    },
    [2] = {
        name = 'duct_tape',
        amount = 2,
        info = {},
        costs = {
            ['plastic'] = 1,
            ['adhesive'] = 1
        },
        type = 'item',
        slot = 2,
        time = 3000,
        chance = 100,
        minGrade = 0
    },
    [3] = {
        name = 'tyre_repair_kit',
        amount = 1,
        info = {},
        costs = {
            ['rubber'] = 1,
            ['adhesive'] = 1
        },
        type = 'item',
        slot = 3,
        time = 4000,
        chance = 100,
        minGrade = 0
    },

    -- Tier 2: Intermediate
    [4] = {
        name = 'tyre_replacement',
        amount = 1,
        info = {},
        costs = {
            ['rubber'] = 3,
            ['steel'] = 2,
            ['iron'] = 1
        },
        type = 'item',
        slot = 4,
        time = 8000,
        chance = 95,
        minGrade = 2
    },
    [5] = {
        name = 'advancedrepairkit',
        amount = 1,
        info = {},
        costs = {
            ['metalscrap'] = 3,
            ['rubber'] = 2,
            ['plastic'] = 1,
            ['steel'] = 1
        },
        type = 'item',
        slot = 5,
        time = 10000,
        chance = 90,
        minGrade = 2
    },
    [6] = {
        name = 'jumper_cables',
        amount = 1,
        info = {},
        costs = {
            ['copper_wire'] = 2,
            ['rubber'] = 1,
            ['plastic'] = 1
        },
        type = 'item',
        slot = 6,
        time = 6000,
        chance = 100,
        minGrade = 2
    },

    -- Tier 3: Advanced
    [7] = {
        name = 'electronickit',
        amount = 1,
        info = {},
        costs = {
            ['electronic_components'] = 2,
            ['copper_wire'] = 1,
            ['plastic'] = 1
        },
        type = 'item',
        slot = 7,
        time = 12000,
        chance = 85,
        minGrade = 4
    },
    [8] = {
        name = 'nitrous',
        amount = 1,
        info = {},
        costs = {
            ['aluminum'] = 3,
            ['steel'] = 2,
            ['electronic_components'] = 1
        },
        type = 'item',
        slot = 8,
        time = 15000,
        chance = 75,
        minGrade = 4
    },
    [9] = {
        name = 'harness',
        amount = 1,
        info = {},
        costs = {
            ['fabric'] = 4,
            ['steel'] = 2,
            ['plastic'] = 1
        },
        type = 'item',
        slot = 9,
        time = 10000,
        chance = 90,
        minGrade = 4
    }
}
```

---

## Vehicle Scavenging

Tow drivers can scavenge materials from broken-down NPC vehicles.

### Scavenge Mechanic
```lua
-- When driver completes PVE tow, chance to find materials
RegisterNetEvent('dps-towjob:server:completePVETow', function(vehicleData)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)

    if not Player then return end

    -- Check scavenge chance
    if math.random() <= Config.Crafting.scavengeChance then
        local material = Config.Crafting.scavengeMaterials[math.random(#Config.Crafting.scavengeMaterials)]
        local amount = math.random(1, 3)

        Player.Functions.AddItem(material, amount)
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Scavenged Materials',
            description = 'Found ' .. amount .. 'x ' .. material,
            type = 'success',
            duration = 3000
        })
    end
end)
```

### Scavengeable Items by Vehicle Class
| Vehicle Class | Possible Materials |
|---------------|-------------------|
| Compacts | plastic, rubber |
| Sedans | metalscrap, plastic, rubber |
| SUVs | metalscrap, steel, rubber |
| Sports | aluminum, electronic_components, rubber |
| Muscle | steel, iron, metalscrap |
| Trucks | steel, iron, copper_wire |

---

## Integration with qs-inventory

### Method 1: Native qs-inventory Crafting
```lua
-- Add to qs-inventory/config/crafting.lua
Config.CraftingTables[#Config.CraftingTables + 1] = {
    name = 'Tow Shop Workbench',
    isjob = 'tow',
    grades = 'all',
    text = '[E] - Craft Supplies',
    blip = {
        enabled = false -- Don't show public blip
    },
    location = vec3(-339.0, -136.0, 39.0),
    items = Config.CraftingRecipes -- Reference our recipes
}
```

### Method 2: Custom Export (Preferred)
```lua
-- client/crafting.lua
function OpenTowCrafting()
    local playerGrade = GetPlayerJobGrade()
    local availableRecipes = {}

    for _, recipe in ipairs(Config.CraftingRecipes) do
        if playerGrade >= recipe.minGrade then
            table.insert(availableRecipes, recipe)
        end
    end

    local items = exports['qs-inventory']:SetUpCrafing(availableRecipes)
    local crafting = {
        label = 'Tow Shop Workbench',
        items = items
    }

    TriggerServerEvent('inventory:server:SetInventoryItems', items)
    TriggerServerEvent('inventory:server:OpenInventory', 'customcrafting', crafting.label, crafting)
end
```

---

## ox_target Integration

```lua
-- Register crafting station targets
for stationId, station in pairs(Config.Crafting.stations) do
    exports.ox_target:addBoxZone({
        coords = station.coords,
        size = vec3(1.5, 1.5, 2.0),
        rotation = 0,
        debug = Config.Debug,
        options = {
            {
                name = 'tow_crafting_' .. stationId,
                icon = 'fa-solid fa-wrench',
                label = station.label,
                onSelect = function()
                    OpenTowCrafting()
                end,
                canInteract = function()
                    return IsOnTowDuty()
                end,
                groups = { ['tow'] = 0 } -- All tow grades
            }
        }
    })
end
```

---

## Required Items (Add to qb-core/shared/items.lua)

```lua
-- Crafting materials
['adhesive'] = { name = 'adhesive', label = 'Industrial Adhesive', weight = 100, type = 'item', image = 'adhesive.png', unique = false, useable = false, shouldClose = false, description = 'Strong bonding agent' },
['copper_wire'] = { name = 'copper_wire', label = 'Copper Wire', weight = 200, type = 'item', image = 'copper_wire.png', unique = false, useable = false, shouldClose = false, description = 'Conductive wire' },
['electronic_components'] = { name = 'electronic_components', label = 'Electronic Components', weight = 150, type = 'item', image = 'electronics.png', unique = false, useable = false, shouldClose = false, description = 'Various electronic parts' },
['fabric'] = { name = 'fabric', label = 'Heavy Duty Fabric', weight = 300, type = 'item', image = 'fabric.png', unique = false, useable = false, shouldClose = false, description = 'Durable fabric material' },

-- Craftable items
['tyre_repair_kit'] = { name = 'tyre_repair_kit', label = 'Tire Repair Kit', weight = 500, type = 'item', image = 'tyre_repair_kit.png', unique = false, useable = true, shouldClose = true, description = 'Patches small tire punctures' },
['jumper_cables'] = { name = 'jumper_cables', label = 'Jumper Cables', weight = 1000, type = 'item', image = 'jumper_cables.png', unique = false, useable = true, shouldClose = true, description = 'For jumpstarting dead batteries' },
['harness'] = { name = 'harness', label = 'Racing Harness', weight = 2000, type = 'item', image = 'harness.png', unique = false, useable = false, shouldClose = false, description = '4-point racing harness' },
```

---

## UI Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          CRAFTING UI FLOW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  STEP 1: APPROACH                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                      │   │
│  │   Player walks to workbench                                         │   │
│  │                    │                                                 │   │
│  │                    ▼                                                 │   │
│  │   ┌────────────────────────────────────────┐                        │   │
│  │   │  ox_target zone detects player         │                        │   │
│  │   │  Shows: [E] Tow Shop Workbench         │                        │   │
│  │   └────────────────────────────────────────┘                        │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                        │
│                                   ▼                                        │
│  STEP 2: OPEN CRAFTING MENU                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  ┌─────────────────────────────────────────────────────────────┐    │   │
│  │  │              CRAFTING MENU (qs-inventory)                    │    │   │
│  │  ├─────────────────────────────────────────────────────────────┤    │   │
│  │  │                                                              │    │   │
│  │  │  YOUR MATERIALS              CRAFTABLE ITEMS                │    │   │
│  │  │  ┌───────────────┐           ┌───────────────┐              │    │   │
│  │  │  │ metalscrap x5 │           │ repair_kit    │ ◄── Tier 1   │    │   │
│  │  │  │ rubber x3     │           │ 100% success  │              │    │   │
│  │  │  │ plastic x2    │           ├───────────────┤              │    │   │
│  │  │  │ duct_tape x1  │           │ duct_tape     │ ◄── Tier 1   │    │   │
│  │  │  │ steel x2      │           │ 100% success  │              │    │   │
│  │  │  └───────────────┘           ├───────────────┤              │    │   │
│  │  │                              │tyre_replacement│◄── Tier 2   │    │   │
│  │  │  Grade: 3 (Lead Driver)      │ 95% success   │   LOCKED     │    │   │
│  │  │                              └───────────────┘              │    │   │
│  │  │                                                              │    │   │
│  │  └─────────────────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                        │
│                                   ▼                                        │
│  STEP 3: SELECT & CRAFT                                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                      │   │
│  │   Player selects "repair_kit"                                       │   │
│  │                    │                                                 │   │
│  │                    ▼                                                 │   │
│  │   ┌────────────────────────────────────────┐                        │   │
│  │   │  MATERIALS CHECK                       │                        │   │
│  │   │  Need: 2x metalscrap, 1x rubber,       │                        │   │
│  │   │        1x duct_tape                    │                        │   │
│  │   │  Have: YES  ✓                          │                        │   │
│  │   └────────────────────────────────────────┘                        │   │
│  │                    │                                                 │   │
│  │                    ▼                                                 │   │
│  │   ┌────────────────────────────────────────┐                        │   │
│  │   │  lib.progressBar                       │                        │   │
│  │   │  "Crafting repair_kit..."              │                        │   │
│  │   │  ████████████░░░░░░░░  60%             │                        │   │
│  │   │  Animation: mechanic_loop              │                        │   │
│  │   └────────────────────────────────────────┘                        │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                        │
│                                   ▼                                        │
│  STEP 4: RESULT                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                      │   │
│  │         SUCCESS (100%)                    FAIL (0% for Tier 1)      │   │
│  │   ┌─────────────────────┐           ┌─────────────────────┐         │   │
│  │   │  lib.notify         │           │  lib.notify         │         │   │
│  │   │  "Crafted 1x        │           │  "Crafting failed!  │         │   │
│  │   │   repair_kit"       │           │   Materials lost"   │         │   │
│  │   │  type: success      │           │  type: error        │         │   │
│  │   └─────────────────────┘           └─────────────────────┘         │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Grade Progression

| Grade | Title | Unlocks |
|-------|-------|---------|
| 0 | Trainee | Tier 1 recipes |
| 1 | Driver | Tier 1 recipes |
| 2 | Senior Driver | Tier 1-2 recipes |
| 3 | Lead Driver | Tier 1-2 recipes |
| 4 | Supervisor | All recipes |
| 5 | Manager | All recipes + bulk craft |

