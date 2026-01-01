--[[
    dps-towjob Server Main
    Core server initialization and exports
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- State tables
TowQueue = {}           -- Active tow queue
ActiveJobs = {}         -- Jobs currently being worked
DutyTracker = {}        -- Drivers on duty
ShopWaitTimes = {}      -- Track wait times per shop
DriverEarnings = {}     -- Track uncollected earnings

-- Initialize shop wait times
CreateThread(function()
    Wait(1000) -- Wait for config to load
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
            table.insert(available, {
                source = src,
                shop = duty.shop,
                clockedInAt = duty.clockedInAt,
                lastTowCompleted = duty.lastTowCompleted
            })
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

-- Server exports
exports('GetAvailableDrivers', GetAvailableDrivers)
exports('GetQueueLength', GetQueueLength)
exports('IsTowDriver', IsTowDriver)

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

    -- Clean up duty tracker
    if DutyTracker[source] then
        TowJob.Debug('Driver disconnected:', source)
        DutyTracker[source] = nil
    end

    -- Handle active job cancellation
    if ActiveJobs[source] then
        local job = ActiveJobs[source]
        -- Requeue the job
        job.state = TowJob.JobState.QUEUED
        job.assignedTo = nil
        table.insert(TowQueue, 1, job) -- Add back to front of queue
        ActiveJobs[source] = nil
        TowJob.Debug('Requeued job from disconnected driver:', job.id)
    end
end)

-- Resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    -- Initialize database tables
    MySQL.ready(function()
        -- Create tow jobs table
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS `tow_jobs` (
                `id` VARCHAR(20) PRIMARY KEY,
                `type` VARCHAR(20) NOT NULL,
                `priority` INT DEFAULT 2,
                `pickup_coords` VARCHAR(100) NOT NULL,
                `dropoff_coords` VARCHAR(100),
                `vehicle_plate` VARCHAR(10),
                `vehicle_model` VARCHAR(50),
                `requester_id` VARCHAR(50),
                `driver_id` VARCHAR(50),
                `shop_id` VARCHAR(50),
                `state` VARCHAR(20) DEFAULT 'queued',
                `payment` INT DEFAULT 0,
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

        TowJob.Debug('Database tables initialized')
    end)
end)

-- Callbacks
lib.callback.register('dps-towjob:server:getQueueInfo', function(source)
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
        activeJob = activeJob
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

    return true
end)

-- Debug command
if Config.Debug then
    RegisterCommand('towdebug', function(source)
        if source ~= 0 then return end -- Server console only
        print('=== TOW DEBUG ===')
        print('Queue:', json.encode(TowQueue))
        print('Active Jobs:', json.encode(ActiveJobs))
        print('Duty Tracker:', json.encode(DutyTracker))
        print('=================')
    end, false)
end
