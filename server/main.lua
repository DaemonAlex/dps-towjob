--[[
    dps-towjob Server Main
    Core server initialization and exports
    Includes: Anti-spam, server-side validation, reliability rating
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Localize for performance
local os_time = os.time
local pairs = pairs
local ipairs = ipairs
local type = type
local math_floor = math.floor

-- State tables
TowQueue = {}           -- Active tow queue
ActiveJobs = {}         -- Jobs currently being worked
DutyTracker = {}        -- Drivers on duty
ShopWaitTimes = {}      -- Track wait times per shop
DriverEarnings = {}     -- Track uncollected earnings
DriverRatings = {}      -- Reliability ratings cache

-- Anti-spam cooldowns (source -> {event -> timestamp})
local EventCooldowns = {}
local COOLDOWN_TIMES = {
    ['vehicleAttached'] = 5000,    -- 5 seconds between attach events
    ['completeJob'] = 10000,       -- 10 seconds between completions
    ['cancelJob'] = 30000,         -- 30 seconds between cancellations
    ['toggleDuty'] = 5000,         -- 5 seconds between duty toggles
    ['collectEarnings'] = 60000,   -- 1 minute between earnings collections
}

-- Check if event is on cooldown (anti-spam)
local function IsOnCooldown(source, eventName)
    local now = GetGameTimer()
    local cooldown = COOLDOWN_TIMES[eventName] or 1000

    if not EventCooldowns[source] then
        EventCooldowns[source] = {}
    end

    local lastCall = EventCooldowns[source][eventName] or 0

    if now - lastCall < cooldown then
        TowJob.Debug('Anti-spam blocked:', source, eventName)
        return true
    end

    EventCooldowns[source][eventName] = now
    return false
end

-- Server-side validation: Check if player is valid tow driver
local function ValidateTowDriver(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false, 'Invalid player' end

    local job = Player.PlayerData.job
    if not job or job.name ~= Config.JobName then
        return false, 'Not a tow driver'
    end

    if not DutyTracker[source] then
        return false, 'Not on duty'
    end

    return true, Player
end

-- Server-side validation: Verify player distance from coords
local function ValidateDistance(source, targetCoords, maxDistance)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    local playerCoords = GetEntityCoords(ped)
    local dist = #(playerCoords - vector3(targetCoords.x, targetCoords.y, targetCoords.z))

    return dist <= maxDistance
end

-- Initialize shop wait times
CreateThread(function()
    Wait(1000)
    for shopId, _ in pairs(Config.ShopJobMapping) do
        ShopWaitTimes[shopId] = 0
    end
    TowJob.Debug('Server initialized')
end)

-- Get player job
local function GetPlayerJob(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil end
    return Player.PlayerData.job
end

-- Check if player is tow driver
local function IsTowDriver(source)
    local job = GetPlayerJob(source)
    return job and job.name == Config.JobName
end

-- Get available tow drivers
function GetAvailableDrivers()
    local available = {}
    for src, duty in pairs(DutyTracker) do
        if duty.state == TowJob.DriverState.AVAILABLE then
            available[#available + 1] = {
                source = src,
                shop = duty.shop,
                clockedInAt = duty.clockedInAt,
                lastTowCompleted = duty.lastTowCompleted,
                rating = DriverRatings[src] or 100
            }
        end
    end
    -- Sort by clockedInAt (longest waiting first)
    table.sort(available, function(a, b)
        return (a.lastTowCompleted or a.clockedInAt) < (b.lastTowCompleted or b.clockedInAt)
    end)
    return available
end

-- Get queue length
function GetQueueLength()
    return #TowQueue
end

-- Get driver reliability rating
function GetDriverRating(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return 100 end

    local citizenid = Player.PlayerData.citizenid

    if DriverRatings[citizenid] then
        return DriverRatings[citizenid]
    end

    -- Load from database
    local result = MySQL.single.await([[
        SELECT reliability_rating FROM tow_driver_stats WHERE citizenid = ?
    ]], { citizenid })

    local rating = result and result.reliability_rating or 100
    DriverRatings[citizenid] = rating
    return rating
end

-- Update driver reliability rating
function UpdateDriverRating(source, change, reason)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local currentRating = GetDriverRating(source)
    local newRating = math.max(0, math.min(150, currentRating + change))

    DriverRatings[citizenid] = newRating

    MySQL.update.await([[
        INSERT INTO tow_driver_stats (citizenid, reliability_rating)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE reliability_rating = ?
    ]], { citizenid, newRating, newRating })

    if change > 0 then
        lib.notify(source, {
            title = 'Rating Increased',
            description = string.format('+%d rating (%s)', change, reason),
            type = 'success'
        })
    elseif change < 0 then
        lib.notify(source, {
            title = 'Rating Decreased',
            description = string.format('%d rating (%s)', change, reason),
            type = 'error'
        })
    end

    TowJob.Debug('Rating update:', citizenid, change, 'new:', newRating)
end

-- Server exports
exports('GetAvailableDrivers', GetAvailableDrivers)
exports('GetQueueLength', GetQueueLength)
exports('IsTowDriver', IsTowDriver)
exports('GetDriverRating', GetDriverRating)
exports('UpdateDriverRating', UpdateDriverRating)
exports('ValidateTowDriver', ValidateTowDriver)

-- Get driver's current assignment
exports('GetDriverAssignment', function(source)
    return ActiveJobs[source]
end)

-- Get shop on-duty count
exports('GetShopOnDutyCount', function(shopId)
    local count = 0
    for src, duty in pairs(DutyTracker) do
        if duty.shop == shopId then
            count = count + 1
        end
    end
    return count
end)

-- Player disconnect handling
AddEventHandler('playerDropped', function()
    local source = source

    -- Clean up cooldowns
    EventCooldowns[source] = nil

    -- Capture duty data before clearing (need citizenid for rating penalty)
    local dutyData = DutyTracker[source]

    -- Clean up duty tracker
    if dutyData then
        TowJob.Debug('Driver disconnected:', source)
        DutyTracker[source] = nil
    end

    -- Handle active job cancellation
    if ActiveJobs[source] then
        local job = ActiveJobs[source]

        -- Penalize rating using cached citizenid (player object is gone)
        local citizenid = dutyData and dutyData.citizenid
        if citizenid then
            local currentRating = DriverRatings[citizenid] or 100
            local newRating = math.max(0, math.min(150, currentRating - 5))
            DriverRatings[citizenid] = newRating
            MySQL.update([[
                INSERT INTO tow_driver_stats (citizenid, reliability_rating)
                VALUES (?, ?)
                ON DUPLICATE KEY UPDATE reliability_rating = ?
            ]], { citizenid, newRating, newRating })
            TowJob.Debug('Disconnect rating penalty applied:', citizenid, '-5 ->', newRating)
        end

        -- Requeue the job
        job.state = TowJob.JobState.QUEUED
        job.assignedTo = nil
        table.insert(TowQueue, 1, job)
        ActiveJobs[source] = nil
        TowJob.Debug('Requeued job from disconnected driver:', job.id)
    end
end)

-- Resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    MySQL.ready(function()
        -- Create tow jobs table
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS `tow_jobs` (
                `id` VARCHAR(20) PRIMARY KEY,
                `type` VARCHAR(20) NOT NULL,
                `priority` INT DEFAULT 2,
                `pickup_coords` VARCHAR(100) NOT NULL,
                `dropoff_coords` VARCHAR(100),
                `dropoff_impound` VARCHAR(50),
                `vehicle_plate` VARCHAR(10),
                `vehicle_model` VARCHAR(50),
                `requester_id` VARCHAR(50),
                `driver_id` VARCHAR(50),
                `shop_id` VARCHAR(50),
                `state` VARCHAR(20) DEFAULT 'queued',
                `payment` INT DEFAULT 0,
                `damage_on_pickup` INT DEFAULT 0,
                `damage_on_dropoff` INT DEFAULT 0,
                `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                `completed_at` TIMESTAMP NULL,
                INDEX `state` (`state`),
                INDEX `driver_id` (`driver_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])

        -- Create service tickets table
        MySQL.query([[
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
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])

        -- Create shop transactions table
        MySQL.query([[
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
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])

        -- Create driver earnings table
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS `tow_driver_earnings` (
                `citizenid` VARCHAR(50) PRIMARY KEY,
                `shop` VARCHAR(50) NOT NULL,
                `total_earned` INT DEFAULT 0,
                `uncollected` INT DEFAULT 0,
                `total_jobs` INT DEFAULT 0,
                `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])

        -- Create/update driver stats table with reliability rating
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS `tow_driver_stats` (
                `citizenid` VARCHAR(50) PRIMARY KEY,
                `total_jobs_completed` INT DEFAULT 0,
                `total_miles_driven` FLOAT DEFAULT 0,
                `total_earned` INT DEFAULT 0,
                `reliability_rating` INT DEFAULT 100,
                `damage_free_tows` INT DEFAULT 0,
                `luxury_unlocked` BOOLEAN DEFAULT FALSE,
                `pve_jobs` INT DEFAULT 0,
                `customer_jobs` INT DEFAULT 0,
                `police_jobs` INT DEFAULT 0,
                `ems_jobs` INT DEFAULT 0,
                `cancelled_jobs` INT DEFAULT 0,
                `average_completion_time` INT DEFAULT 0,
                `fastest_completion` INT DEFAULT 0,
                `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])

        -- Create impound tracking table
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS `tow_impound_vehicles` (
                `plate` VARCHAR(10) PRIMARY KEY,
                `impound_lot` VARCHAR(50) NOT NULL,
                `towed_by` VARCHAR(50) NOT NULL,
                `tow_job_id` VARCHAR(20),
                `reason` VARCHAR(255),
                `fee_base` INT DEFAULT 0,
                `fee_per_day` INT DEFAULT 0,
                `impounded_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                `released_at` TIMESTAMP NULL,
                `released_by` VARCHAR(50) NULL,
                INDEX `impound_lot` (`impound_lot`),
                INDEX `impounded_at` (`impounded_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])

        TowJob.Debug('Database tables initialized')
    end)
end)

-- Callbacks with validation
lib.callback.register('dps-towjob:server:getQueueInfo', function(source)
    local valid, _ = ValidateTowDriver(source)
    if not valid then return nil end

    return {
        queue = TowQueue,
        length = #TowQueue,
        activeJobs = ActiveJobs,
        drivers = GetAvailableDrivers()
    }
end)

lib.callback.register('dps-towjob:server:getDriverStatus', function(source)
    local duty = DutyTracker[source]
    local activeJob = ActiveJobs[source]

    return {
        onDuty = duty ~= nil,
        state = duty and duty.state or TowJob.DriverState.OFF_DUTY,
        shop = duty and duty.shop or nil,
        activeJob = activeJob,
        rating = GetDriverRating(source)
    }
end)

lib.callback.register('dps-towjob:server:canClockIn', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false, 'Player not found' end

    local job = Player.PlayerData.job
    if job.name ~= Config.JobName then
        return false, 'Not a tow driver'
    end

    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.towShop then
        return false, 'Invalid shop'
    end

    -- Validate player is near the shop
    if not ValidateDistance(source, shop.depot, 10.0) then
        return false, 'Too far from depot'
    end

    return true
end)

-- Track impound vehicle location
RegisterNetEvent('dps-towjob:server:impoundVehicle', function(plate, impoundId)
    local source = source

    -- Validate
    if IsOnCooldown(source, 'completeJob') then return end

    local valid, Player = ValidateTowDriver(source)
    if not valid then return end

    local impound = Config.ImpoundLots[impoundId]
    if not impound then
        lib.notify(source, { title = 'Error', description = 'Invalid impound lot', type = 'error' })
        return
    end

    -- Validate distance to impound
    if not ValidateDistance(source, impound.dropoff, 15.0) then
        lib.notify(source, { title = 'Error', description = 'Too far from impound', type = 'error' })
        return
    end

    local citizenid = Player.PlayerData.citizenid
    local job = ActiveJobs[source]

    -- Store in impound tracking
    MySQL.insert.await([[
        INSERT INTO tow_impound_vehicles (plate, impound_lot, towed_by, tow_job_id, fee_base, fee_per_day)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            impound_lot = VALUES(impound_lot),
            towed_by = VALUES(towed_by),
            tow_job_id = VALUES(tow_job_id),
            impounded_at = CURRENT_TIMESTAMP,
            released_at = NULL,
            released_by = NULL
    ]], {
        plate,
        impoundId,
        citizenid,
        job and job.id or nil,
        impound.fee.base,
        impound.fee.perDay
    })

    -- Update player_vehicles state
    MySQL.update.await([[
        UPDATE player_vehicles SET state = 2 WHERE plate = ?
    ]], { plate })

    TowJob.Debug('Vehicle impounded:', plate, 'at', impoundId)
end)

-- Get vehicle impound location
lib.callback.register('dps-towjob:server:getVehicleImpound', function(source, plate)
    local result = MySQL.single.await([[
        SELECT * FROM tow_impound_vehicles WHERE plate = ? AND released_at IS NULL
    ]], { plate })

    if result then
        return {
            lot = result.impound_lot,
            impoundedAt = result.impounded_at,
            feeBase = result.fee_base,
            feePerDay = result.fee_per_day
        }
    end

    return nil
end)

-- Debug command
if Config.Debug then
    RegisterCommand('towdebug', function(source)
        if source ~= 0 then return end
        print('=== TOW DEBUG ===')
        print('Queue:', json.encode(TowQueue))
        print('Active Jobs:', json.encode(ActiveJobs))
        print('Duty Tracker:', json.encode(DutyTracker))
        print('Cooldowns:', json.encode(EventCooldowns))
        print('=================')
    end, false)
end

-- Export cooldown checker for other server files
function CheckCooldown(source, eventName)
    return IsOnCooldown(source, eventName)
end

exports('CheckCooldown', CheckCooldown)
