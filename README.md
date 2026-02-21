# DPS TowJob

A comprehensive, queue-based tow job system for FiveM with dispatch dashboard, jg-mechanic integration, and NPC "predatory" towing.

![Version](https://img.shields.io/badge/version-2.7.0-blue)
![Framework](https://img.shields.io/badge/framework-QB%20%7C%20QBX%20%7C%20ESX-green)
![License](https://img.shields.io/badge/license-GPL--3.0-orange)

## Features

### Core Systems
- **Queue-Based Dispatch** - Fair job distribution with priority handling
- **NUI Dispatch Dashboard** - Visual management interface (F6)
- **Multi-Location Impound** - City, Sandy Shores, and Paleto lots
- **Shop Integration** - Fair distribution to mechanic shops
- **Framework Agnostic** - Supports QBCore, QBX, and ESX via Bridge abstraction
- **Rope Physics Winching** - Winch vehicles onto tow trucks with rope visuals

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
- **NPC Dispute System** - Angry vehicle owners with dynamic dialogue, negotiation, fights, and police involvement
- **Roadside Services** - Tire changes, jumpstarts, fluid top-offs
- **Driver Reliability Rating** - Persistent performance tracking with pay bonuses
- **Winch System** - Rope-physics winching for distant vehicles
- **jg-mechanic Integration** - Seamless shop queue system
- **qs-billing Integration** - Professional invoicing
- **qs-dispatch Integration** - Police/EMS tow requests

## Screenshots

```
+-------------------------------------------------------------+
|  Tow Dispatch                    [On Duty]   3 Drivers  5 Q |
+--------------------+--------------------+-------------------+
|  Job Queue         |  Active Tows       |  Drivers          |
|                    |                    |                   |
|  +--------------+  |  +--------------+  |  +-------------+  |
|  | POLICE       |  |  | John D.      |  |  | J  John D.  |  |
|  | HIGH         |  |  | ####--  75%  |  |  |   Available |  |
|  | Downtown     |  |  | TOWING       |  |  +-------------+  |
|  | ABC 123      |  |  +--------------+  |                   |
|  | 2m 30s       |  |                    |  +-------------+  |
|  +--------------+  |                    |  | M  Mike S.  |  |
|                    |                    |  |   Busy      |  |
|  +--------------+  |                    |  +-------------+  |
|  | CUSTOMER     |  |                    |                   |
|  | NORMAL       |  |                    |                   |
|  | Beach        |  |                    |                   |
|  +--------------+  |                    |                   |
+--------------------+--------------------+-------------------+
|  12 Today's Tows  $2,450 Earned  4 PVE Breakdowns  3 Impound |
+-------------------------------------------------------------+
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
2. **Database** - Tables are auto-created on first start (see `sql/schema.sql` for reference)
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
    paleto = { ... },
}
```

## Usage

### Commands & Keybinds
| Command | Keybind | Description |
|---------|---------|-------------|
| `/dispatch` | F6 | Open dispatch dashboard |
| `/towmenu` | F7 | Open tow driver menu |
| `/towdetach` | G | Detach towed vehicle (while towing) |
| `/towqueue` | - | View current queue |
| `/calltow` | - | Request a tow (for customers) |

> **Note:** F6, F7, and G keybinds only activate for players with the tow job. They use conditional input polling, not `RegisterKeyMapping`, so they never globally reserve keys from other players or resources.

### Player Workflow
1. Clock in at a tow depot
2. Open dispatch dashboard (F6) or wait for job assignment
3. Accept jobs from the queue
4. Navigate to pickup location
5. Attach vehicle (ox_target) or use winch for distant vehicles
6. Deliver to destination (shop or impound lot)
7. Collect payment from tow menu (F7)

### Predatory Towing
Drivers can earn commission by towing illegally parked NPC vehicles:
- Fire hydrant parking
- Bus stop violations
- Handicapped zone violations
- Double parking
- No-parking zones

**Warning:** NPC owners may confront you! Options include:
- Talk them down
- Negotiate a settlement
- Accept a bribe
- Ignore and continue (may escalate to fight)
- Abandon the tow
- Police may get involved for resolution

## Queue System

```
+------------------------------------------+
|           PRIORITY ORDER                 |
+------------------------------------------+
| 1. Emergency (Police/EMS) - Jumps queue  |
| 2. Customer Calls - Normal FIFO          |
| 3. PVE/Predatory - Lowest priority       |
+------------------------------------------+

+------------------------------------------+
|         DRIVER ASSIGNMENT                |
+------------------------------------------+
| - Must be AVAILABLE (not on active tow)  |
| - Longest waiting driver gets next job   |
| - Emergency jobs jump queue position     |
| - Cancelled jobs requeue at front        |
+------------------------------------------+
```

## Payment Flow

### Customer Tows
```
Customer requests tow (qs-billing)
           |
    Driver completes tow
           |
  Customer pays invoice
           |
  Money -> Shop Society Fund
           |
  Driver collects when ready (85%)
```

### Police Impound
```
Police requests impound (qs-dispatch)
           |
    Driver tows to impound
           |
  City fronts payment -> Shop Society
           |
    Owner pays impound fee
         (recoups cost)
```

### Reliability Rating Bonus
Drivers with 120+ reliability rating earn a 15% pay bonus on all jobs. Rating changes:
- +3 for completed jobs
- -5 for cancellations or disconnecting during a job

## Exports

### Server
```lua
-- Add tow request to queue
exports['dps-towjob']:RequestTow(source, coords, 'customer', priority)

-- Get queue length
exports['dps-towjob']:GetQueueLength()

-- Get available drivers
exports['dps-towjob']:GetAvailableDrivers()

-- Check if shop has mechanics
exports['dps-towjob']:ShopHasEmployees(shopId)

-- Get driver rating
exports['dps-towjob']:GetDriverRating(source)

-- Check if driver is on duty
exports['dps-towjob']:IsDriverOnDuty(source)

-- Get driver's assigned shop
exports['dps-towjob']:GetDriverShop(source)

-- Create a tow bill (requires qs-billing)
exports['dps-towjob']:CreateTowBill(driverSource, customerSource, amount, description)
```

### Client
```lua
-- Check if on duty
exports['dps-towjob']:IsOnDuty()

-- Get current job
exports['dps-towjob']:GetCurrentAssignment()

-- Open dispatch UI
exports['dps-towjob']:OpenDispatchUI()

-- Check if vehicle is attached
exports['dps-towjob']:HasAttachedVehicle()

-- Get attached vehicle entity
exports['dps-towjob']:GetAttachedVehicle()
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
4. **Service Tickets** - Auto-creates tickets when vehicles are dropped off
5. **Notifications** - Alerts mechanics when vehicles are dropped off

## Database

Tables are auto-created on resource start. See `sql/schema.sql` for the full schema reference.

### Tables
| Table | Purpose |
|-------|---------|
| `tow_jobs` | Job tracking (pickup, dropoff, state, payment) |
| `tow_service_tickets` | Repair handoff tickets for mechanic shops |
| `tow_shop_transactions` | Shop fund transaction log |
| `tow_driver_earnings` | Per-driver earning and collection tracking |
| `tow_driver_stats` | Lifetime stats, reliability rating, job counts |
| `tow_impound_vehicles` | Active impound tracking with fee calculation |
| `tow_dispute_logs` | Predatory towing dispute outcomes |

## Changelog

### v2.7.0
- Added settlement system for NPC disputes
- Added police alerts for dispute escalations
- Added arrestable NPCs for police interaction
- Fixed keybinds: F6, F7, G now use conditional threads instead of RegisterKeyMapping
- Fixed 11 bugs found in deep code evaluation:
  - GeneratePlate() producing wrong-length plates
  - AlertPoliceUnits() never matching police officers
  - Client event handler stuck in server-side script
  - playerDropped rating penalty failing silently
  - checkQueue event exposed to client exploit
  - Duplicate PVE spawn loop causing double-spawns
  - Bridge abstraction bypassed in 4 files
  - Blip Policy violation in duty.lua
  - SQL schema out of sync with runtime

### v2.6.0
- Added NPC Dispute system with dynamic dialogue
- Added negotiation mechanics (talk down, settlement, bribe, counter-offer)
- Added NPC fight system with escalation
- Added police integration for dispute resolution

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
