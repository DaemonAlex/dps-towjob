# jg-mechanic Integration Bridge

**Resource**: dps-towjob
**Date**: 2025-12-30

---

## Overview

This document outlines how dps-towjob integrates with jg-mechanic for shop duty tracking, vehicle repair handoffs, and billing coordination.

---

## Integration Points

### 1. Duty System Sync
### 2. Shop Employee Detection
### 3. Repair Handoff
### 4. Society Fund Management
### 5. Shop Queue Distribution

---

## 1. Duty System Sync

### Hook into jg-mechanic Duty Events
```lua
-- bridge/jg-mechanic.lua (Server)

local JGMechanic = {}

-- Listen for jg-mechanic duty changes
RegisterNetEvent('jg-mechanic:server:toggle-duty', function()
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)

    if not Player then return end

    local job = Player.PlayerData.job

    -- Update our duty tracker for mechanic employees
    if IsMechanicJob(job.name) then
        local shopId = GetShopByJob(job.name)
        if shopId then
            UpdateShopEmployeeStatus(shopId, source, job.onduty)

            if Config.Debug then
                print('[dps-towjob] Mechanic duty update:', Player.PlayerData.citizenid, job.name, job.onduty)
            end
        end
    end
end)

-- Track tow driver duty separately
RegisterNetEvent('dps-towjob:server:toggleDuty', function(shopId)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)

    if not Player then return end

    local currentDuty = DutyTracker[source]

    if currentDuty then
        -- Clock out
        DutyTracker[source] = nil
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Tow Job',
            description = 'You are now off duty',
            type = 'inform'
        })
    else
        -- Clock in
        DutyTracker[source] = {
            shop = shopId,
            clockedInAt = os.time(),
            lastTowCompleted = nil
        }
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Tow Job',
            description = 'Clocked in at ' .. Config.Shops[shopId].label,
            type = 'success'
        })
    end

    -- Sync with QBCore duty
    Player.Functions.SetJobDuty(not currentDuty)
end)
```

---

## 2. Shop Employee Detection

### Mapping jg-mechanic Jobs to Shops
```lua
-- config/shops.lua

Config.ShopJobMapping = {
    ['lscustoms_burton'] = {
        mechanicJob = 'mechanic',
        towShop = true,
        societyName = 'mechanic'
    },
    ['bennys_strawberry'] = {
        mechanicJob = 'bennys',
        towShop = true,
        societyName = 'bennys'
    },
    ['lscustoms_lamesa'] = {
        mechanicJob = 'mechanic2',
        towShop = true,
        societyName = 'mechanic2'
    },
    ['beekers_paleto'] = {
        mechanicJob = 'beeker',
        towShop = true,
        societyName = 'beeker'
    },
    ['hayes_auto'] = {
        mechanicJob = 'mechanic3',
        towShop = true,
        societyName = 'mechanic3'
    },
    ['lscustoms_harmony'] = {
        mechanicJob = nil, -- Self-service
        towShop = false,
        societyName = nil
    },
    ['lscustoms_lsia'] = {
        mechanicJob = nil, -- Self-service
        towShop = false,
        societyName = nil
    }
}

-- Helper functions
function GetShopByJob(jobName)
    for shopId, shop in pairs(Config.ShopJobMapping) do
        if shop.mechanicJob == jobName then
            return shopId
        end
    end
    return nil
end

function IsMechanicJob(jobName)
    for _, shop in pairs(Config.ShopJobMapping) do
        if shop.mechanicJob == jobName then
            return true
        end
    end
    return false
end
```

### Check On-Duty Employees
```lua
-- server/bridge/jg-mechanic.lua

function GetShopOnDutyCount(shopId)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.mechanicJob then return 0 end

    local count = 0
    local players = QBCore.Functions.GetPlayers()

    for _, src in ipairs(players) do
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            local job = Player.PlayerData.job
            if job.name == shop.mechanicJob and job.onduty then
                count = count + 1
            end
        end
    end

    return count
end

-- Export for external use
exports('GetShopOnDutyCount', GetShopOnDutyCount)

function ShopHasEmployees(shopId)
    return GetShopOnDutyCount(shopId) > 0
end

exports('ShopHasEmployees', ShopHasEmployees)
```

---

## 3. Repair Handoff

### Vehicle Dropoff at Shop
```lua
-- client/bridge/jg-mechanic.lua

function DropoffVehicleAtShop(shopId, vehicle)
    local shop = Config.Shops[shopId]
    if not shop then return false end

    -- Position vehicle at shop dropoff zone
    local dropoffCoords = shop.vehicleDropoff

    -- Create notification for on-duty mechanics
    TriggerServerEvent('dps-towjob:server:notifyMechanics', shopId, {
        type = 'vehicle_dropoff',
        vehicleModel = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)),
        plate = GetVehicleNumberPlateText(vehicle),
        damage = GetVehicleDamageLevel(vehicle)
    })

    return true
end

-- Server: Notify mechanics of incoming vehicle
RegisterNetEvent('dps-towjob:server:notifyMechanics', function(shopId, data)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.mechanicJob then return end

    local players = QBCore.Functions.GetPlayers()

    for _, src in ipairs(players) do
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            local job = Player.PlayerData.job
            if job.name == shop.mechanicJob and job.onduty then
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Incoming Vehicle',
                    description = data.vehicleModel .. ' [' .. data.plate .. '] dropped off by tow',
                    type = 'inform',
                    duration = 8000,
                    icon = 'truck-ramp-box'
                })
            end
        end
    end
end)
```

### jg-mechanic Service Ticket Creation
```lua
-- When vehicle arrives, create a service record jg-mechanic can use
function CreateServiceTicket(shopId, vehicleData, customerData)
    local ticket = {
        id = GenerateTicketId(),
        shop = shopId,
        vehicle = {
            model = vehicleData.model,
            plate = vehicleData.plate,
            owner = vehicleData.owner
        },
        customer = customerData,
        status = 'awaiting_repair',
        createdAt = os.time(),
        towedBy = vehicleData.towDriver
    }

    -- Store in database
    MySQL.insert.await([[
        INSERT INTO tow_service_tickets
        (id, shop, vehicle_data, customer_data, status, created_at, towed_by)
        VALUES (?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?)
    ]], {
        ticket.id,
        shopId,
        json.encode(ticket.vehicle),
        json.encode(ticket.customer),
        ticket.status,
        ticket.createdAt,
        ticket.towedBy
    })

    return ticket
end
```

---

## 4. Society Fund Management

### Payment Flow Integration
```lua
-- server/payment.lua

-- Use qb-management for society funds
local Management = exports['qb-management']

function AddToShopFund(shopId, amount, reason)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.societyName then
        print('[dps-towjob] Warning: No society for shop', shopId)
        return false
    end

    Management:AddMoney(shop.societyName, amount)

    -- Log the transaction
    LogShopTransaction(shopId, amount, reason)

    return true
end

function WithdrawFromShopFund(shopId, citizenid, amount)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.societyName then
        return false, 'No society fund'
    end

    local balance = Management:GetAccount(shop.societyName)

    if balance < amount then
        return false, 'Insufficient funds'
    end

    Management:RemoveMoney(shop.societyName, amount)

    -- Log withdrawal
    LogShopWithdrawal(shopId, citizenid, amount)

    return true
end

-- Get current shop balance
function GetShopBalance(shopId)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.societyName then
        return 0
    end

    return Management:GetAccount(shop.societyName) or 0
end

exports('GetShopBalance', GetShopBalance)
```

### Driver Earnings Tracking
```lua
-- Track individual driver earnings (stored in shop fund)
DriverEarnings = {}

function AddDriverEarning(source, shopId, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    if not DriverEarnings[citizenid] then
        DriverEarnings[citizenid] = {
            total = 0,
            uncollected = 0,
            shop = shopId
        }
    end

    DriverEarnings[citizenid].total = DriverEarnings[citizenid].total + amount
    DriverEarnings[citizenid].uncollected = DriverEarnings[citizenid].uncollected + amount

    -- Add to shop society fund
    AddToShopFund(shopId, amount, 'Tow payment - ' .. citizenid)
end

-- Driver collects earnings
RegisterNetEvent('dps-towjob:server:collectEarnings', function()
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local earnings = DriverEarnings[citizenid]

    if not earnings or earnings.uncollected <= 0 then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Earnings',
            description = 'No uncollected earnings',
            type = 'error'
        })
        return
    end

    local amount = earnings.uncollected
    local shopId = earnings.shop

    -- Withdraw from shop fund
    local success, error = WithdrawFromShopFund(shopId, citizenid, amount)

    if success then
        Player.Functions.AddMoney('bank', amount, 'tow-earnings')
        DriverEarnings[citizenid].uncollected = 0

        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Earnings Collected',
            description = '$' .. amount .. ' deposited to bank',
            type = 'success'
        })
    else
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Error',
            description = error or 'Failed to collect earnings',
            type = 'error'
        })
    end
end)
```

---

## 5. Shop Queue Distribution

### Fair Distribution Algorithm
```lua
-- server/queue.lua

ShopWaitTimes = {}

-- Initialize wait times
for shopId, _ in pairs(Config.ShopJobMapping) do
    ShopWaitTimes[shopId] = 0
end

-- Get next shop for repair tow
function GetNextRepairShop()
    local availableShops = {}

    for shopId, shop in pairs(Config.ShopJobMapping) do
        if shop.towShop and ShopHasEmployees(shopId) then
            table.insert(availableShops, {
                id = shopId,
                waitTime = ShopWaitTimes[shopId] or 0
            })
        end
    end

    if #availableShops == 0 then
        return nil, 'No shops with on-duty employees'
    end

    -- Sort by wait time (longest first)
    table.sort(availableShops, function(a, b)
        return a.waitTime > b.waitTime
    end)

    local selectedShop = availableShops[1]

    -- Reset wait time for selected shop
    ShopWaitTimes[selectedShop.id] = os.time()

    return selectedShop.id
end

-- Update wait times periodically
CreateThread(function()
    while true do
        Wait(60000) -- Every minute

        for shopId, lastTow in pairs(ShopWaitTimes) do
            if ShopHasEmployees(shopId) then
                -- Increment wait time if shop is staffed but hasn't received a tow
                ShopWaitTimes[shopId] = lastTow
            end
        end
    end
end)

exports('GetNextRepairShop', GetNextRepairShop)
exports('GetShopWaitTime', function(shopId)
    local waitTime = ShopWaitTimes[shopId] or 0
    if waitTime == 0 then return 0 end
    return os.time() - waitTime
end)
```

---

## Database Schema

```sql
-- Service tickets for repair handoffs
CREATE TABLE IF NOT EXISTS `tow_service_tickets` (
    `id` VARCHAR(20) PRIMARY KEY,
    `shop` VARCHAR(50) NOT NULL,
    `vehicle_data` LONGTEXT NOT NULL,
    `customer_data` LONGTEXT NOT NULL,
    `status` ENUM('awaiting_repair', 'in_progress', 'completed', 'cancelled') DEFAULT 'awaiting_repair',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `completed_at` TIMESTAMP NULL,
    `towed_by` VARCHAR(50) NOT NULL,
    `repaired_by` VARCHAR(50) NULL,
    `repair_cost` INT DEFAULT 0,
    INDEX `shop` (`shop`),
    INDEX `status` (`status`)
);

-- Shop transaction log
CREATE TABLE IF NOT EXISTS `tow_shop_transactions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop` VARCHAR(50) NOT NULL,
    `amount` INT NOT NULL,
    `type` ENUM('tow_payment', 'impound_fee', 'withdrawal', 'repair_handoff') NOT NULL,
    `description` VARCHAR(255),
    `citizenid` VARCHAR(50) NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `shop` (`shop`),
    INDEX `created_at` (`created_at`)
);
```

---

## Exports Summary

### Server Exports
```lua
-- Check if shop has on-duty mechanics
exports['dps-towjob']:ShopHasEmployees(shopId) -- returns boolean

-- Get on-duty count
exports['dps-towjob']:GetShopOnDutyCount(shopId) -- returns number

-- Get shop balance
exports['dps-towjob']:GetShopBalance(shopId) -- returns number

-- Get next shop for repair tow
exports['dps-towjob']:GetNextRepairShop() -- returns shopId or nil

-- Get shop wait time in seconds
exports['dps-towjob']:GetShopWaitTime(shopId) -- returns number
```

### Client Exports
```lua
-- Check if player is tow driver on duty at specific shop
exports['dps-towjob']:IsOnDutyAtShop(shopId) -- returns boolean

-- Get current shop assignment
exports['dps-towjob']:GetCurrentShop() -- returns shopId or nil
```

---

## Event Flow Diagram

```
Customer requests tow
        ↓
[dps-towjob] Queue assigns to driver
        ↓
Driver picks up vehicle
        ↓
GetNextRepairShop() finds shop with:
  - On-duty mechanics
  - Longest wait time
        ↓
Vehicle delivered to shop
        ↓
[dps-towjob:server:notifyMechanics] alerts mechanics
        ↓
Service ticket created
        ↓
Payment flows:
  Customer pays via qs-billing
        ↓
  Money → Shop Society Fund
        ↓
  Driver collects when ready (85%)
  Shop keeps (15%)
```

---

## Compatibility Notes

### jg-mechanic Version Compatibility
- Tested with jg-mechanic v2.x
- Uses standard QBCore job.onduty for duty detection
- Does not modify jg-mechanic core files

### Required jg-mechanic Settings
```lua
-- In jg-mechanic config, ensure these are enabled:
Config.UseJobDuty = true  -- Required for duty sync
Config.SocietyPay = true  -- Required for society fund integration
```

### Avoiding Conflicts
- dps-towjob uses separate database tables
- No overlapping ox_target zones with jg-mechanic
- Event names prefixed with 'dps-towjob:' to avoid collisions

