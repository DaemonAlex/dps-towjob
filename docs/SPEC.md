# DPS-TowJob Specification

**Project**: dps-towjob
**Base**: qb-towjob (QBCore Team)
**Enhancements**: @daemonAlex
**Integration**: JG Scripts (jg-mechanic)
**Version**: 2.0.0
**Date**: 2025-12-30

---

## Overview

A comprehensive tow job system that integrates with mechanic shops, providing queue-based dispatch, multi-location support, and seamless billing integration.

---

## Core Features

### Single Whitelist Tow Job
- One `tow` job that services all mechanic shops, police, EMS
- Drivers clock in at a specific shop location
- Shop assignment tracked for commission purposes

---

## Queue System

### Queue Rules
```
PRIORITY ORDER:
1. Emergency Services (Police/EMS) - Highest priority, jumps queue
2. Customer Calls - Normal queue (FIFO)
3. PVE (NPC tows) - Lowest priority

ASSIGNMENT RULES:
- Driver must be AVAILABLE (not on active tow)
- Longest waiting driver gets next job
- Emergency jumps queue position but doesn't interrupt active tows
- Driver on PVE tow only gets PVP call if no one else available
```

### Driver States
| State | Description |
|-------|-------------|
| `available` | On duty, waiting for assignment |
| `busy` | Currently on a tow (PVE or PVP) |
| `off_duty` | Not working |

### Cancel Logic
- Cancelled jobs requeue at original timestamp
- Next available driver gets it (might be same driver if only one available)
- Natural deterrent against cherry-picking jobs

---

## Destinations

### Police Tows → Impound
- Vehicle goes to NEAREST impound from pickup location
- Player pays impound fee to retrieve

### Impound Lots (3 Locations)
| Location | Coverage Area |
|----------|---------------|
| City (Los Santos) | South LS, Downtown, Beach |
| Sandy Shores | Blaine County, Desert |
| Roxwood | North County |

### Repair Tows → Shop Queue
- Shop must have at least 1 employee ON DUTY
- Shop waiting LONGEST gets next tow
- Creates fair distribution across shops

---

## Payment System

### Core Principle
**ALL payments flow through shop fund - NEVER direct to driver**

### Payment Formula
```lua
Config.TowPayment = {
    baseRate = 100,        -- Base pay
    perMile = 15,          -- Per mile/km
    shopCut = 0.15,        -- 15% to shop
    driverCut = 0.85,      -- 85% to driver
}

-- Example: 5 mile tow
-- Total: $100 + (5 × $15) = $175
-- Shop: $175 × 0.15 = $26.25
-- Driver: $175 × 0.85 = $148.75
```

### Payment Flow by Type

#### PVE Tows (NPC Vehicles)
```
City creates money → Shop Society Fund
                          ↓
              Driver collects when ready
```

#### Police/Impound Tows
```
City fronts payment → Shop Society Fund → Driver
                              ↓
            Owner pays impound fee (recoups cost)

PD pays $0 - system is self-sustaining
```

#### Customer Tows
```
Driver/Shop creates invoice (qs-billing)
                    ↓
          Customer pays invoice
                    ↓
          Money → Shop Society Fund
                    ↓
          Driver collects when ready
```

---

## Request Entry Points

### Customers
- Use **qs-billing** to create tow request (service ticket)
- Request enters queue as normal priority

### Police/EMS
- Use **qs-dispatch** to request tow
- Request enters queue as PRIORITY (jumps queue)

### PVE
- System-generated NPC breakdown calls
- Lowest priority in queue

---

## Roadside Services

### Tow Drivers Can Perform
| Service | Items Required | Billable |
|---------|----------------|----------|
| Flat tire change | tyre_replacement | Yes |
| Quick patch | duct_tape | Yes |
| Jumpstart | - | Yes |
| Top off fluids | - | Yes |

### Major Damage → Must Tow
- Engine damage
- Body damage over threshold
- Anything requiring shop equipment

---

## Duty System

### Integration Points
- Hook into QBCore native duty (`player.job.onduty`)
- Hook into jg-mechanic duty callbacks
- Track WHICH SHOP driver clocked in at

### Shop Assignment Tracking
```lua
DutyTracker = {
    [source] = {
        job = "tow",
        shop = "lscustoms",
        clockedInAt = timestamp,
        lastTowCompleted = timestamp
    }
}
```

---

## Shop Integration

### Shops with Tow Depots
| Shop | Job | Tow Depot | Employee Garage |
|------|-----|-----------|-----------------|
| LS Customs Burton | mechanic | Yes (Primary) | 10 slots |
| Benny's Strawberry | bennys | Yes | 8 slots |
| LS Customs La Mesa | mechanic2 | Yes | 6 slots |
| Beeker's Paleto | beeker | Yes | 4 slots |
| Hayes Auto | mechanic3 | Yes | 6 slots |
| LS Customs Harmony | - | No (self-service) | No |
| LS Customs LSIA | - | No (self-service) | No |

### Shop Queue System
```
When repair tow needs assignment:

1. Filter shops with on-duty employees
2. Sort by wait time (longest first)
3. Assign to shop with longest wait
4. Reset that shop's wait timer
```

---

## Tow Vehicles

```lua
Config.TowVehicles = {
    ["flatbed"] = "Flatbed",
    ["towtruck"] = "Tow Truck",
    ["towtruck2"] = "Tow Truck 2",
    ["slamtruck"] = "Slam Truck",
}
```

---

## Configuration

### config/config.lua
```lua
Config = {}

-- Credits
Config.Credits = {
    base = "QBCore Team",
    enhancements = "@daemonAlex",
    integration = "JG Scripts"
}

-- Core Settings
Config.Debug = false
Config.UseOxLib = true

-- Payment
Config.TowPayment = {
    baseRate = 100,
    perMile = 15,
    shopCut = 0.15,
    driverCut = 0.85,
}

-- Queue
Config.Queue = {
    priorityTypes = { "police", "ems" },
    pveEnabled = true,
    maxQueueSize = 50,
}

-- Impound
Config.ImpoundLots = {
    city = {
        label = "LSPD Impound",
        coords = vector3(409.0, -1623.0, 29.0),
        spawn = vector4(409.0, -1623.0, 29.0, 90.0),
        fee = {
            base = 250,
            perDay = 100,
            towFee = 175,
        }
    },
    sandy = {
        label = "Sandy Shores Impound",
        coords = vector3(1880.0, 3692.0, 33.0),
        spawn = vector4(1880.0, 3692.0, 33.0, 30.0),
        fee = {
            base = 150,
            perDay = 50,
            towFee = 150,
        }
    },
    roxwood = {
        label = "Roxwood Impound",
        coords = vector3(0.0, 0.0, 0.0), -- TBD
        spawn = vector4(0.0, 0.0, 0.0, 0.0),
        fee = {
            base = 150,
            perDay = 50,
            towFee = 150,
        }
    },
}
```

---

## File Structure

```
dps-towjob/
├── fxmanifest.lua
├── README.md
├── docs/
│   └── SPEC.md              ← This document
├── config/
│   ├── config.lua           -- Main settings
│   ├── shops.lua            -- Shop/depot definitions
│   ├── impound.lua          -- Impound lot configs
│   └── vehicles.lua         -- Tow vehicle list
├── client/
│   ├── main.lua             -- Core client
│   ├── queue.lua            -- Queue display/notifications
│   ├── towing.lua           -- Attach/detach mechanics
│   ├── roadside.lua         -- Roadside repair menu
│   └── duty.lua             -- Clock in/out at shops
├── server/
│   ├── main.lua             -- Core server
│   ├── queue.lua            -- Queue management
│   ├── dispatch.lua         -- qs-dispatch integration
│   ├── billing.lua          -- qs-billing integration
│   ├── payment.lua          -- Payment calculations
│   └── duty.lua             -- Duty tracking
├── shared/
│   └── functions.lua        -- Shared utilities
├── locales/
│   └── en.lua               -- English strings
└── bridge/
    ├── jg-mechanic.lua      -- jg-mechanic integration
    └── qs-billing.lua       -- qs-billing integration
```

---

## Dependencies

| Resource | Purpose |
|----------|---------|
| qb-core | Framework |
| ox_lib | UI, callbacks, zones |
| ox_target | Interaction targets |
| jg-mechanic | Shop integration, duty |
| qs-billing | Customer billing |
| qs-dispatch | Police/EMS requests |
| qb-management | Society funds |

---

## Events

### Client Events
```lua
-- Receive job assignment
RegisterNetEvent('dps-towjob:assignJob')

-- Job cancelled/completed
RegisterNetEvent('dps-towjob:jobUpdate')

-- Queue status update
RegisterNetEvent('dps-towjob:queueUpdate')
```

### Server Events
```lua
-- Request enters queue
RegisterNetEvent('dps-towjob:addToQueue')

-- Driver completes tow
RegisterNetEvent('dps-towjob:completeTow')

-- Driver cancels tow
RegisterNetEvent('dps-towjob:cancelTow')

-- Driver clocks in/out
RegisterNetEvent('dps-towjob:toggleDuty')
```

---

## Exports

### Server Exports
```lua
-- Get available drivers count
exports['dps-towjob']:GetAvailableDrivers()

-- Get queue length
exports['dps-towjob']:GetQueueLength()

-- Add tow request to queue
exports['dps-towjob']:RequestTow(source, coords, type, priority)

-- Get shop on-duty count
exports['dps-towjob']:GetShopOnDutyCount(shopId)

-- Get shop wait time
exports['dps-towjob']:GetShopWaitTime(shopId)
```

### Client Exports
```lua
-- Check if player is on tow duty
exports['dps-towjob']:IsOnDuty()

-- Get current assignment
exports['dps-towjob']:GetCurrentAssignment()
```

---

## Integration with qs-dispatch

```lua
-- When police requests tow via dispatch
RegisterNetEvent('qs-dispatch:towRequest', function(data)
    local request = {
        type = "police",
        priority = true,
        coords = data.coords,
        vehicle = data.vehicle,
        plate = data.plate,
        requestedBy = data.source,
        timestamp = os.time()
    }

    AddToQueue(request)
end)
```

---

## Integration with qs-billing

```lua
-- Create tow invoice
local function CreateTowInvoice(driver, customer, amount, description)
    exports['qs-billing']:CreateBill({
        sender = driver,
        target = customer,
        amount = amount,
        description = description,
        society = GetDriverShop(driver)
    })
end
```

---

## Integration with jg-mechanic

```lua
-- Check if shop has on-duty employees
local function ShopHasEmployees(shopId)
    local count = 0
    for _, player in pairs(QBCore.Functions.GetPlayers()) do
        local Player = QBCore.Functions.GetPlayer(player)
        if Player and Player.PlayerData.job.onduty then
            local shopJob = Config.ShopJobs[shopId]
            if Player.PlayerData.job.name == shopJob then
                count = count + 1
            end
        end
    end
    return count > 0, count
end

-- Hook into jg-mechanic duty toggle
RegisterNetEvent('jg-mechanic:server:toggle-duty', function()
    -- Update our duty tracker
    UpdateDutyTracker(source)
end)
```

---

## Changelog

### v2.0.0 (2025-12-30)
- Complete rewrite based on qb-towjob
- Added queue-based dispatch system
- Added multi-location impound support
- Added shop queue system
- Added qs-billing integration
- Added qs-dispatch integration
- Added jg-mechanic integration
- Added roadside repair services
- Added distance-based payment
- Credits: QBCore Team (base), @daemonAlex (enhancements)
