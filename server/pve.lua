--[[
    dps-towjob Server PVE
    Enhanced NPC system with "Predatory" towing
]]

-- PVE Configuration (extends Config.Queue)
local PVEConfig = {
    -- Standard NPC breakdowns
    breakdowns = {
        enabled = true,
        interval = 300000,      -- 5 minutes
        maxActive = 3,
        payMultiplier = 0.8,    -- 80% of normal pay
    },

    -- Predatory towing (illegally parked NPCs)
    predatory = {
        enabled = true,
        interval = 180000,      -- 3 minutes
        maxActive = 5,
        commission = 75,        -- Base commission per tow
        bonusZones = {          -- Higher pay in these areas
            ['downtown'] = 1.5,
            ['airport'] = 2.0,
            ['casino'] = 1.75,
        },
        -- NPC Dispute system - angry owners!
        dispute = {
            enabled = true,
            chance = 0.15,          -- 15% chance of angry owner
            fightChance = 0.30,     -- 30% of disputes turn violent
            bribeRange = { 50, 150 }, -- Bribe amount range
            bonusOnSuccess = 25,    -- Extra $ if you handle dispute
        }
    },

    -- Random breakdown locations
    breakdownLocations = {
        vector4(-200.0, -1000.0, 29.0, 180.0),
        vector4(400.0, -1200.0, 29.0, 90.0),
        vector4(-500.0, -300.0, 35.0, 270.0),
        vector4(100.0, -700.0, 31.0, 0.0),
        vector4(-1100.0, -1500.0, 4.5, 45.0),
        vector4(800.0, -500.0, 30.0, 135.0),
        vector4(-350.0, -900.0, 31.0, 200.0),
        vector4(250.0, -350.0, 45.0, 280.0),
    },

    -- Illegal parking zones (for predatory towing)
    illegalParkingZones = {
        -- Fire hydrants
        { coords = vector3(-254.0, -983.0, 29.0), radius = 3.0, reason = 'fire_hydrant' },
        { coords = vector3(-334.0, -713.0, 33.0), radius = 3.0, reason = 'fire_hydrant' },
        { coords = vector3(215.0, -805.0, 30.0), radius = 3.0, reason = 'fire_hydrant' },

        -- Red zones / No parking
        { coords = vector3(-1045.0, -2728.0, 13.0), radius = 10.0, reason = 'no_parking', zone = 'airport' },
        { coords = vector3(-1031.0, -2733.0, 20.0), radius = 8.0, reason = 'no_parking', zone = 'airport' },
        { coords = vector3(921.0, 46.0, 81.0), radius = 5.0, reason = 'no_parking', zone = 'casino' },

        -- Bus stops
        { coords = vector3(-261.0, -893.0, 31.0), radius = 4.0, reason = 'bus_stop' },
        { coords = vector3(-549.0, -188.0, 38.0), radius = 4.0, reason = 'bus_stop' },

        -- Handicapped zones (without permit)
        { coords = vector3(-710.0, -904.0, 19.0), radius = 3.0, reason = 'handicapped' },
        { coords = vector3(-817.0, -1078.0, 11.0), radius = 3.0, reason = 'handicapped' },

        -- Double parking areas
        { coords = vector3(-165.0, -1550.0, 35.0), radius = 6.0, reason = 'double_parked', zone = 'downtown' },
        { coords = vector3(315.0, -710.0, 29.0), radius = 6.0, reason = 'double_parked', zone = 'downtown' },
    },

    -- NPC vehicle models for spawning
    npcVehicles = {
        'sultan', 'buffalo', 'oracle', 'fugitive', 'tailgater',
        'exemplar', 'felon', 'jackal', 'zion', 'sentinel',
        'prairie', 'primo', 'ingot', 'stratum', 'stanier',
    },

    -- Violation reasons for display
    violationReasons = {
        ['fire_hydrant'] = 'Parked near fire hydrant',
        ['no_parking'] = 'Parked in no-parking zone',
        ['bus_stop'] = 'Parked at bus stop',
        ['handicapped'] = 'Parked in handicapped zone without permit',
        ['double_parked'] = 'Double parked / blocking traffic',
        ['expired_meter'] = 'Expired parking meter',
    }
}

-- Active PVE tracking
local ActivePVE = {
    breakdowns = {},
    predatory = {}
}

-- Generate random plate
local function GeneratePlate()
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    local nums = '0123456789'
    local plate = ''
    for i = 1, 3 do
        plate = plate .. chars:sub(math.random(#chars), math.random(#chars))
    end
    plate = plate .. ' '
    for i = 1, 4 do
        plate = plate .. nums:sub(math.random(#nums), math.random(#nums))
    end
    return plate
end

-- Spawn NPC breakdown
local function SpawnBreakdown()
    if #ActivePVE.breakdowns >= PVEConfig.breakdowns.maxActive then return end

    local availableDrivers = GetAvailableDrivers()
    if #availableDrivers == 0 then return end

    -- Pick random location
    local location = PVEConfig.breakdownLocations[math.random(#PVEConfig.breakdownLocations)]
    local vehicle = PVEConfig.npcVehicles[math.random(#PVEConfig.npcVehicles)]
    local plate = GeneratePlate()

    local breakdownId = TowJob.GenerateId()

    -- Add to queue
    local success, jobId = AddToQueue({
        type = TowJob.JobTypes.PVE,
        coords = vector3(location.x, location.y, location.z),
        model = vehicle,
        plate = plate,
        requesterId = 'SYSTEM_BREAKDOWN',
        requesterSource = nil,
        pveId = breakdownId
    })

    if success then
        ActivePVE.breakdowns[breakdownId] = {
            jobId = jobId,
            coords = location,
            vehicle = vehicle,
            plate = plate,
            createdAt = os.time()
        }

        TowJob.Debug('Spawned NPC breakdown:', breakdownId)
    end
end

-- Spawn predatory tow opportunity
local function SpawnPredatoryTow()
    if not PVEConfig.predatory.enabled then return end
    if #ActivePVE.predatory >= PVEConfig.predatory.maxActive then return end

    local availableDrivers = GetAvailableDrivers()
    if #availableDrivers == 0 then return end

    -- Pick random illegal parking zone
    local zone = PVEConfig.illegalParkingZones[math.random(#PVEConfig.illegalParkingZones)]
    local vehicle = PVEConfig.npcVehicles[math.random(#PVEConfig.npcVehicles)]
    local plate = GeneratePlate()

    local predatoryId = TowJob.GenerateId()

    -- Calculate commission with zone bonus
    local commission = PVEConfig.predatory.commission
    if zone.zone and PVEConfig.predatory.bonusZones[zone.zone] then
        commission = math.floor(commission * PVEConfig.predatory.bonusZones[zone.zone])
    end

    -- Add to queue as low priority
    local success, jobId = AddToQueue({
        type = 'predatory',
        priority = TowJob.Priority.LOW,
        coords = zone.coords,
        model = vehicle,
        plate = plate,
        requesterId = 'SYSTEM_PREDATORY',
        requesterSource = nil,
        pveId = predatoryId,
        violation = zone.reason,
        violationText = PVEConfig.violationReasons[zone.reason] or 'Illegal parking',
        commission = commission
    })

    if success then
        ActivePVE.predatory[predatoryId] = {
            jobId = jobId,
            coords = zone.coords,
            vehicle = vehicle,
            plate = plate,
            violation = zone.reason,
            commission = commission,
            createdAt = os.time()
        }

        -- Notify on-duty drivers
        NotifyAllDrivers(
            'Illegal Parking',
            string.format('Vehicle spotted: %s ($%d commission)', PVEConfig.violationReasons[zone.reason], commission),
            'inform'
        )

        TowJob.Debug('Spawned predatory tow:', predatoryId, zone.reason)
    end
end

-- Notify all on-duty tow drivers
function NotifyAllDrivers(title, message, notifyType)
    for source, tracker in pairs(DutyTracker or {}) do
        if tracker.state ~= TowJob.DriverState.OFF_DUTY then
            Bridge.Notify(source, title, message, notifyType)
        end
    end
end

-- Cleanup expired PVE jobs
local function CleanupPVE()
    local now = os.time()
    local maxAge = 1800 -- 30 minutes

    for id, data in pairs(ActivePVE.breakdowns) do
        if now - data.createdAt > maxAge then
            -- Remove from queue if still there
            for i, job in ipairs(TowQueue or {}) do
                if job.pveId == id then
                    table.remove(TowQueue, i)
                    break
                end
            end
            ActivePVE.breakdowns[id] = nil
            TowJob.Debug('Cleaned up expired breakdown:', id)
        end
    end

    for id, data in pairs(ActivePVE.predatory) do
        if now - data.createdAt > maxAge then
            for i, job in ipairs(TowQueue or {}) do
                if job.pveId == id then
                    table.remove(TowQueue, i)
                    break
                end
            end
            ActivePVE.predatory[id] = nil
            TowJob.Debug('Cleaned up expired predatory:', id)
        end
    end
end

-- PVE job completed handler
RegisterNetEvent('dps-towjob:server:pveCompleted', function(pveId, pveType)
    if pveType == 'breakdown' then
        ActivePVE.breakdowns[pveId] = nil
    elseif pveType == 'predatory' then
        ActivePVE.predatory[pveId] = nil
    end
end)

-- ============================================
-- DISPUTE SYSTEM
-- ============================================

-- Check if dispute should trigger for predatory tow
lib.callback.register('dps-towjob:server:checkDispute', function(source, jobId)
    if not PVEConfig.predatory.dispute.enabled then
        return { triggered = false }
    end

    -- Find the job
    local job = nil
    for _, j in ipairs(TowQueue or {}) do
        if j.id == jobId and j.type == 'predatory' then
            job = j
            break
        end
    end

    if not job then
        job = ActiveJobs and ActiveJobs[source]
    end

    if not job or job.type ~= 'predatory' then
        return { triggered = false }
    end

    -- Roll for dispute
    local disputeChance = PVEConfig.predatory.dispute.chance
    local triggered = math.random() < disputeChance

    if not triggered then
        return { triggered = false }
    end

    -- Determine if fight will happen
    local willFight = math.random() < PVEConfig.predatory.dispute.fightChance

    -- Generate bribe amount
    local bribeMin = PVEConfig.predatory.dispute.bribeRange[1]
    local bribeMax = PVEConfig.predatory.dispute.bribeRange[2]
    local bribeAmount = math.random(bribeMin, bribeMax)

    TowJob.Debug('Dispute triggered for job:', jobId, 'willFight:', willFight)

    return {
        triggered = true,
        willFight = willFight,
        bribeAmount = bribeAmount
    }
end)

-- Check if player has money for bribe
lib.callback.register('dps-towjob:server:checkMoney', function(source, amount)
    return Bridge.GetMoney(source, 'cash') >= amount or Bridge.GetMoney(source, 'bank') >= amount
end)

-- Pay bribe to angry owner
RegisterNetEvent('dps-towjob:server:payBribe', function(jobId, amount)
    local source = source

    -- Try cash first, then bank
    if Bridge.GetMoney(source, 'cash') >= amount then
        Bridge.RemoveMoney(source, 'cash', amount)
    elseif Bridge.GetMoney(source, 'bank') >= amount then
        Bridge.RemoveMoney(source, 'bank', amount)
    else
        Bridge.Notify(source, 'Dispute', 'Insufficient funds', 'error')
        return
    end

    TowJob.Debug('Player paid bribe:', source, amount)
end)

-- Dispute bonus payment
RegisterNetEvent('dps-towjob:server:disputeBonus', function(jobId, reason)
    local source = source
    local bonus = PVEConfig.predatory.dispute.bonusOnSuccess or 25

    -- Add bonus to earnings
    Bridge.AddMoney(source, 'cash', bonus)

    TowJob.Debug('Dispute bonus paid:', source, bonus, reason)
end)

-- Main PVE spawn loop
if Config.Queue and Config.Queue.pveEnabled then
    CreateThread(function()
        Wait(10000) -- Wait 10s after start

        while true do
            -- Spawn breakdowns
            if PVEConfig.breakdowns.enabled then
                SpawnBreakdown()
            end

            Wait(PVEConfig.breakdowns.interval)
        end
    end)

    CreateThread(function()
        Wait(30000) -- Wait 30s after start

        while true do
            -- Spawn predatory opportunities
            if PVEConfig.predatory.enabled then
                SpawnPredatoryTow()
            end

            Wait(PVEConfig.predatory.interval)
        end
    end)

    -- Cleanup thread
    CreateThread(function()
        while true do
            Wait(300000) -- Every 5 minutes
            CleanupPVE()
        end
    end)
end

-- Get PVE stats
function GetPVEStats()
    local stats = {
        breakdowns = {
            active = 0,
            completed = 0
        },
        predatory = {
            active = 0,
            completed = 0
        }
    }

    for _ in pairs(ActivePVE.breakdowns) do
        stats.breakdowns.active = stats.breakdowns.active + 1
    end

    for _ in pairs(ActivePVE.predatory) do
        stats.predatory.active = stats.predatory.active + 1
    end

    -- Get completed from database
    local result = MySQL.query.await([[
        SELECT
            SUM(CASE WHEN type = 'pve' AND state = 'completed' THEN 1 ELSE 0 END) as breakdowns,
            SUM(CASE WHEN type = 'predatory' AND state = 'completed' THEN 1 ELSE 0 END) as predatory
        FROM tow_jobs
        WHERE DATE(completed_at) = CURDATE()
    ]])

    if result and result[1] then
        stats.breakdowns.completed = result[1].breakdowns or 0
        stats.predatory.completed = result[1].predatory or 0
    end

    return stats
end

exports('GetPVEStats', GetPVEStats)

-- Server callback for dispatch data
lib.callback.register('dps-towjob:server:getDispatchData', function(source)
    local queueData = {}
    local activeData = {}
    local driverData = {}

    -- Format queue
    for _, job in ipairs(TowQueue or {}) do
        table.insert(queueData, {
            id = job.id,
            type = job.type,
            priority = job.priority,
            zone = job.zone,
            vehicleModel = job.vehicleModel,
            vehiclePlate = job.vehiclePlate,
            createdAt = job.createdAt,
            violation = job.violation,
            violationText = job.violationText
        })
    end

    -- Format active jobs
    for src, job in pairs(ActiveJobs or {}) do
        local player = Bridge.GetPlayer(src)
        table.insert(activeData, {
            id = job.id,
            driverName = player and Bridge.GetPlayerName(src) or 'Unknown',
            state = job.state,
            zone = job.zone,
            vehiclePlate = job.vehiclePlate,
            progress = job.progress or 0
        })
    end

    -- Format drivers
    for src, tracker in pairs(DutyTracker or {}) do
        local player = Bridge.GetPlayer(src)
        if player then
            table.insert(driverData, {
                source = src,
                name = Bridge.GetPlayerName(src),
                shop = tracker.shop,
                state = tracker.state
            })
        end
    end

    -- Get today's stats
    local stats = {
        completed = 0,
        earnings = 0,
        pve = 0,
        impound = 0
    }

    local result = MySQL.query.await([[
        SELECT
            COUNT(*) as completed,
            COALESCE(SUM(payment), 0) as earnings,
            SUM(CASE WHEN type IN ('pve', 'predatory') THEN 1 ELSE 0 END) as pve,
            SUM(CASE WHEN dropoff_impound IS NOT NULL THEN 1 ELSE 0 END) as impound
        FROM tow_jobs
        WHERE state = 'completed' AND DATE(completed_at) = CURDATE()
    ]])

    if result and result[1] then
        stats.completed = result[1].completed or 0
        stats.earnings = result[1].earnings or 0
        stats.pve = result[1].pve or 0
        stats.impound = result[1].impound or 0
    end

    return {
        queue = queueData,
        activeJobs = activeData,
        drivers = driverData,
        stats = stats
    }
end)

-- Get job coords for waypoint
lib.callback.register('dps-towjob:server:getJobCoords', function(source, jobId)
    for _, job in ipairs(TowQueue or {}) do
        if job.id == jobId then
            return job.pickupCoords
        end
    end
    return nil
end)
