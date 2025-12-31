# Employee Garage System

**Resource**: dps-towjob
**Date**: 2025-12-30

---

## Overview

Each tow depot has an employee garage for spawning and storing work vehicles. Vehicles are job-restricted and persist between sessions.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      EMPLOYEE GARAGE SYSTEM                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                         ┌─────────────────────┐                             │
│                         │   TOW DRIVER ON     │                             │
│                         │      DUTY           │                             │
│                         └──────────┬──────────┘                             │
│                                    │                                        │
│                                    ▼                                        │
│                         ┌─────────────────────┐                             │
│                         │  Approach Garage    │                             │
│                         │     ox_target       │                             │
│                         └──────────┬──────────┘                             │
│                                    │                                        │
│               ┌────────────────────┼────────────────────┐                   │
│               │                    │                    │                   │
│               ▼                    ▼                    ▼                   │
│    ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐           │
│    │  SPAWN VEHICLE  │  │ STORED VEHICLES │  │  STORE CURRENT  │           │
│    │                 │  │                 │  │                 │           │
│    │ Select from     │  │ View personal   │  │ Park vehicle    │           │
│    │ shop fleet      │  │ stored vehicles │  │ in garage       │           │
│    └────────┬────────┘  └────────┬────────┘  └────────┬────────┘           │
│             │                    │                    │                    │
│             ▼                    ▼                    │                    │
│    ┌─────────────────┐  ┌─────────────────┐          │                    │
│    │  Check Grade    │  │  Retrieve from  │          │                    │
│    │  Requirements   │  │    Database     │          │                    │
│    └────────┬────────┘  └────────┬────────┘          │                    │
│             │                    │                    │                    │
│             ▼                    ▼                    ▼                    │
│    ┌─────────────────────────────────────────────────────────────┐        │
│    │                        DATABASE                              │        │
│    │                  tow_employee_vehicles                       │        │
│    │                                                              │        │
│    │    ┌────────┬────────┬────────┬────────┬────────┐          │        │
│    │    │  id    │citizen │ model  │ plate  │ state  │          │        │
│    │    ├────────┼────────┼────────┼────────┼────────┤          │        │
│    │    │   1    │ ABC123 │flatbed │TOW12345│ stored │          │        │
│    │    │   2    │ ABC123 │towtruck│TOW67890│  out   │          │        │
│    │    └────────┴────────┴────────┴────────┴────────┘          │        │
│    │                                                              │        │
│    └─────────────────────────────────────────────────────────────┘        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Vehicle Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         VEHICLE LIFECYCLE                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                                                                             │
│    ┌─────────────┐                                  ┌─────────────┐        │
│    │   SPAWNED   │◄─────────────────────────────────│   STORED    │        │
│    │   (World)   │                                  │ (Database)  │        │
│    └──────┬──────┘                                  └──────▲──────┘        │
│           │                                                │               │
│           │ Driver takes vehicle                           │               │
│           ▼                                                │               │
│    ┌─────────────┐                                         │               │
│    │    OUT      │                                         │               │
│    │  (In Use)   │─────────────────────────────────────────┘               │
│    └──────┬──────┘  Driver stores at garage                                │
│           │                                                                 │
│           │                                                                 │
│    ┌──────┼──────────────────────────────────────────────────┐             │
│    │      │                                                  │             │
│    ▼      ▼                                                  ▼             │
│ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│ │ 8HR TIMEOUT  │  │  DESTROYED   │  │  ABANDONED   │  │   IMPOUNDED  │    │
│ │              │  │              │  │              │  │              │    │
│ │ Auto-store   │  │ 30min cool-  │  │ Admin can    │  │ Pay fee to   │    │
│ │ to garage    │  │ down then    │  │ return to    │  │ retrieve     │    │
│ │              │  │ respawn      │  │ storage      │  │              │    │
│ └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │
│        │                 │                 │                 │             │
│        └─────────────────┴─────────────────┴─────────────────┘             │
│                                    │                                        │
│                                    ▼                                        │
│                          ┌─────────────────┐                               │
│                          │     STORED      │                               │
│                          │   (Database)    │                               │
│                          └─────────────────┘                               │
│                                                                             │
│  Legend:                                                                    │
│  ────────────────────────────────────────────────────────────────          │
│  SPAWNED  = Vehicle exists in game world                                   │
│  OUT      = Vehicle in use by player                                       │
│  STORED   = Vehicle saved in database, not in world                        │
│  IMPOUNDED = Vehicle at impound lot, requires fee                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Garage Location Map

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        TOW DEPOT LOCATIONS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                            BLAINE COUNTY                                    │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                                                                      │  │
│   │              ★ BEEKER'S PALETO                                      │  │
│   │              Capacity: 4 vehicles                                    │  │
│   │              Livery: Orange/White                                    │  │
│   │                                                                      │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│                                   │                                         │
│                                   │                                         │
│                            LOS SANTOS                                       │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                                                                      │  │
│   │    ★ HAYES AUTO                          ★ LS CUSTOMS LA MESA       │  │
│   │    Capacity: 6 vehicles                   Capacity: 6 vehicles       │  │
│   │    Livery: Red/Black                      Livery: Green/Black        │  │
│   │                                                                      │  │
│   │                                                                      │  │
│   │              ★ LS CUSTOMS BURTON (PRIMARY)                          │  │
│   │              Capacity: 10 vehicles                                   │  │
│   │              Livery: Blue/White                                      │  │
│   │                                                                      │  │
│   │                                                                      │  │
│   │                        ★ BENNY'S STRAWBERRY                         │  │
│   │                        Capacity: 8 vehicles                          │  │
│   │                        Livery: Purple/Gold                           │  │
│   │                                                                      │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   ★ = Tow Depot with Employee Garage                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Vehicle Fleet by Grade

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        VEHICLE ACCESS BY GRADE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   GRADE 0-2 (Trainee → Senior Driver)                                      │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                                                                      │  │
│   │    ┌────────────┐    ┌────────────┐    ┌────────────┐              │  │
│   │    │  FLATBED   │    │  TOWTRUCK  │    │ TOWTRUCK2  │              │  │
│   │    │            │    │            │    │            │              │  │
│   │    │  Standard  │    │  Standard  │    │   Heavy    │              │  │
│   │    │  flatbed   │    │  hook tow  │    │  hook tow  │              │  │
│   │    │            │    │            │    │            │              │  │
│   │    └────────────┘    └────────────┘    └────────────┘              │  │
│   │                                                                      │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   GRADE 3+ (Lead Driver+)                                                  │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                                                                      │  │
│   │    ┌────────────┐                                                   │  │
│   │    │ SLAMTRUCK  │    + All vehicles from Grade 0-2                  │  │
│   │    │            │                                                   │  │
│   │    │  Lowrider  │                                                   │  │
│   │    │  specialty │                                                   │  │
│   │    │    tow     │                                                   │  │
│   │    └────────────┘                                                   │  │
│   │                                                                      │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   GRADE 4+ (Supervisor+)                                                   │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                                                                      │  │
│   │    ┌────────────┐                                                   │  │
│   │    │  PERSONAL  │    + All vehicles from previous grades            │  │
│   │    │  VEHICLES  │                                                   │  │
│   │    │            │    Supervisors can use personal vehicles          │  │
│   │    │  Any owned │    with tow capacity for work                     │  │
│   │    │  tow-ready │                                                   │  │
│   │    └────────────┘                                                   │  │
│   │                                                                      │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Garage Locations

| Shop | Spawn Point | Store Zone | Capacity |
|------|-------------|------------|----------|
| LS Customs Burton | vec4(-344.5, -131.0, 39.0, 250.0) | Box zone near shop | 10 slots |
| Benny's Strawberry | vec4(-210.0, -1320.0, 31.0, 0.0) | Box zone near shop | 8 slots |
| LS Customs La Mesa | vec4(725.0, -1082.0, 22.0, 90.0) | Box zone near shop | 6 slots |
| Beeker's Paleto | vec4(105.0, 6620.0, 32.0, 180.0) | Box zone near shop | 4 slots |
| Hayes Auto | vec4(-1425.0, -455.0, 36.0, 125.0) | Box zone near shop | 6 slots |

---

## Available Vehicles

### Standard Fleet (All Grades)
| Model | Label | Fuel | Livery |
|-------|-------|------|--------|
| `flatbed` | Flatbed | 100 | Shop-specific |
| `towtruck` | Tow Truck | 100 | Shop-specific |
| `towtruck2` | Heavy Tow Truck | 100 | Shop-specific |

### Premium Fleet (Grade 3+)
| Model | Label | Fuel | Livery |
|-------|-------|------|--------|
| `slamtruck` | Slam Truck | 100 | Shop-specific |

### Personal Vehicles (Grade 4+)
Supervisors and Managers can use personal vehicles with tow capacity.

---

## Configuration (config/garages.lua)

```lua
Config.EmployeeGarages = {
    ['lscustoms_burton'] = {
        label = 'LS Customs Burton - Tow Depot',
        job = 'tow',
        grades = 'all',
        capacity = 10,
        spawnPoint = vec4(-344.5, -131.0, 39.0, 250.0),
        storeZone = {
            coords = vec3(-340.0, -128.0, 39.0),
            size = vec3(8.0, 8.0, 4.0),
            rotation = 250.0
        },
        blip = {
            enabled = true,
            sprite = 68,
            color = 5,
            scale = 0.7,
            label = 'Tow Depot'
        },
        vehicles = {
            { model = 'flatbed', label = 'Flatbed', minGrade = 0, livery = 0 },
            { model = 'towtruck', label = 'Tow Truck', minGrade = 0, livery = 0 },
            { model = 'towtruck2', label = 'Heavy Tow', minGrade = 0, livery = 0 },
            { model = 'slamtruck', label = 'Slam Truck', minGrade = 3, livery = 0 }
        }
    },
    ['bennys_strawberry'] = {
        label = 'Benny\'s - Tow Depot',
        job = 'tow',
        grades = 'all',
        capacity = 8,
        spawnPoint = vec4(-210.0, -1320.0, 31.0, 0.0),
        storeZone = {
            coords = vec3(-207.0, -1318.0, 31.0),
            size = vec3(6.0, 6.0, 4.0),
            rotation = 0.0
        },
        blip = {
            enabled = true,
            sprite = 68,
            color = 5,
            scale = 0.7,
            label = 'Tow Depot'
        },
        vehicles = {
            { model = 'flatbed', label = 'Flatbed', minGrade = 0, livery = 1 },
            { model = 'towtruck', label = 'Tow Truck', minGrade = 0, livery = 1 },
            { model = 'towtruck2', label = 'Heavy Tow', minGrade = 0, livery = 1 },
            { model = 'slamtruck', label = 'Slam Truck', minGrade = 3, livery = 1 }
        }
    },
    ['lscustoms_lamesa'] = {
        label = 'LS Customs La Mesa - Tow Depot',
        job = 'tow',
        grades = 'all',
        capacity = 6,
        spawnPoint = vec4(725.0, -1082.0, 22.0, 90.0),
        storeZone = {
            coords = vec3(728.0, -1085.0, 22.0),
            size = vec3(6.0, 6.0, 4.0),
            rotation = 90.0
        },
        blip = {
            enabled = true,
            sprite = 68,
            color = 5,
            scale = 0.7,
            label = 'Tow Depot'
        },
        vehicles = {
            { model = 'flatbed', label = 'Flatbed', minGrade = 0, livery = 2 },
            { model = 'towtruck', label = 'Tow Truck', minGrade = 0, livery = 2 },
            { model = 'towtruck2', label = 'Heavy Tow', minGrade = 0, livery = 2 },
            { model = 'slamtruck', label = 'Slam Truck', minGrade = 3, livery = 2 }
        }
    },
    ['beekers_paleto'] = {
        label = 'Beeker\'s Paleto - Tow Depot',
        job = 'tow',
        grades = 'all',
        capacity = 4,
        spawnPoint = vec4(105.0, 6620.0, 32.0, 180.0),
        storeZone = {
            coords = vec3(108.0, 6622.0, 32.0),
            size = vec3(6.0, 6.0, 4.0),
            rotation = 180.0
        },
        blip = {
            enabled = true,
            sprite = 68,
            color = 5,
            scale = 0.7,
            label = 'Tow Depot'
        },
        vehicles = {
            { model = 'flatbed', label = 'Flatbed', minGrade = 0, livery = 3 },
            { model = 'towtruck', label = 'Tow Truck', minGrade = 0, livery = 3 },
            { model = 'towtruck2', label = 'Heavy Tow', minGrade = 0, livery = 3 }
            -- No slam truck at smaller depot
        }
    },
    ['hayes_auto'] = {
        label = 'Hayes Auto - Tow Depot',
        job = 'tow',
        grades = 'all',
        capacity = 6,
        spawnPoint = vec4(-1425.0, -455.0, 36.0, 125.0),
        storeZone = {
            coords = vec3(-1422.0, -452.0, 36.0),
            size = vec3(6.0, 6.0, 4.0),
            rotation = 125.0
        },
        blip = {
            enabled = true,
            sprite = 68,
            color = 5,
            scale = 0.7,
            label = 'Tow Depot'
        },
        vehicles = {
            { model = 'flatbed', label = 'Flatbed', minGrade = 0, livery = 4 },
            { model = 'towtruck', label = 'Tow Truck', minGrade = 0, livery = 4 },
            { model = 'towtruck2', label = 'Heavy Tow', minGrade = 0, livery = 4 },
            { model = 'slamtruck', label = 'Slam Truck', minGrade = 3, livery = 4 }
        }
    }
}
```

---

## Database Schema

```sql
CREATE TABLE IF NOT EXISTS `tow_employee_vehicles` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `garage` VARCHAR(50) NOT NULL,
    `model` VARCHAR(50) NOT NULL,
    `plate` VARCHAR(10) NOT NULL,
    `mods` LONGTEXT DEFAULT NULL,
    `fuel` INT DEFAULT 100,
    `damage` LONGTEXT DEFAULT NULL,
    `state` ENUM('stored', 'out', 'impounded') DEFAULT 'stored',
    `last_used` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `plate` (`plate`),
    INDEX `citizenid` (`citizenid`),
    INDEX `garage` (`garage`)
);
```

---

## ox_lib UI Implementation

### Garage Menu
```lua
function OpenEmployeeGarage(garageId)
    local garage = Config.EmployeeGarages[garageId]
    if not garage then return end

    local playerGrade = GetPlayerJobGrade()
    local storedVehicles = lib.callback.await('dps-towjob:server:getStoredVehicles', false, garageId)

    local options = {}

    -- Add "Spawn Vehicle" section
    options[#options + 1] = {
        title = '🚛 Spawn Work Vehicle',
        description = 'Get a company vehicle',
        icon = 'truck-ramp-box',
        arrow = true,
        onSelect = function()
            OpenSpawnMenu(garageId, garage, playerGrade)
        end
    }

    -- Add stored personal vehicles
    if #storedVehicles > 0 then
        options[#options + 1] = {
            title = '📦 Stored Vehicles (' .. #storedVehicles .. ')',
            description = 'Retrieve your stored vehicles',
            icon = 'warehouse',
            arrow = true,
            onSelect = function()
                OpenStoredMenu(garageId, storedVehicles)
            end
        }
    end

    -- Store current vehicle option
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        options[#options + 1] = {
            title = '💾 Store Current Vehicle',
            description = 'Park your vehicle in the garage',
            icon = 'square-parking',
            onSelect = function()
                StoreCurrentVehicle(garageId)
            end
        }
    end

    lib.registerContext({
        id = 'employee_garage_menu',
        title = garage.label,
        options = options
    })

    lib.showContext('employee_garage_menu')
end
```

### Spawn Menu
```lua
function OpenSpawnMenu(garageId, garage, playerGrade)
    local options = {}

    for _, vehicle in ipairs(garage.vehicles) do
        if playerGrade >= vehicle.minGrade then
            options[#options + 1] = {
                title = vehicle.label,
                description = vehicle.minGrade > 0 and ('Grade ' .. vehicle.minGrade .. '+') or 'All grades',
                icon = 'truck',
                metadata = {
                    { label = 'Model', value = vehicle.model },
                    { label = 'Livery', value = 'Shop #' .. (vehicle.livery + 1) }
                },
                onSelect = function()
                    SpawnWorkVehicle(garageId, vehicle)
                end
            }
        end
    end

    lib.registerContext({
        id = 'spawn_vehicle_menu',
        title = 'Spawn Work Vehicle',
        menu = 'employee_garage_menu',
        options = options
    })

    lib.showContext('spawn_vehicle_menu')
end
```

### Store Menu
```lua
function OpenStoredMenu(garageId, vehicles)
    local options = {}

    for _, vehicle in ipairs(vehicles) do
        options[#options + 1] = {
            title = vehicle.label .. ' [' .. vehicle.plate .. ']',
            description = 'Fuel: ' .. vehicle.fuel .. '%',
            icon = 'car',
            metadata = {
                { label = 'Last Used', value = vehicle.last_used }
            },
            onSelect = function()
                RetrieveVehicle(garageId, vehicle)
            end
        }
    end

    lib.registerContext({
        id = 'stored_vehicles_menu',
        title = 'Stored Vehicles',
        menu = 'employee_garage_menu',
        options = options
    })

    lib.showContext('stored_vehicles_menu')
end
```

---

## Server Callbacks

```lua
-- Get stored vehicles for player at garage
lib.callback.register('dps-towjob:server:getStoredVehicles', function(source, garageId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end

    local citizenid = Player.PlayerData.citizenid
    local result = MySQL.query.await([[
        SELECT model, plate, fuel, damage, last_used
        FROM tow_employee_vehicles
        WHERE citizenid = ? AND garage = ? AND state = 'stored'
    ]], { citizenid, garageId })

    local vehicles = {}
    for _, row in ipairs(result or {}) do
        vehicles[#vehicles + 1] = {
            model = row.model,
            plate = row.plate,
            fuel = row.fuel,
            damage = json.decode(row.damage) or {},
            last_used = row.last_used,
            label = GetVehicleLabel(row.model)
        }
    end

    return vehicles
end)

-- Spawn work vehicle
lib.callback.register('dps-towjob:server:spawnWorkVehicle', function(source, garageId, vehicleData)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    -- Check job
    if Player.PlayerData.job.name ~= 'tow' then
        return false, 'Not on tow duty'
    end

    -- Check grade
    if Player.PlayerData.job.grade.level < vehicleData.minGrade then
        return false, 'Grade too low'
    end

    -- Generate plate
    local plate = 'TOW' .. math.random(10000, 99999)

    return true, plate
end)

-- Store vehicle
lib.callback.register('dps-towjob:server:storeVehicle', function(source, garageId, vehicleData)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    local citizenid = Player.PlayerData.citizenid

    -- Check garage capacity
    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM tow_employee_vehicles
        WHERE garage = ? AND state = 'stored'
    ]], { garageId })

    local garage = Config.EmployeeGarages[garageId]
    if count >= garage.capacity then
        return false, 'Garage is full'
    end

    -- Save vehicle
    MySQL.insert.await([[
        INSERT INTO tow_employee_vehicles (citizenid, garage, model, plate, mods, fuel, damage, state)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'stored')
        ON DUPLICATE KEY UPDATE
            garage = VALUES(garage),
            mods = VALUES(mods),
            fuel = VALUES(fuel),
            damage = VALUES(damage),
            state = 'stored',
            last_used = CURRENT_TIMESTAMP
    ]], {
        citizenid,
        garageId,
        vehicleData.model,
        vehicleData.plate,
        json.encode(vehicleData.mods),
        vehicleData.fuel,
        json.encode(vehicleData.damage)
    })

    return true
end)

-- Retrieve vehicle
lib.callback.register('dps-towjob:server:retrieveVehicle', function(source, garageId, plate)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    local citizenid = Player.PlayerData.citizenid

    local vehicle = MySQL.single.await([[
        SELECT * FROM tow_employee_vehicles
        WHERE citizenid = ? AND plate = ? AND state = 'stored'
    ]], { citizenid, plate })

    if not vehicle then
        return false, 'Vehicle not found'
    end

    -- Mark as out
    MySQL.update.await([[
        UPDATE tow_employee_vehicles SET state = 'out' WHERE plate = ?
    ]], { plate })

    return true, {
        model = vehicle.model,
        plate = vehicle.plate,
        mods = json.decode(vehicle.mods) or {},
        fuel = vehicle.fuel,
        damage = json.decode(vehicle.damage) or {}
    }
end)
```

---

## Client Functions

```lua
-- Spawn work vehicle
function SpawnWorkVehicle(garageId, vehicleData)
    local garage = Config.EmployeeGarages[garageId]
    if not garage then return end

    -- Check spawn point is clear
    local spawnCoords = garage.spawnPoint
    if not IsSpawnPointClear(spawnCoords.xyz) then
        lib.notify({
            title = 'Garage',
            description = 'Spawn point is blocked',
            type = 'error'
        })
        return
    end

    local success, plate = lib.callback.await('dps-towjob:server:spawnWorkVehicle', false, garageId, vehicleData)

    if not success then
        lib.notify({
            title = 'Garage',
            description = plate, -- Error message
            type = 'error'
        })
        return
    end

    -- Spawn vehicle
    lib.requestModel(vehicleData.model)
    local vehicle = CreateVehicle(vehicleData.model, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.w, true, false)

    SetVehicleNumberPlateText(vehicle, plate)
    SetVehicleLivery(vehicle, vehicleData.livery)
    SetVehicleFuelLevel(vehicle, 100.0)
    SetVehicleEngineOn(vehicle, true, true, false)

    -- Set as work vehicle
    Entity(vehicle).state.isWorkVehicle = true
    Entity(vehicle).state.shop = garageId

    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)

    lib.notify({
        title = 'Garage',
        description = 'Vehicle spawned: ' .. vehicleData.label,
        type = 'success'
    })
end

-- Store current vehicle
function StoreCurrentVehicle(garageId)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if not vehicle or vehicle == 0 then
        lib.notify({
            title = 'Garage',
            description = 'You must be in a vehicle',
            type = 'error'
        })
        return
    end

    -- Check if it's a work vehicle
    local isWorkVehicle = Entity(vehicle).state.isWorkVehicle
    if not isWorkVehicle then
        lib.notify({
            title = 'Garage',
            description = 'This is not a work vehicle',
            type = 'error'
        })
        return
    end

    local vehicleData = {
        model = GetEntityModel(vehicle),
        plate = GetVehicleNumberPlateText(vehicle),
        mods = GetVehicleMods(vehicle),
        fuel = GetVehicleFuelLevel(vehicle),
        damage = GetVehicleDamage(vehicle)
    }

    local success, errorMsg = lib.callback.await('dps-towjob:server:storeVehicle', false, garageId, vehicleData)

    if success then
        TaskLeaveVehicle(ped, vehicle, 0)
        Wait(1500)
        DeleteVehicle(vehicle)

        lib.notify({
            title = 'Garage',
            description = 'Vehicle stored successfully',
            type = 'success'
        })
    else
        lib.notify({
            title = 'Garage',
            description = errorMsg or 'Failed to store vehicle',
            type = 'error'
        })
    end
end

-- Check spawn point
function IsSpawnPointClear(coords)
    local vehicles = GetGamePool('CVehicle')
    for _, veh in ipairs(vehicles) do
        local vehCoords = GetEntityCoords(veh)
        if #(coords - vehCoords) < 3.0 then
            return false
        end
    end
    return true
end
```

---

## ox_target Integration

```lua
-- Register garage zones
for garageId, garage in pairs(Config.EmployeeGarages) do
    -- Spawn/menu point
    exports.ox_target:addBoxZone({
        coords = garage.spawnPoint.xyz,
        size = vec3(3.0, 3.0, 2.0),
        rotation = garage.spawnPoint.w,
        debug = Config.Debug,
        options = {
            {
                name = 'garage_' .. garageId,
                icon = 'fa-solid fa-warehouse',
                label = 'Open Garage',
                onSelect = function()
                    OpenEmployeeGarage(garageId)
                end,
                canInteract = function()
                    local Player = QBCore.Functions.GetPlayerData()
                    return Player.job.name == 'tow'
                end,
                groups = { ['tow'] = 0 }
            }
        }
    })

    -- Store zone
    exports.ox_target:addBoxZone({
        coords = garage.storeZone.coords,
        size = garage.storeZone.size,
        rotation = garage.storeZone.rotation,
        debug = Config.Debug,
        options = {
            {
                name = 'store_' .. garageId,
                icon = 'fa-solid fa-square-parking',
                label = 'Store Vehicle',
                onSelect = function()
                    StoreCurrentVehicle(garageId)
                end,
                canInteract = function()
                    return IsPedInAnyVehicle(PlayerPedId(), false)
                end,
                groups = { ['tow'] = 0 }
            }
        }
    })
end
```

---

## Vehicle Features

### Shop-Specific Liveries
Each shop has its own livery index:
- 0 = LS Customs Burton (Blue/White)
- 1 = Benny's (Purple/Gold)
- 2 = La Mesa (Green/Black)
- 3 = Beeker's (Orange/White)
- 4 = Hayes (Red/Black)

### Work Vehicle Tracking
```lua
-- State bag for tracking work vehicles
Entity(vehicle).state.isWorkVehicle = true
Entity(vehicle).state.shop = garageId
Entity(vehicle).state.driver = citizenid
```

### Return Policy
- Vehicles not returned within 8 hours are auto-stored
- Damaged vehicles can be repaired at shop (costs deducted from earnings)
- Destroyed vehicles respawn after 30 min cooldown

---

## Blip Configuration

```lua
-- Create garage blips for on-duty tow drivers
function CreateGarageBlips()
    for garageId, garage in pairs(Config.EmployeeGarages) do
        if garage.blip.enabled then
            local blip = AddBlipForCoord(garage.spawnPoint.xyz)
            SetBlipSprite(blip, garage.blip.sprite)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, garage.blip.scale)
            SetBlipColour(blip, garage.blip.color)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(garage.blip.label)
            EndTextCommandSetBlipName(blip)

            GarageBlips[garageId] = blip
        end
    end
end

-- Remove blips when off duty
function RemoveGarageBlips()
    for garageId, blip in pairs(GarageBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    GarageBlips = {}
end
```

