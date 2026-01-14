# DPS TowJob

A comprehensive, queue-based tow job system for FiveM with dispatch dashboard, jg-mechanic integration, and NPC "predatory" towing.

![Version](https://img.shields.io/badge/version-2.5.0-blue)
![Framework](https://img.shields.io/badge/framework-QB%20%7C%20QBX%20%7C%20ESX-green)
![License](https://img.shields.io/badge/license-GPL--3.0-orange)

## Features

### Core Systems
- **Queue-Based Dispatch** - Fair job distribution with priority handling
- **NUI Dispatch Dashboard** - Visual management interface (F6)
- **Multi-Location Impound** - City, Sandy Shores, and Roxwood lots
- **Shop Integration** - Fair distribution to mechanic shops
- **Framework Agnostic** - Supports QBCore, QBX, and ESX

### Job Types
| Type | Priority | Description |
|------|----------|-------------|
| Police | HIGH | Impound requests from law enforcement |
| EMS | HIGH | Emergency medical service requests |
| Customer | NORMAL | Player-requested tows via billing |
| PVE Breakdown | LOW | NPC vehicle breakdowns |
| Predatory | LOW | Illegally parked NPC vehicles |

### Unique Features
- **Predatory Towing** - Tow illegally parked NPC vehicles for commission
- **Roadside Services** - Tire changes, jumpstarts, fluid top-offs
- **Driver Reliability Rating** - Track driver performance
- **jg-mechanic Integration** - Seamless shop queue system
- **qs-billing Integration** - Professional invoicing
- **qs-dispatch Integration** - Police/EMS tow requests

## Screenshots

```
┌─────────────────────────────────────────────────────────────┐
│  🚛 Tow Dispatch                    [On Duty]   👥 3  📋 5  │
├────────────────────┬────────────────────┬───────────────────┤
│  📋 Job Queue      │  🚚 Active Tows    │  👤 Drivers       │
│                    │                    │                   │
│  ┌──────────────┐  │  ┌──────────────┐  │  ┌─────────────┐  │
│  │ 🚔 POLICE    │  │  │ John D.      │  │  │ J  John D.  │  │
│  │ HIGH         │  │  │ ▓▓▓▓▓▓░░ 75% │  │  │   Available │  │
│  │ 📍 Downtown  │  │  │ TOWING       │  │  └─────────────┘  │
│  │ 🚗 ABC 123   │  │  └──────────────┘  │                   │
│  │ ⏱ 2m 30s    │  │                    │  ┌─────────────┐  │
│  └──────────────┘  │                    │  │ M  Mike S.  │  │
│                    │                    │  │   Busy      │  │
│  ┌──────────────┐  │                    │  └─────────────┘  │
│  │ 🚗 CUSTOMER  │  │                    │                   │
│  │ NORMAL       │  │                    │                   │
│  │ 📍 Beach     │  │                    │                   │
│  └──────────────┘  │                    │                   │
├────────────────────┴────────────────────┴───────────────────┤
│  ✅ 12 Today's Tows  💰 $2,450 Earned  🚗 4 PVE  🅿️ 3 Impound │
└─────────────────────────────────────────────────────────────┘
```

## Dependencies

### Required
- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_target](https://github.com/overextended/ox_target)
- [oxmysql](https://github.com/overextended/oxmysql)

### Optional (Enhanced Features)
- [jg-mechanic](https://jgscripts.com/) - Shop integration
- [qs-billing](https://quasar-store.com/) - Customer billing
- [qs-dispatch](https://quasar-store.com/) - Police/EMS dispatch
- [qb-management](https://github.com/qbcore-framework/) - Society funds

## Installation

1. **Download** and extract to your resources folder
2. **Import SQL** - Run `sql/schema.sql` in your database
3. **Configure** - Edit files in `config/` folder
4. **Add to server.cfg**:
   ```cfg
   ensure ox_lib
   ensure ox_target
   ensure dps-towjob
   ```

## Configuration

### config/config.lua
```lua
Config = {}

Config.Debug = false
Config.JobName = 'tow'

-- Payment settings
Config.Payment = {
    baseRate = 100,         -- Base pay per tow
    perMile = 15,           -- Additional pay per mile
    shopCut = 0.15,         -- 15% to shop society
    driverCut = 0.85,       -- 85% to driver
    pveMultiplier = 0.8,    -- PVE tows pay 80%
}

-- Queue settings
Config.Queue = {
    maxSize = 50,
    pveEnabled = true,
    pveInterval = 300000,   -- 5 minutes
    maxPveActive = 3,
}
```

### config/impound.lua
```lua
Config.ImpoundLots = {
    city = {
        label = "LSPD Impound",
        coords = vector3(409.0, -1623.0, 29.0),
        fee = { base = 250, perDay = 100, towFee = 175 }
    },
    sandy = { ... },
    roxwood = { ... },
}
```

## Usage

### Commands
| Command | Keybind | Description |
|---------|---------|-------------|
| `/dispatch` | F6 | Open dispatch dashboard |
| `/towmenu` | F7 | Open tow driver menu |

### Player Workflow
1. Clock in at a tow depot
2. Open dispatch dashboard (F6)
3. Accept jobs from the queue
4. Navigate to pickup location
5. Attach vehicle and deliver to destination
6. Collect payment

### Predatory Towing
Drivers can earn commission by towing illegally parked NPC vehicles:
- Fire hydrant parking
- Bus stop violations
- Handicapped zone violations
- Double parking
- No-parking zones

## Queue System

```
┌─────────────────────────────────────────┐
│           PRIORITY ORDER                │
├─────────────────────────────────────────┤
│ 1. Emergency (Police/EMS) - Jumps queue │
│ 2. Customer Calls - Normal FIFO         │
│ 3. PVE/Predatory - Lowest priority      │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│         DRIVER ASSIGNMENT               │
├─────────────────────────────────────────┤
│ • Must be AVAILABLE (not on active tow) │
│ • Longest waiting driver gets next job  │
│ • Emergency jobs jump queue position    │
│ • Cancelled jobs requeue at original ts │
└─────────────────────────────────────────┘
```

## Payment Flow

### Customer Tows
```
Customer requests tow (qs-billing)
           ↓
    Driver completes tow
           ↓
  Customer pays invoice
           ↓
  Money → Shop Society Fund
           ↓
  Driver collects when ready (85%)
```

### Police Impound
```
Police requests impound (qs-dispatch)
           ↓
    Driver tows to impound
           ↓
  City fronts payment → Shop Society
           ↓
    Owner pays impound fee
         (recoups cost)
```

## Exports

### Server
```lua
-- Add tow request to queue
exports['dps-towjob']:RequestTow(source, coords, 'customer', priority)

-- Get queue length
exports['dps-towjob']:GetQueueLength()

-- Get available drivers count
exports['dps-towjob']:GetAvailableDrivers()

-- Check if shop has mechanics
exports['dps-towjob']:ShopHasEmployees(shopId)
```

### Client
```lua
-- Check if on duty
exports['dps-towjob']:IsOnDuty()

-- Get current job
exports['dps-towjob']:GetCurrentAssignment()

-- Open dispatch UI
exports['dps-towjob']:OpenDispatchUI()
```

## Events

### Server Events
```lua
-- Request tow (from other resources)
TriggerServerEvent('dps-towjob:server:requestTow', {
    type = 'customer',
    coords = vector3(x, y, z),
    plate = 'ABC 123',
    model = 'sultan'
})

-- Job completed
RegisterNetEvent('dps-towjob:server:completeTow')
```

### Client Events
```lua
-- Job assigned to driver
RegisterNetEvent('dps-towjob:client:jobAssigned')

-- Job state changed
RegisterNetEvent('dps-towjob:client:jobStateChanged')

-- Job completed
RegisterNetEvent('dps-towjob:client:jobCompleted')
```

## jg-mechanic Integration

This script seamlessly integrates with jg-mechanic:

1. **Duty Tracking** - Hooks into mechanic duty toggles
2. **Shop Queue** - Routes repair tows to shops with on-duty mechanics
3. **Fair Distribution** - Shop with longest wait gets next tow
4. **Notifications** - Alerts mechanics when vehicles are dropped off

## Database Schema

```sql
CREATE TABLE IF NOT EXISTS `tow_jobs` (
    `id` VARCHAR(50) PRIMARY KEY,
    `type` VARCHAR(20),
    `priority` INT,
    `pickup_coords` JSON,
    `dropoff_coords` JSON,
    `vehicle_plate` VARCHAR(20),
    `vehicle_model` VARCHAR(50),
    `requester_id` VARCHAR(50),
    `driver_id` VARCHAR(50),
    `state` VARCHAR(20),
    `payment` INT,
    `dropoff_impound` VARCHAR(50),
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `completed_at` TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `tow_driver_stats` (
    `citizenid` VARCHAR(50) PRIMARY KEY,
    `total_jobs_completed` INT DEFAULT 0,
    `total_miles_driven` FLOAT DEFAULT 0,
    `total_earned` INT DEFAULT 0,
    `cancelled_jobs` INT DEFAULT 0,
    `reliability_rating` INT DEFAULT 100
);
```

## Changelog

### v2.5.0
- Added NUI Dispatch Dashboard
- Added framework bridge (QB/QBX/ESX support)
- Added predatory towing system
- Enhanced PVE breakdown spawning
- Added driver reliability rating
- Added zone-based commission bonuses

### v2.0.0
- Complete rewrite based on qb-towjob
- Added queue-based dispatch system
- Added jg-mechanic integration
- Added qs-billing integration
- Added roadside services

## Credits

- **Base**: [qb-towjob](https://github.com/qbcore-framework/qb-towjob) by QBCore Team
- **Enhancements**: @daemonAlex / DPS Development
- **Integration**: [JG Scripts](https://jgscripts.com/)

## License

This project is licensed under the GPL-3.0 License.
