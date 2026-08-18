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
            -- Server-authoritative settlement payout (C3). The NPC settlement
            -- the driver receives is computed here from the job's commission,
            -- NOT from any client-supplied amount.
            settlementMultiplier = 1.75, -- payout = commission * this
            settlementMax = 400,         -- hard cap on a single settlement
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

-- ActivePVE.* are hash-keyed by id, so # is always 0; count keys for the caps.
local function CountPVE(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Generate random plate
local function GeneratePlate()
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    local nums = '0123456789'
    local plate = ''
    for i = 1, 3 do
        local n = math.random(#chars)
        plate = plate .. chars:sub(n, n)
    end
    plate = plate .. ' '
    for i = 1, 4 do
        local n = math.random(#nums)
        plate = plate .. nums:sub(n, n)
    end
    return plate
end

-- Spawn NPC breakdown
local function SpawnBreakdown()
    if CountPVE(ActivePVE.breakdowns) >= PVEConfig.breakdowns.maxActive then return end

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
    if CountPVE(ActivePVE.predatory) >= PVEConfig.predatory.maxActive then return end

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

    -- Once-per-job gate: a client could otherwise spam this callback to
    -- re-roll the dispute until it triggers, then collect the settlement
    -- payout without ever completing the tow.
    local gateJob = ActiveJobs and ActiveJobs[source]
    if gateJob then
        if gateJob.disputeChecked then return { triggered = false } end
        gateJob.disputeChecked = true
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

    -- Server-side dispute gate (C3/C4): only mark a dispute active when the
    -- driver actually has this predatory job active. disputeBonus and
    -- settlementPaid require these flags, so a client cannot mint cash by
    -- firing those events without a server-sanctioned dispute.
    local activeJob = ActiveJobs and ActiveJobs[source]
    if activeJob and activeJob.id == jobId and activeJob.type == 'predatory' then
        activeJob.disputeActive = true
        activeJob.disputeBonusPaid = false
        activeJob.settled = false
    end

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

    -- Validate/clamp amount: must be positive and within the configured bribe
    -- range. Prevents a negative "removal" from crediting the player.
    amount = tonumber(amount)
    if not amount or amount <= 0 then return end
    amount = math.floor(math.min(amount, PVEConfig.predatory.dispute.bribeRange[2]))

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

-- Dispute bonus payment (C4)
-- Requires a server-sanctioned active predatory dispute, and pays at most once.
RegisterNetEvent('dps-towjob:server:disputeBonus', function(jobId, reason)
    local source = source

    local job = ActiveJobs and ActiveJobs[source]
    if not job or job.id ~= jobId or job.type ~= 'predatory' then
        TowJob.Debug('disputeBonus rejected: no matching predatory job', source, jobId)
        return
    end
    if not job.disputeActive then
        TowJob.Debug('disputeBonus rejected: no active dispute', source, jobId)
        return
    end
    if job.disputeBonusPaid then
        TowJob.Debug('disputeBonus rejected: already paid', source, jobId)
        return
    end

    -- Mark paid BEFORE granting money (idempotency)
    job.disputeBonusPaid = true

    local bonus = PVEConfig.predatory.dispute.bonusOnSuccess or 25
    Bridge.AddMoney(source, 'cash', bonus)

    -- Log the outcome
    local citizenid = Bridge.GetIdentifier(source)
    MySQL.insert([[
        INSERT INTO tow_dispute_logs (job_id, driver_id, outcome, resolved_at)
        VALUES (?, ?, 'talked_down', NOW())
    ]], { jobId, citizenid })

    TowJob.Debug('Dispute bonus paid:', source, bonus, reason)
end)

-- Settlement payment (NPC pays to keep their car) (C3)
-- Server recomputes the payout from the job's commission; the client-sent
-- amount is IGNORED. Requires an active dispute; pays once per job.
RegisterNetEvent('dps-towjob:server:settlementPaid', function(jobId, _clientAmount)
    local source = source

    local job = ActiveJobs and ActiveJobs[source]
    if not job or job.id ~= jobId or job.type ~= 'predatory' then
        TowJob.Debug('settlement rejected: no matching predatory job', source, jobId)
        return
    end
    if not job.disputeActive then
        TowJob.Debug('settlement rejected: no active dispute', source, jobId)
        return
    end
    if job.settled then
        TowJob.Debug('settlement rejected: already settled', source, jobId)
        return
    end

    -- Consume the dispute and mark settled BEFORE paying (idempotency)
    job.settled = true
    job.disputeActive = false

    -- Server-authoritative settlement amount from config + job commission
    local commission = tonumber(job.commission) or PVEConfig.predatory.commission
    local dispute = PVEConfig.predatory.dispute
    local amount = math.floor(commission * (dispute.settlementMultiplier or 1.75))
    amount = math.max(0, math.min(amount, dispute.settlementMax or 400))

    -- Pay the driver
    Bridge.AddMoney(source, 'cash', amount)

    -- Close out the job (vehicle released)
    ActiveJobs[source] = nil
    if DutyTracker and DutyTracker[source] then
        DutyTracker[source].state = TowJob.DriverState.AVAILABLE
    end

    -- Update database - mark as settled
    MySQL.update.await([[
        UPDATE tow_jobs SET state = 'settled', payment = ? WHERE id = ?
    ]], { amount, jobId })

    -- Log the settlement outcome
    local citizenid = Bridge.GetIdentifier(source)
    MySQL.insert([[
        INSERT INTO tow_dispute_logs (job_id, driver_id, outcome, settlement_amount, resolved_at)
        VALUES (?, ?, 'settlement', ?, NOW())
    ]], { jobId, citizenid, amount })

    -- Remove from PVE tracking
    for pveId, data in pairs(ActivePVE.predatory) do
        if data.jobId == jobId then
            ActivePVE.predatory[pveId] = nil
            break
        end
    end

    TowJob.Debug('Settlement paid (server-computed):', source, amount, jobId)

    -- Check queue for next job
    TriggerEvent('dps-towjob:server:checkQueue')
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

-- ============================================
-- POLICE INTEGRATION
-- ============================================

-- Track active disputes for police
local ActiveDisputes = {}

-- Police alert when NPC calls cops
RegisterNetEvent('dps-towjob:server:policeAlert', function(data)
    local source = source
    local alertData = {
        type = data.type or 'dispute',
        reason = data.reason or 'Vehicle owner dispute',
        coords = data.coords,
        street = data.street or 'Unknown Location',
        vehiclePlate = data.vehiclePlate,
        reportedBy = 'Civilian',
        towDriver = source,
        timestamp = os.time()
    }

    -- Store for reference
    local alertId = TowJob.GenerateId()
    ActiveDisputes[alertId] = alertData

    -- Try qs-dispatch integration first
    if Bridge.Resources.dispatch then
        TriggerEvent('qs-dispatch:server:CreateDispatchCall', {
            job = 'police',
            callLocation = data.coords,
            callCode = { code = '10-10', flash = false },
            message = 'Tow Truck Dispute',
            description = data.reason .. ' at ' .. data.street,
            units = {},
            time = 10,
            blip = {
                sprite = 477,
                scale = 1.0,
                colour = 1,
                flashes = true,
                text = 'Dispute in Progress',
                time = 120
            }
        })
        TowJob.Debug('Police alert sent via qs-dispatch:', alertId)
    else
        -- Fallback: Alert all on-duty police manually
        AlertPoliceUnits(alertData)
    end

    -- Log for records
    TowJob.Debug('Police alert triggered:', alertId, data.reason)
end)

-- Alert police units (fallback when qs-dispatch not available)
function AlertPoliceUnits(alertData)
    local policeJobs = { 'police', 'bcso', 'sasp', 'sahp', 'lspd', 'sast' }

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local player = Bridge.GetPlayer(src)

        if player then
            local job = Bridge.GetPlayerJob(src)
            local isPolice = false

            for _, pJob in ipairs(policeJobs) do
                if job and job.name == pJob then
                    isPolice = true
                    break
                end
            end

            if isPolice then
                -- Send notification
                Bridge.Notify(src, '🚔 Dispatch', alertData.reason .. ' at ' .. alertData.street, 'inform', 10000)

                -- Send blip coordinates
                TriggerClientEvent('dps-towjob:client:policeBlip', src, {
                    coords = alertData.coords,
                    duration = 120000, -- 2 minutes
                    sprite = 477,
                    color = 1,
                    label = 'Dispute - ' .. alertData.street
                })
            end
        end
    end
end

-- NPC started fighting notification
RegisterNetEvent('dps-towjob:server:npcFighting', function(data)
    local source = source
    local coords = data.coords

    -- Store fighting NPC info
    local fightId = TowJob.GenerateId()
    ActiveDisputes[fightId] = {
        type = 'assault',
        netId = data.netId,
        coords = coords,
        jobId = data.jobId,
        towDriver = source,
        timestamp = os.time()
    }

    TowJob.Debug('NPC fighting reported:', fightId, 'NetID:', data.netId)
end)

-- NPC arrested notification
RegisterNetEvent('dps-towjob:server:npcArrested', function(data)
    local source = source

    -- Find and remove from active disputes
    for id, dispute in pairs(ActiveDisputes) do
        if dispute.netId == data.netId then
            ActiveDisputes[id] = nil

            -- Log arrest in database
            MySQL.insert.await([[
                INSERT INTO tow_dispute_logs (job_id, outcome, officer_source, resolved_at)
                VALUES (?, 'arrested', ?, NOW())
            ]], { data.jobId or 'unknown', source })

            TowJob.Debug('NPC arrested by officer:', source, 'Dispute:', id)
            break
        end
    end

    -- Notify the tow driver if different from arresting officer
    local driver = nil
    for id, dispute in pairs(ActiveDisputes) do
        if dispute.jobId == data.jobId then
            driver = dispute.towDriver
            break
        end
    end

    if driver and driver ~= source then
        Bridge.Notify(driver, '🚔 Police', 'The suspect has been arrested', 'success')
    end
end)

-- Client event for police blip
-- This should be registered on client side, but adding the handler pattern here
AddEventHandler('dps-towjob:server:requestPoliceBlip', function(src, coords)
    TriggerClientEvent('dps-towjob:client:policeBlip', src, {
        coords = coords,
        duration = 120000,
        sprite = 477,
        color = 1,
        label = 'Active Dispute'
    })
end)

-- Cleanup old disputes periodically
CreateThread(function()
    while true do
        Wait(300000) -- Every 5 minutes

        local now = os.time()
        local maxAge = 600 -- 10 minutes

        for id, dispute in pairs(ActiveDisputes) do
            if now - dispute.timestamp > maxAge then
                ActiveDisputes[id] = nil
                TowJob.Debug('Cleaned up old dispute:', id)
            end
        end
    end
end)
