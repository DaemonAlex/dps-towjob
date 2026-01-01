--[[
    dps-towjob Server Queue
    Queue management and job distribution
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Add job to queue
function AddToQueue(request)
    if #TowQueue >= Config.Queue.maxSize then
        TowJob.Debug('Queue full, rejecting request')
        return false, 'Queue full'
    end

    local job = {
        id = TowJob.GenerateId(),
        type = request.type or TowJob.JobTypes.CUSTOMER,
        priority = request.priority or TowJob.GetPriority(request.type),
        pickupCoords = request.coords,
        dropoffCoords = request.dropoff,
        vehiclePlate = request.plate,
        vehicleModel = request.model,
        requesterId = request.requesterId,
        requesterSource = request.requesterSource,
        state = TowJob.JobState.QUEUED,
        assignedTo = nil,
        createdAt = os.time(),
        zone = TowJob.GetZoneName(request.coords)
    }

    -- Insert based on priority
    local inserted = false
    for i, queuedJob in ipairs(TowQueue) do
        if job.priority > queuedJob.priority then
            table.insert(TowQueue, i, job)
            inserted = true
            break
        end
    end

    if not inserted then
        table.insert(TowQueue, job)
    end

    TowJob.Debug('Job added to queue:', job.id, job.type)

    -- Store in database
    MySQL.insert.await([[
        INSERT INTO tow_jobs (id, type, priority, pickup_coords, dropoff_coords, vehicle_plate, vehicle_model, requester_id, state)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        job.id,
        job.type,
        job.priority,
        json.encode(job.pickupCoords),
        job.dropoffCoords and json.encode(job.dropoffCoords) or nil,
        job.vehiclePlate,
        job.vehicleModel,
        job.requesterId,
        job.state
    })

    -- Check for available drivers
    TriggerEvent('dps-towjob:server:checkQueue')

    return true, job.id
end

exports('AddToQueue', AddToQueue)

-- Request tow (main entry point)
exports('RequestTow', function(source, coords, towType, priority)
    local Player = source and QBCore.Functions.GetPlayer(source)

    return AddToQueue({
        type = towType or TowJob.JobTypes.CUSTOMER,
        priority = priority,
        coords = coords,
        requesterId = Player and Player.PlayerData.citizenid or nil,
        requesterSource = source
    })
end)

-- Check queue for available assignments
RegisterNetEvent('dps-towjob:server:checkQueue', function()
    if #TowQueue == 0 then return end

    local availableDrivers = GetAvailableDrivers()
    if #availableDrivers == 0 then return end

    for _, driver in ipairs(availableDrivers) do
        if #TowQueue == 0 then break end

        local job = TowQueue[1]

        -- Check if driver on PVE should get PVP job
        if job.type ~= TowJob.JobTypes.PVE and DutyTracker[driver.source] then
            local currentJob = ActiveJobs[driver.source]
            if currentJob and currentJob.type == TowJob.JobTypes.PVE then
                -- Skip this driver, they're on PVE and there are other drivers
                if #availableDrivers > 1 then
                    goto continue
                end
            end
        end

        -- Assign job
        table.remove(TowQueue, 1)
        AssignJobToDriver(driver.source, job)

        ::continue::
    end
end)

-- Assign job to driver
function AssignJobToDriver(source, job)
    job.state = TowJob.JobState.ASSIGNED
    job.assignedTo = source
    job.assignedAt = os.time()

    ActiveJobs[source] = job
    DutyTracker[source].state = TowJob.DriverState.BUSY

    -- Update database
    MySQL.update.await([[
        UPDATE tow_jobs SET state = ?, driver_id = ? WHERE id = ?
    ]], {
        job.state,
        QBCore.Functions.GetPlayer(source).PlayerData.citizenid,
        job.id
    })

    -- Notify driver
    TriggerClientEvent('dps-towjob:client:jobAssigned', source, job)

    -- Notify requester if applicable
    if job.requesterSource then
        local Player = QBCore.Functions.GetPlayer(source)
        local driverName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname

        TriggerClientEvent('ox_lib:notify', job.requesterSource, {
            title = 'Tow Service',
            description = 'Driver ' .. driverName .. ' is en route',
            type = 'success'
        })
    end

    TowJob.Debug('Job assigned:', job.id, 'to driver:', source)
end

-- Driver accepts job
RegisterNetEvent('dps-towjob:server:acceptJob', function(jobId)
    local source = source
    local job = ActiveJobs[source]

    if not job or job.id ~= jobId then
        lib.notify(source, {
            title = 'Tow Job',
            description = 'Invalid job',
            type = 'error'
        })
        return
    end

    job.state = TowJob.JobState.EN_ROUTE

    MySQL.update.await([[
        UPDATE tow_jobs SET state = ? WHERE id = ?
    ]], { job.state, job.id })

    TriggerClientEvent('dps-towjob:client:jobStateChanged', source, job)
    TowJob.Debug('Job accepted:', job.id)
end)

-- Driver arrived on scene
RegisterNetEvent('dps-towjob:server:arrivedOnScene', function(jobId)
    local source = source
    local job = ActiveJobs[source]

    if not job or job.id ~= jobId then return end

    job.state = TowJob.JobState.ON_SCENE

    MySQL.update.await([[
        UPDATE tow_jobs SET state = ? WHERE id = ?
    ]], { job.state, job.id })

    TriggerClientEvent('dps-towjob:client:jobStateChanged', source, job)
    TowJob.Debug('Driver on scene:', job.id)
end)

-- Vehicle attached
RegisterNetEvent('dps-towjob:server:vehicleAttached', function(jobId, vehicleData)
    local source = source
    local job = ActiveJobs[source]

    if not job or job.id ~= jobId then return end

    job.state = TowJob.JobState.TOWING
    job.vehiclePlate = vehicleData.plate
    job.vehicleModel = vehicleData.model
    job.pickupLocation = vehicleData.location

    -- Determine destination
    if job.type == TowJob.JobTypes.POLICE then
        -- Police tows go to nearest impound
        local nearestImpound = GetNearestImpound(job.pickupCoords)
        job.destination = {
            type = TowJob.DestinationType.IMPOUND,
            id = nearestImpound,
            coords = Config.ImpoundLots[nearestImpound].dropoff
        }
    else
        -- Repair tows go to shop with longest wait and on-duty mechanics
        local shopId = GetNextRepairShop()
        if shopId then
            job.destination = {
                type = TowJob.DestinationType.SHOP,
                id = shopId,
                coords = Config.ShopJobMapping[shopId].vehicleDropoff
            }
        else
            -- Fallback to driver's shop
            local driverShop = GetDriverShop(source)
            if driverShop then
                job.destination = {
                    type = TowJob.DestinationType.SHOP,
                    id = driverShop,
                    coords = Config.ShopJobMapping[driverShop].vehicleDropoff
                }
            end
        end
    end

    MySQL.update.await([[
        UPDATE tow_jobs SET state = ?, vehicle_plate = ?, vehicle_model = ?, dropoff_coords = ? WHERE id = ?
    ]], {
        job.state,
        job.vehiclePlate,
        job.vehicleModel,
        job.destination and json.encode(job.destination.coords) or nil,
        job.id
    })

    TriggerClientEvent('dps-towjob:client:jobStateChanged', source, job)
    TowJob.Debug('Vehicle attached:', job.id, 'destination:', job.destination and job.destination.id)
end)

-- Job completed
RegisterNetEvent('dps-towjob:server:completeJob', function(jobId)
    local source = source

    -- Anti-spam check
    if CheckCooldown(source, 'completeJob') then return end

    local job = ActiveJobs[source]
    if not job or job.id ~= jobId then return end

    job.state = TowJob.JobState.COMPLETED
    job.completedAt = os.time()

    -- Calculate payment
    local distance = TowJob.CalculateDistance(job.pickupCoords, job.destination.coords)
    local isPve = job.type == TowJob.JobTypes.PVE
    local totalPayment = TowJob.CalculatePayment(distance, isPve)
    local driverCut, shopCut = TowJob.SplitPayment(totalPayment)

    -- Bonus for high rating drivers (luxury tier unlocked at 120+)
    local rating = GetDriverRating(source)
    if rating >= 120 then
        driverCut = math.floor(driverCut * 1.15) -- 15% bonus
        totalPayment = driverCut + shopCut
    end

    job.payment = {
        total = totalPayment,
        driver = driverCut,
        shop = shopCut,
        distance = distance
    }

    -- Process payment
    TriggerEvent('dps-towjob:server:processPayment', source, job)

    -- Update database with impound tracking
    MySQL.update.await([[
        UPDATE tow_jobs SET state = ?, payment = ?, completed_at = NOW(), dropoff_impound = ? WHERE id = ?
    ]], {
        job.state,
        totalPayment,
        job.destination and job.destination.type == TowJob.DestinationType.IMPOUND and job.destination.id or nil,
        job.id
    })

    -- Update driver stats
    local Player = QBCore.Functions.GetPlayer(source)
    if Player then
        local citizenid = Player.PlayerData.citizenid
        local jobTypeColumn = job.type .. '_jobs'

        MySQL.update.await([[
            INSERT INTO tow_driver_stats (citizenid, total_jobs_completed, total_miles_driven, total_earned)
            VALUES (?, 1, ?, ?)
            ON DUPLICATE KEY UPDATE
                total_jobs_completed = total_jobs_completed + 1,
                total_miles_driven = total_miles_driven + ?,
                total_earned = total_earned + ?
        ]], { citizenid, distance, driverCut, distance, driverCut })
    end

    -- Update reliability rating (+3 for completion, +2 bonus for damage-free)
    UpdateDriverRating(source, 3, 'Job completed')

    -- Clear active job
    ActiveJobs[source] = nil

    -- Update driver state
    if DutyTracker[source] then
        DutyTracker[source].state = TowJob.DriverState.AVAILABLE
        DutyTracker[source].lastTowCompleted = os.time()
    end

    -- Notify driver
    TriggerClientEvent('dps-towjob:client:jobCompleted', source, job)

    TowJob.Debug('Job completed:', job.id, 'payment:', totalPayment)

    -- Check for more jobs
    TriggerEvent('dps-towjob:server:checkQueue')
end)

-- Cancel job
RegisterNetEvent('dps-towjob:server:cancelJob', function(jobId, reason)
    local source = source

    -- Anti-spam check
    if CheckCooldown(source, 'cancelJob') then
        lib.notify(source, {
            title = 'Cooldown',
            description = 'Please wait before cancelling again',
            type = 'error'
        })
        return
    end

    local job = ActiveJobs[source]
    if not job or job.id ~= jobId then return end

    -- Penalize rating for cancellation (-5 rating)
    UpdateDriverRating(source, -5, 'Cancelled job')

    -- Update cancelled jobs count
    local Player = QBCore.Functions.GetPlayer(source)
    if Player then
        MySQL.update.await([[
            INSERT INTO tow_driver_stats (citizenid, cancelled_jobs)
            VALUES (?, 1)
            ON DUPLICATE KEY UPDATE cancelled_jobs = cancelled_jobs + 1
        ]], { Player.PlayerData.citizenid })
    end

    -- Requeue job at original position
    job.state = TowJob.JobState.QUEUED
    job.assignedTo = nil
    job.cancelledBy = source
    job.cancelReason = reason

    -- Insert back based on original timestamp
    local inserted = false
    for i, queuedJob in ipairs(TowQueue) do
        if job.createdAt < queuedJob.createdAt then
            table.insert(TowQueue, i, job)
            inserted = true
            break
        end
    end
    if not inserted then
        table.insert(TowQueue, job)
    end

    -- Clear active job
    ActiveJobs[source] = nil

    -- Update driver state
    if DutyTracker[source] then
        DutyTracker[source].state = TowJob.DriverState.AVAILABLE
    end

    lib.notify(source, {
        title = 'Tow Job',
        description = 'Job cancelled and requeued',
        type = 'inform'
    })

    TriggerClientEvent('dps-towjob:client:jobCancelled', source, job)

    TowJob.Debug('Job cancelled:', job.id, 'reason:', reason)

    -- Check for other available drivers
    TriggerEvent('dps-towjob:server:checkQueue')
end)

-- Get next repair shop (fair distribution)
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
        return nil
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

exports('GetNextRepairShop', GetNextRepairShop)

-- Check if shop has employees
function ShopHasEmployees(shopId)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.mechanicJob then return false end

    local players = QBCore.Functions.GetPlayers()

    for _, src in ipairs(players) do
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            local job = Player.PlayerData.job
            if job.name == shop.mechanicJob and job.onduty then
                return true
            end
        end
    end

    return false
end

exports('ShopHasEmployees', ShopHasEmployees)

-- Get shop wait time
exports('GetShopWaitTime', function(shopId)
    local waitTime = ShopWaitTimes[shopId] or 0
    if waitTime == 0 then return 0 end
    return os.time() - waitTime
end)

-- PVE job spawning
if Config.Queue.pveEnabled then
    CreateThread(function()
        while true do
            Wait(Config.Queue.pveInterval)

            -- Count active PVE jobs
            local pveCount = 0
            for _, job in pairs(ActiveJobs) do
                if job.type == TowJob.JobTypes.PVE then
                    pveCount = pveCount + 1
                end
            end
            for _, job in ipairs(TowQueue) do
                if job.type == TowJob.JobTypes.PVE then
                    pveCount = pveCount + 1
                end
            end

            -- Spawn PVE if under limit and drivers available
            if pveCount < Config.Queue.maxPveActive and #GetAvailableDrivers() > 0 then
                -- Generate random PVE location
                local pveLocations = {
                    vector3(-200.0, -1000.0, 29.0),
                    vector3(400.0, -1200.0, 29.0),
                    vector3(-500.0, -300.0, 35.0),
                    vector3(100.0, -700.0, 31.0),
                }

                local coords = pveLocations[math.random(#pveLocations)]

                AddToQueue({
                    type = TowJob.JobTypes.PVE,
                    coords = coords,
                    requesterId = 'SYSTEM',
                    requesterSource = nil
                })

                TowJob.Debug('PVE job spawned')
            end
        end
    end)
end
