# ox_lib Integration Plan

**Resource**: dps-towjob
**Date**: 2025-12-30

---

## Overview

This document outlines how ox_lib will be integrated throughout the tow job system for UI, callbacks, zones, and notifications.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ox_lib INTEGRATION MAP                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│    ┌──────────────┐     ┌──────────────┐     ┌──────────────┐              │
│    │   ZONES      │     │   TARGETS    │     │   POINTS     │              │
│    │  (lib.zones) │     │ (ox_target)  │     │ (lib.points) │              │
│    └──────┬───────┘     └──────┬───────┘     └──────┬───────┘              │
│           │                    │                    │                       │
│           └────────────────────┼────────────────────┘                       │
│                                ▼                                            │
│                    ┌───────────────────────┐                                │
│                    │    PLAYER ENTERS      │                                │
│                    │      ZONE/TARGET      │                                │
│                    └───────────┬───────────┘                                │
│                                │                                            │
│                                ▼                                            │
│    ┌───────────────────────────────────────────────────────────┐           │
│    │                    lib.showTextUI                          │           │
│    │            "[E] - Tow Services / Workbench"                │           │
│    └───────────────────────────┬───────────────────────────────┘           │
│                                │ Player presses E                           │
│                                ▼                                            │
│    ┌───────────────────────────────────────────────────────────┐           │
│    │                  lib.registerContext                       │           │
│    │              (Opens Context Menu)                          │           │
│    └───────────────────────────┬───────────────────────────────┘           │
│                                │                                            │
│           ┌────────────────────┼────────────────────┐                       │
│           ▼                    ▼                    ▼                       │
│    ┌────────────┐       ┌────────────┐       ┌────────────┐                │
│    │ Clock In   │       │ Spawn      │       │ Roadside   │                │
│    │ /Out       │       │ Vehicle    │       │ Services   │                │
│    └─────┬──────┘       └─────┬──────┘       └─────┬──────┘                │
│          │                    │                    │                        │
│          ▼                    ▼                    ▼                        │
│    ┌───────────────────────────────────────────────────────────┐           │
│    │                   lib.callback                             │           │
│    │          (Communicate with Server)                         │           │
│    └───────────────────────────┬───────────────────────────────┘           │
│                                │                                            │
│                                ▼                                            │
│    ┌───────────────────────────────────────────────────────────┐           │
│    │                  lib.progressBar                           │           │
│    │          (Show action progress)                            │           │
│    └───────────────────────────┬───────────────────────────────┘           │
│                                │                                            │
│                                ▼                                            │
│    ┌───────────────────────────────────────────────────────────┐           │
│    │                    lib.notify                              │           │
│    │          (Show result notification)                        │           │
│    └───────────────────────────────────────────────────────────┘           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Menu Structure

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CONTEXT MENU HIERARCHY                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      tow_main_menu                                   │   │
│  │  "Tow Services"                                                      │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │  ├─ 🕐 Clock In/Out                                                  │   │
│  │  ├─ 📋 View Queue ─────────────────────┐                             │   │
│  │  ├─ 🚛 Spawn Tow Vehicle ──────────┐   │                             │   │
│  │  └─ 💵 Collect Earnings            │   │                             │   │
│  └────────────────────────────────────┼───┼─────────────────────────────┘   │
│                                       │   │                                 │
│                                       ▼   ▼                                 │
│  ┌─────────────────────────┐   ┌─────────────────────────┐                 │
│  │   tow_vehicle_menu      │   │    tow_queue_menu       │                 │
│  │  "Tow Vehicles"         │   │   "Queue Status"        │                 │
│  ├─────────────────────────┤   ├─────────────────────────┤                 │
│  │  ├─ 🚛 Flatbed          │   │  Position: #3           │                 │
│  │  ├─ 🚗 Tow Truck        │   │  Pending Jobs: 5        │                 │
│  │  ├─ 🚙 Tow Truck 2      │   │  Available Drivers: 2   │                 │
│  │  └─ 🏎️ Slam Truck       │   │                         │                 │
│  └─────────────────────────┘   └─────────────────────────┘                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    roadside_services_menu                            │   │
│  │  "Roadside Services"                                                 │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │  ├─ 🔧 Change Flat Tire ── Requires: tyre_replacement ── $75        │   │
│  │  ├─ 📦 Quick Patch ─────── Requires: duct_tape ───────── $50        │   │
│  │  ├─ 🔋 Jumpstart ───────── Requires: none ────────────── $100       │   │
│  │  ├─ 🛢️ Top Off Fluids ──── Requires: none ────────────── $60        │   │
│  │  └─ 🚛 Tow to Shop ─────── Full tow service                         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      active_tow_menu                                 │   │
│  │  "Current Tow Job"                                                   │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │  ├─ 📍 Set GPS to Pickup                                            │   │
│  │  ├─ 🏁 Set GPS to Dropoff                                           │   │
│  │  ├─ 📞 Contact Customer                                             │   │
│  │  └─ ❌ Cancel Job                                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Callback Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CALLBACK DATA FLOW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   CLIENT                              SERVER                                │
│   ──────                              ──────                                │
│                                                                             │
│   ┌─────────────────┐                 ┌─────────────────┐                  │
│   │ Player clocks   │    REQUEST      │ lib.callback    │                  │
│   │ in at shop      │ ───────────────►│ .register()     │                  │
│   │                 │                 │                 │                  │
│   │ lib.callback()  │                 │ - Verify job    │                  │
│   └─────────────────┘                 │ - Update duty   │                  │
│          │                            │ - Return status │                  │
│          │                            └────────┬────────┘                  │
│          │                                     │                           │
│          │           RESPONSE                  │                           │
│          │◄────────────────────────────────────┘                           │
│          ▼                                                                 │
│   ┌─────────────────┐                                                      │
│   │ Receive result  │                                                      │
│   │                 │                                                      │
│   │ If success:     │                                                      │
│   │ - Show notify   │                                                      │
│   │ - Update UI     │                                                      │
│   │ - Add radial    │                                                      │
│   └─────────────────┘                                                      │
│                                                                             │
│   ═══════════════════════════════════════════════════════════════════════  │
│                                                                             │
│   REGISTERED CALLBACKS:                                                     │
│   ┌────────────────────────────────────────────────────────────────────┐   │
│   │ dps-towjob:server:getQueueStatus    → Returns queue position/count  │   │
│   │ dps-towjob:server:getCurrentAssignment → Returns active job or nil  │   │
│   │ dps-towjob:server:toggleDuty        → Toggles on/off duty status    │   │
│   │ dps-towjob:server:getAvailableShops → Returns shops with employees  │   │
│   │ dps-towjob:server:calculateTowPrice → Returns price based on dist   │   │
│   └────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Callbacks (Server/Client RPC)

### Server Callbacks
```lua
-- Get queue status
lib.callback.register('dps-towjob:server:getQueueStatus', function(source)
    return {
        queueLength = #TowQueue,
        availableDrivers = GetAvailableDriverCount(),
        myPosition = GetDriverQueuePosition(source)
    }
end)

-- Get current assignment
lib.callback.register('dps-towjob:server:getCurrentAssignment', function(source)
    return ActiveAssignments[source] or nil
end)

-- Request duty toggle
lib.callback.register('dps-towjob:server:toggleDuty', function(source, shopId)
    return ToggleDriverDuty(source, shopId)
end)

-- Get available shops for tow
lib.callback.register('dps-towjob:server:getAvailableShops', function(source)
    return GetShopsWithOnDutyEmployees()
end)

-- Calculate tow price
lib.callback.register('dps-towjob:server:calculateTowPrice', function(source, pickupCoords, dropoffCoords)
    return CalculateTowPayment(pickupCoords, dropoffCoords)
end)
```

### Client Callbacks
```lua
-- Get current vehicle on hook
lib.callback('dps-towjob:server:getCurrentAssignment', false, function(assignment)
    if assignment then
        -- Update UI/blip
    end
end)
```

---

## 2. Context Menus

### Main Tow Menu (Clock In Location)
```lua
lib.registerContext({
    id = 'tow_main_menu',
    title = 'Tow Services',
    options = {
        {
            title = 'Clock In',
            description = 'Start your tow shift at this location',
            icon = 'clock',
            onSelect = function()
                TriggerServerEvent('dps-towjob:toggleDuty', CurrentShop)
            end,
            metadata = {
                {label = 'Shop', value = CurrentShopName},
                {label = 'Commission', value = '85%'}
            }
        },
        {
            title = 'View Queue',
            description = 'See pending tow requests',
            icon = 'list',
            onSelect = function()
                OpenQueueMenu()
            end
        },
        {
            title = 'Spawn Tow Vehicle',
            description = 'Get your work vehicle',
            icon = 'truck',
            onSelect = function()
                OpenVehicleSpawnMenu()
            end
        },
        {
            title = 'Collect Earnings',
            description = 'Withdraw from shop fund',
            icon = 'money-bill',
            onSelect = function()
                TriggerServerEvent('dps-towjob:collectEarnings')
            end
        }
    }
})
```

### Vehicle Spawn Menu
```lua
lib.registerContext({
    id = 'tow_vehicle_menu',
    title = 'Tow Vehicles',
    menu = 'tow_main_menu',
    options = {
        {
            title = 'Flatbed',
            description = 'Large flatbed tow truck',
            icon = 'truck-ramp-box',
            onSelect = function()
                SpawnTowVehicle('flatbed')
            end
        },
        {
            title = 'Tow Truck',
            description = 'Standard hook tow',
            icon = 'truck-pickup',
            onSelect = function()
                SpawnTowVehicle('towtruck')
            end
        },
        {
            title = 'Tow Truck 2',
            description = 'Heavy duty hook tow',
            icon = 'truck-pickup',
            onSelect = function()
                SpawnTowVehicle('towtruck2')
            end
        },
        {
            title = 'Slam Truck',
            description = 'Lowrider tow',
            icon = 'car-side',
            onSelect = function()
                SpawnTowVehicle('slamtruck')
            end
        }
    }
})
```

### Roadside Services Menu
```lua
lib.registerContext({
    id = 'roadside_services_menu',
    title = 'Roadside Services',
    options = {
        {
            title = 'Change Flat Tire',
            description = 'Replace damaged tire',
            icon = 'tire',
            onSelect = function()
                PerformRoadsideService('tire_change')
            end,
            metadata = {
                {label = 'Required', value = 'tyre_replacement'},
                {label = 'Base Price', value = '$75'}
            }
        },
        {
            title = 'Quick Patch',
            description = 'Temporary body repair',
            icon = 'tape',
            onSelect = function()
                PerformRoadsideService('quick_patch')
            end,
            metadata = {
                {label = 'Required', value = 'duct_tape'},
                {label = 'Base Price', value = '$50'}
            }
        },
        {
            title = 'Jumpstart',
            description = 'Jump dead battery',
            icon = 'car-battery',
            onSelect = function()
                PerformRoadsideService('jumpstart')
            end,
            metadata = {
                {label = 'Required', value = 'None'},
                {label = 'Base Price', value = '$100'}
            }
        },
        {
            title = 'Top Off Fluids',
            description = 'Add oil, coolant, etc.',
            icon = 'oil-can',
            onSelect = function()
                PerformRoadsideService('fluids')
            end,
            metadata = {
                {label = 'Base Price', value = '$60'}
            }
        },
        {
            title = 'Tow to Shop',
            description = 'Full tow for major repairs',
            icon = 'truck-ramp-box',
            onSelect = function()
                InitiateTow()
            end
        }
    }
})
```

### Active Job Menu
```lua
lib.registerContext({
    id = 'active_tow_menu',
    title = 'Current Tow Job',
    options = {
        {
            title = 'Set GPS to Pickup',
            icon = 'location-dot',
            onSelect = function()
                SetWaypointToPickup()
            end
        },
        {
            title = 'Set GPS to Dropoff',
            icon = 'flag-checkered',
            onSelect = function()
                SetWaypointToDropoff()
            end
        },
        {
            title = 'Contact Customer',
            description = 'Call the requesting party',
            icon = 'phone',
            onSelect = function()
                ContactCustomer()
            end
        },
        {
            title = 'Cancel Job',
            description = 'Return job to queue',
            icon = 'xmark',
            onSelect = function()
                CancelCurrentJob()
            end
        }
    }
})
```

---

## 3. Notifications

### Notification Types
```lua
-- Job assignment
lib.notify({
    title = 'Tow Dispatch',
    description = 'New job assigned - Check GPS',
    type = 'inform',
    duration = 8000,
    icon = 'truck-ramp-box'
})

-- Queue position update
lib.notify({
    title = 'Queue Update',
    description = 'You are now #3 in queue',
    type = 'inform',
    duration = 5000,
    icon = 'list-ol'
})

-- Payment received
lib.notify({
    title = 'Payment Received',
    description = '$175 added to shop fund',
    type = 'success',
    duration = 5000,
    icon = 'money-bill-wave'
})

-- Job cancelled
lib.notify({
    title = 'Job Cancelled',
    description = 'Customer cancelled request',
    type = 'error',
    duration = 5000,
    icon = 'ban'
})

-- Emergency priority
lib.notify({
    title = 'PRIORITY DISPATCH',
    description = 'Police tow request - Respond immediately',
    type = 'warning',
    duration = 10000,
    icon = 'shield-halved'
})
```

---

## 4. Progress Bars

### Towing Actions
```lua
-- Attach vehicle to flatbed
lib.progressBar({
    duration = 5000,
    label = 'Securing vehicle...',
    useWhileDead = false,
    canCancel = true,
    disable = {
        move = true,
        car = true,
        combat = true
    },
    anim = {
        dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
        clip = 'machinic_loop_mechandplayer'
    }
})

-- Detach vehicle
lib.progressBar({
    duration = 3000,
    label = 'Releasing vehicle...',
    useWhileDead = false,
    canCancel = true,
    disable = {
        move = true,
        car = true,
        combat = true
    }
})

-- Roadside repair
lib.progressBar({
    duration = 8000,
    label = 'Changing tire...',
    useWhileDead = false,
    canCancel = true,
    disable = {
        move = true,
        car = true,
        combat = true
    },
    anim = {
        dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
        clip = 'machinic_loop_mechandplayer'
    },
    prop = {
        model = 'prop_tool_wrench',
        bone = 57005,
        pos = vec3(0.13, 0.02, 0.0),
        rot = vec3(90.0, 0.0, 70.0)
    }
})
```

---

## 5. Zones (ox_lib Points/Zones)

### Shop Depot Zones
```lua
-- Clock in/out zones at each shop
local depotZones = {}

for shopId, shop in pairs(Config.Shops) do
    if shop.towDepot then
        depotZones[shopId] = lib.zones.box({
            coords = shop.towDepot.coords,
            size = vec3(5, 5, 3),
            rotation = shop.towDepot.heading,
            debug = Config.Debug,
            onEnter = function()
                CurrentShop = shopId
                lib.showTextUI('[E] - Tow Services', {
                    icon = 'truck-ramp-box'
                })
            end,
            onExit = function()
                CurrentShop = nil
                lib.hideTextUI()
            end
        })
    end
end
```

### Impound Lot Zones
```lua
-- Impound dropoff zones
local impoundZones = {}

for lotId, lot in pairs(Config.ImpoundLots) do
    impoundZones[lotId] = lib.zones.poly({
        points = lot.dropoffPoints,
        thickness = 4,
        debug = Config.Debug,
        onEnter = function()
            if HasVehicleOnHook() then
                lib.showTextUI('[E] - Drop off at Impound', {
                    icon = 'warehouse'
                })
            end
        end,
        onExit = function()
            lib.hideTextUI()
        end
    })
end
```

### Vehicle Spawn Points
```lua
-- Tow vehicle spawn points at each depot
for shopId, shop in pairs(Config.Shops) do
    if shop.towDepot then
        lib.points.new({
            coords = shop.towDepot.vehicleSpawn,
            distance = 3.0,
            onEnter = function()
                if IsOnTowDuty() then
                    lib.showTextUI('[E] - Spawn Tow Vehicle', {
                        icon = 'truck'
                    })
                end
            end,
            onExit = function()
                lib.hideTextUI()
            end
        })
    end
end
```

---

## 6. Input Dialogs

### Custom Billing Amount
```lua
local input = lib.inputDialog('Roadside Service Invoice', {
    {type = 'number', label = 'Service Amount ($)', description = 'Base service cost', required = true, min = 0, max = 10000},
    {type = 'number', label = 'Parts Cost ($)', description = 'Cost of parts used', required = false, min = 0, max = 5000},
    {type = 'textarea', label = 'Description', description = 'Service description for invoice', required = true, max = 200}
})

if input then
    local totalAmount = (input[1] or 0) + (input[2] or 0)
    local description = input[3]
    CreateTowInvoice(targetPlayer, totalAmount, description)
end
```

### Impound Notes (Police)
```lua
local input = lib.inputDialog('Impound Vehicle', {
    {type = 'select', label = 'Impound Reason', required = true, options = {
        {value = 'abandoned', label = 'Abandoned Vehicle'},
        {value = 'evidence', label = 'Evidence - Police Hold'},
        {value = 'unpaid_fines', label = 'Unpaid Fines'},
        {value = 'illegal_parking', label = 'Illegal Parking'},
        {value = 'stolen_recovered', label = 'Stolen - Recovered'}
    }},
    {type = 'textarea', label = 'Notes', description = 'Additional details', required = false, max = 500}
})
```

---

## 7. Alert Dialogs

### Confirm Job Cancellation
```lua
local alert = lib.alertDialog({
    header = 'Cancel Tow Job?',
    content = 'This job will be returned to the queue. You may receive it again if no other drivers are available.',
    centered = true,
    cancel = true
})

if alert == 'confirm' then
    TriggerServerEvent('dps-towjob:cancelTow')
end
```

### Confirm Clock Out
```lua
local alert = lib.alertDialog({
    header = 'End Shift?',
    content = 'You have $' .. uncollectedEarnings .. ' in uncollected earnings. Clock out anyway?',
    centered = true,
    cancel = true,
    labels = {
        confirm = 'Clock Out',
        cancel = 'Stay On Duty'
    }
})
```

---

## 8. Radial Menu Integration

```lua
-- Add tow options to radial menu when on duty
lib.addRadialItem({
    id = 'tow_radial',
    icon = 'truck-ramp-box',
    label = 'Tow Job',
    menu = 'tow_radial_menu'
})

lib.registerRadial({
    id = 'tow_radial_menu',
    items = {
        {
            icon = 'list',
            label = 'View Queue',
            onSelect = function()
                OpenQueueMenu()
            end
        },
        {
            icon = 'briefcase',
            label = 'Current Job',
            onSelect = function()
                lib.showContext('active_tow_menu')
            end
        },
        {
            icon = 'wrench',
            label = 'Roadside Services',
            onSelect = function()
                lib.showContext('roadside_services_menu')
            end
        },
        {
            icon = 'clock',
            label = 'Clock Out',
            onSelect = function()
                ConfirmClockOut()
            end
        }
    }
})
```

---

## Dependencies

```lua
-- fxmanifest.lua
shared_scripts {
    '@ox_lib/init.lua',
    'config/*.lua'
}
```

---

## Summary

| Feature | ox_lib Component |
|---------|------------------|
| Server/Client communication | lib.callback |
| Menus | lib.registerContext |
| Notifications | lib.notify |
| Progress bars | lib.progressBar |
| Location zones | lib.zones.box/poly |
| Point interactions | lib.points.new |
| User input | lib.inputDialog |
| Confirmations | lib.alertDialog |
| Quick access | lib.addRadialItem |
| Text prompts | lib.showTextUI |

---

## Zone Layout Map

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TOW DEPOT ZONE LAYOUT                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Each tow depot has the following zones:                                    │
│                                                                             │
│                    ┌─────────────────────────────────────────┐              │
│                    │              SHOP PROPERTY              │              │
│                    │                                         │              │
│    ┌───────────────────┐                    ┌───────────────────┐          │
│    │   lib.zones.box   │                    │   lib.zones.box   │          │
│    │   "Clock In/Out"  │                    │   "Vehicle Spawn" │          │
│    │                   │                    │                   │          │
│    │   5x5x3 meters    │                    │   8x4x3 meters    │          │
│    │                   │                    │                   │          │
│    │  [Tow Services]   │                    │  [Spawn Vehicle]  │          │
│    └───────────────────┘                    └───────────────────┘          │
│                                                                             │
│                    ┌───────────────────┐                                   │
│                    │   lib.points.new  │                                   │
│                    │   "Workbench"     │                                   │
│                    │                   │                                   │
│                    │   3m radius       │                                   │
│                    │                   │                                   │
│                    │  [Craft Items]    │                                   │
│                    └───────────────────┘                                   │
│                    │                                         │              │
│                    └─────────────────────────────────────────┘              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                        IMPOUND LOT ZONE LAYOUT                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                    ┌─────────────────────────────────────────┐              │
│                    │            IMPOUND LOT                  │              │
│                    │                                         │              │
│   ┌───────────────────────────────────────────────────────────┐            │
│   │                    lib.zones.poly                         │            │
│   │                    "Vehicle Dropoff"                      │            │
│   │                                                           │            │
│   │  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐   │            │
│   │  │     │  │     │  │     │  │     │  │     │  │     │   │            │
│   │  │ [P] │  │ [P] │  │ [P] │  │ [P] │  │ [P] │  │ [P] │   │            │
│   │  │     │  │     │  │     │  │     │  │     │  │     │   │            │
│   │  └─────┘  └─────┘  └─────┘  └─────┘  └─────┘  └─────┘   │            │
│   │                                                           │            │
│   │  [Drop off at Impound] - Shows when vehicle on hook      │            │
│   └───────────────────────────────────────────────────────────┘            │
│                                                                             │
│                    ┌───────────────────┐                                   │
│                    │   ox_target box   │                                   │
│                    │   "Retrieval"     │                                   │
│                    │                   │                                   │
│                    │  [Retrieve Car]   │                                   │
│                    └───────────────────┘                                   │
│                    │                                         │              │
│                    └─────────────────────────────────────────┘              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Radial Menu Structure

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        RADIAL MENU LAYOUT                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                              [TOW JOB]                                      │
│                                  │                                          │
│                    ┌─────────────┼─────────────┐                            │
│                    │             │             │                            │
│                    ▼             ▼             ▼                            │
│              ┌─────────┐   ┌─────────┐   ┌─────────┐                       │
│              │ View    │   │ Current │   │ Roadside│                       │
│              │ Queue   │   │ Job     │   │ Service │                       │
│              │         │   │         │   │         │                       │
│              │ 📋      │   │ 📦      │   │ 🔧      │                       │
│              └─────────┘   └─────────┘   └─────────┘                       │
│                                  │                                          │
│                                  ▼                                          │
│                            ┌─────────┐                                      │
│                            │ Clock   │                                      │
│                            │ Out     │                                      │
│                            │         │                                      │
│                            │ 🕐      │                                      │
│                            └─────────┘                                      │
│                                                                             │
│   Note: Radial menu only visible when player is ON DUTY as tow driver      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

