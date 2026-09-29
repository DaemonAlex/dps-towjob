--[[
    dps-towjob Server Queue
    Queue management and job distribution
]]

-- Framework access goes through Bridge (qbx has no GetCoreObject on this box)

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
        zone = request.locationLabel or TowJob.GetZoneName(request.coords) or 'Unknown',
        kind = request.kind,
        fee = request.fee or 0,
        netId = request.netId,
        vehicleCode = request.code,
        test = request.test,
        declined = {},
        -- Preserve PVE / predatory metadata so the server stays authoritative
        -- over commission (settlement math), dispatch display, and cleanup.
        pveId = request.pveId,
        violation = request.violation,
        violationText = request.violationText,
        commission = request.commission,
    }

    TowLifecycle.insertByPriority(TowQueue, job)

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
    local Player = source and Bridge.GetPlayer(source)

    return AddToQueue({
        type = towType or TowJob.JobTypes.CUSTOMER,
        priority = priority,
        coords = coords,
        requesterId = Player and Player.PlayerData.citizenid or nil,
        requesterSource = source
    })
end)

-- Offer queued jobs to available drivers, oldest-idle driver first.
AddEventHandler('dps-towjob:server:checkQueue', function()
    if #TowQueue == 0 then return end

    local available = GetAvailableDrivers()
    if #available == 0 then return end

    for i = 1, #TowQueue do
        local job = TowQueue[i]
        if job and not job.offeredTo and not job.cityTow and not job.test then
            local driver = TowLifecycle.nextDriver(available, job)
            if driver and OfferJob(driver.source, job) then
                for k = #available, 1, -1 do
                    if available[k].source == driver.source then table.remove(available, k) end
                end
                if #available == 0 then break end
            end
        end
    end
end)

--- What a driver's client is given about a job: what their screen shows and
--- nothing else. No requester citizen id, no list of drivers who declined.
function DriverJobView(job)
    if type(job) ~= 'table' then return nil end
    return {
        id = job.id,
        type = job.type,
        kind = job.kind,
        state = job.state,
        priority = job.priority,
        zone = job.zone,
        pickupCoords = job.pickupCoords,
        vehiclePlate = job.vehiclePlate,
        vehicleModel = job.vehicleModel,
        vehicleCode = job.vehicleCode,
        violation = job.violation,
        violationText = job.violationText,
        commission = job.commission,
        pveId = job.pveId,
        destination = job.destination,
        destinationLabel = job.destinationLabel,
        accepted = job.accepted,
        payment = job.payment,
        createdAt = job.createdAt,
        -- a server id, not an identity: roadside billing needs it to bill the
        -- caller standing in front of the driver
        requesterSource = job.requesterSource,
    }
end

-- Assign job to driver
function AssignJobToDriver(source, job)
    job.state = TowJob.JobState.ASSIGNED
    job.assignedTo = source
    job.assignedAt = os.time()

    ActiveJobs[source] = job
    DutyTracker[source].state = TowJob.DriverState.BUSY

    -- Update database
    local assignPlayer = Bridge.GetPlayer(source)
    MySQL.update.await([[
        UPDATE tow_jobs SET state = ?, driver_id = ? WHERE id = ?
    ]], {
        job.state,
        assignPlayer and assignPlayer.PlayerData.citizenid or nil,
        job.id
    })

    -- Notify driver
    TriggerClientEvent('dps-towjob:client:jobAssigned', source, DriverJobView(job))

    local charinfo = assignPlayer and assignPlayer.PlayerData and assignPlayer.PlayerData.charinfo
    job.driverName = charinfo and (charinfo.firstname .. ' ' .. charinfo.lastname) or 'A driver'
    PublishRequest(job)
    PublishQueuePositions()

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

    TriggerClientEvent('dps-towjob:client:jobStateChanged', source, DriverJobView(job))
    PublishRequest(job)
    TowJob.Debug('Job accepted:', job.id)
end)

-- Driver arrived on scene
RegisterNetEvent('dps-towjob:server:arrivedOnScene', function(jobId)
    local source = source
    local job = ActiveJobs[source]

    if not job or job.id ~= jobId then return end
    if job.state ~= TowJob.JobState.ASSIGNED and job.state ~= TowJob.JobState.EN_ROUTE then return end
    if not ValidateDistance(source, job.pickupCoords, Config.Requests.arriveRadius + 15.0) then return end

    job.state = TowJob.JobState.ON_SCENE
    job.etaAt = nil

    MySQL.update.await([[
        UPDATE tow_jobs SET state = ? WHERE id = ?
    ]], { job.state, job.id })

    TriggerClientEvent('dps-towjob:client:jobStateChanged', source, DriverJobView(job))
    PublishRequest(job)
    TowJob.Debug('Driver on scene:', job.id)
end)

local RealJob = {}   -- job name -> true / false, asked once per server run

--- Is this the name of a job somebody can actually hold on this server? Four
--- shops in config/shops.lua name vendor jobs that do not exist here, so a car
--- sent to them lands in a queue nobody can ever open.
local function jobExists(name)
    if type(name) ~= 'string' or name == '' then return false end
    if RealJob[name] ~= nil then return RealJob[name] end
    local ok, job = pcall(function() return exports.qbx_core:GetJob(name) end)
    RealJob[name] = ok and job ~= nil
    return RealJob[name]
end

--- Where a hooked vehicle goes. Impound requests go to the nearest impound lot,
--- everything else to a repair shop. driverSource is nil for City Tow.
function ChooseDestination(job, driverSource)
    if job.type == TowJob.JobTypes.POLICE or job.type == TowJob.JobTypes.EMS or job.kind == 'impound' then
        local impoundId = GetNearestImpound(job.pickupCoords)
        local lot = impoundId and Config.ImpoundLots[impoundId]
        if lot then
            job.destination = { type = TowJob.DestinationType.IMPOUND, id = impoundId, coords = lot.dropoff }
            job.destinationLabel = lot.label or impoundId
            return job.destination
        end
    end

    local shopId = GetNextRepairShop() or (driverSource and GetDriverShop(driverSource)) or nil
    if not shopId then
        local best
        for id, shop in pairs(Config.ShopJobMapping) do
            if shop.towShop and shop.vehicleDropoff and jobExists(shop.mechanicJob) then
                local d = #(shop.vehicleDropoff - job.pickupCoords)
                if not best or d < best then
                    best = d
                    shopId = id
                end
            end
        end
    end
    if shopId and Config.ShopJobMapping[shopId] then
        local shop = Config.ShopJobMapping[shopId]
        job.destination = { type = TowJob.DestinationType.SHOP, id = shopId, coords = shop.vehicleDropoff }
        job.destinationLabel = shop.label or shopId
        return job.destination
    end
    return nil
end

-- Vehicle attached
-- H2: this is the ONLY transition into TOWING, and completeJob requires TOWING.
-- So this handler is server-authoritative about "the vehicle is really hooked":
-- the driver must be on duty, near the pickup, and coming from a pre-tow state.
RegisterNetEvent('dps-towjob:server:vehicleAttached', function(jobId, vehicleData)
    local source = source

    -- Anti-spam
    if CheckCooldown(source, 'vehicleAttached') then return end

    local job = ActiveJobs[source]
    if not job or job.id ~= jobId then return end
    if type(vehicleData) ~= 'table' then return end

    -- Must be an on-duty tow driver
    if not DutyTracker[source] then return end

    -- Enforce ordering: can only attach from a pre-tow state, never re-attach
    local s = job.state
    if s ~= TowJob.JobState.ASSIGNED and s ~= TowJob.JobState.EN_ROUTE and s ~= TowJob.JobState.ON_SCENE then
        TowJob.Debug('Rejected vehicleAttached from state:', s, 'job:', jobId)
        return
    end

    -- Must actually be at the pickup to hook the vehicle
    if not ValidateDistance(source, job.pickupCoords, 15.0) then
        TowJob.Debug('Rejected vehicleAttached: too far from pickup', source, jobId)
        return
    end

    local sentPlate = TowLifecycle.sanitizeLabel(vehicleData.plate, 10)
    if job.kind then
        -- A player request keeps what the server recorded when it was made.
        -- The driver's client may only confirm it is the same vehicle.
        local want = (job.vehiclePlate or ''):gsub('%s+', ''):upper()
        local got = (sentPlate == 'Unknown' and '' or sentPlate):gsub('%s+', ''):upper()
        if want == '' or got ~= want then
            Bridge.Notify(source, 'Tow', 'That is not the vehicle on this request. Check the plate.', 'error')
            TowJob.Debug('Rejected vehicleAttached: plate mismatch', source, jobId)
            return
        end
    else
        job.vehiclePlate = sentPlate
        job.vehicleModel = TowLifecycle.sanitizeLabel(vehicleData.model, 30)
        job.pickupLocation = TowLifecycle.sanitizeLabel(vehicleData.location, 60)
    end
    job.state = TowJob.JobState.TOWING

    ChooseDestination(job, source)
    job.etaAt = nil
    ChargeRequestFee(job)

    MySQL.update.await([[
        UPDATE tow_jobs SET state = ?, vehicle_plate = ?, vehicle_model = ?, dropoff_coords = ? WHERE id = ?
    ]], {
        job.state,
        job.vehiclePlate,
        job.vehicleModel,
        job.destination and json.encode(job.destination.coords) or nil,
        job.id
    })

    TriggerClientEvent('dps-towjob:client:jobStateChanged', source, DriverJobView(job))
    PublishRequest(job)
    TowJob.Debug('Vehicle attached:', job.id, 'destination:', job.destination and job.destination.id)
end)

-- Job completed
RegisterNetEvent('dps-towjob:server:completeJob', function(jobId)
    local source = source

    -- Anti-spam check
    if CheckCooldown(source, 'completeJob') then return end

    local job = ActiveJobs[source]
    if not job or job.id ~= jobId then return end

    -- H2 state machine: only a job that was actually hooked (TOWING) and has a
    -- server-assigned destination can be completed, and the driver must have
    -- driven it to that destination. This blocks "skip the tow, get full pay".
    if job.state ~= TowJob.JobState.TOWING then
        TowJob.Debug('Rejected completeJob from state:', job.state, 'job:', jobId)
        return
    end
    if not job.destination or not job.destination.coords then
        TowJob.Debug('Rejected completeJob: no destination', jobId)
        return
    end
    if not ValidateDistance(source, job.destination.coords, 15.0) then
        lib.notify(source, {
            title = 'Tow Job',
            description = 'You must deliver the vehicle to the destination',
            type = 'error'
        })
        return
    end

    job.state = TowJob.JobState.COMPLETED
    if job.kind and job.feeCharged and (job.fee or 0) > 0 then
        local driverShop = GetDriverShop(source)
        if driverShop then AddToShopFund(driverShop, job.fee, 'Tow fee ' .. job.id) end
    end
    -- The vehicle has to end up where the app says it is. Once per job, before
    -- the requester is told it was delivered.
    if job.kind and HandOffVehicle then HandOffVehicle(job) end
    PublishRequest(job)
    job.completedAt = os.time()

    -- Calculate payment SERVER-SIDE from server-tracked pickup/destination.
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

    -- Process payment (C2: internal call, NOT a spoofable net event).
    ProcessPayment(source, job)

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
    local Player = Bridge.GetPlayer(source)
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
    TriggerClientEvent('dps-towjob:client:jobCompleted', source, DriverJobView(job))

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
    local Player = Bridge.GetPlayer(source)
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
    -- Another client's free text: cleaned and capped before it is stored.
    job.cancelReason = reason ~= nil and TowLifecycle.sanitizeLabel(reason, 60) or nil

    -- Back into the queue by priority and age, and never back to the same driver
    job.etaAt = nil
    job.driverName = nil
    job.accepted = nil
    if DutyTracker[source] and DutyTracker[source].citizenid then
        job.declined[DutyTracker[source].citizenid] = true
    end
    TowLifecycle.insertByPriority(TowQueue, job)
    if PublishRequest then PublishRequest(job) end

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

    TriggerClientEvent('dps-towjob:client:jobCancelled', source, DriverJobView(job))

    TowJob.Debug('Job cancelled:', job.id, 'reason:', reason)

    -- Check for other available drivers
    TriggerEvent('dps-towjob:server:checkQueue')

    -- Both City Tow timers may already have fired while this driver held the
    -- job. Without this a player request could sit in the queue for good.
    if job.kind and CityTowCheck then CityTowCheck(job.id) end
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

    local players = Bridge.GetPlayers()

    for _, src in ipairs(players) do
        local Player = Bridge.GetPlayer(src)
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

-- PVE job spawning handled by server/pve.lua (SpawnBreakdown + SpawnPredatoryTow)
