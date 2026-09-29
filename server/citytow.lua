--[[
    dps-towjob server/citytow.lua
    City Tow: the backup that takes a player's request when no driver can or
    does. Timer driven. It shows no truck in the world; the visible truck is a
    later plan. The requester gets the same status steps as with a real driver.
]]

local CityTowJobs = {}   -- jobId -> job

local function scaled(job, seconds)
    local ms = seconds * 1000 * (job.timeScale or 1.0)
    if ms < 1000 then ms = 1000 end
    return math.floor(ms)
end

local function nearestDepotDistance(coords)
    local best
    for _, shop in pairs(Config.ShopJobMapping) do
        if shop.towShop and shop.depot then
            local d = #(vector3(shop.depot.x, shop.depot.y, shop.depot.z) - coords)
            if not best or d < best then best = d end
        end
    end
    return best or 3000.0
end

local function trimPlate(plate)
    if type(plate) ~= 'string' then return nil end
    local clean = plate:gsub('^%s+', '')
    clean = clean:gsub('%s+$', '')
    return clean
end

--- Look at the world and decide what to do with the vehicle. The net id may
--- have been reused by another vehicle since the request, so the plate and
--- the distance from the pickup must both agree before anything is deleted.
local function vehicleAtPickup(job)
    local entity = job.netId and NetworkGetEntityFromNetworkId(job.netId) or 0
    local found = entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
    local plateMatches, distance = false, nil
    if found then
        plateMatches = trimPlate(GetVehicleNumberPlateText(entity)) == trimPlate(job.vehiclePlate)
        distance = #(GetEntityCoords(entity) - job.pickupCoords)
    end
    return TowLifecycle.hookDecision(found, plateMatches, distance, 30.0), entity
end

local function finish(job, state, reason)
    job.state = state
    job.cancelReason = reason
    job.etaAt = nil
    CityTowJobs[job.id] = nil
    MySQL.update('UPDATE tow_jobs SET state = ?, completed_at = NOW() WHERE id = ?', { state, job.id })
    PublishRequest(job)
end

local function cityDeliver(jobId)
    local job = CityTowJobs[jobId]
    if not job or job.state ~= TowJob.JobState.TOWING then return end

    local destination = job.destination
    if destination and destination.type == TowJob.DestinationType.IMPOUND then
        RecordImpound(job.vehiclePlate, destination.id, 'CITYTOW', job.id)
        MySQL.update('UPDATE tow_jobs SET dropoff_impound = ? WHERE id = ?', { destination.id, job.id })
    elseif destination then
        CreateServiceTicket(destination.id,
            { plate = job.vehiclePlate, model = job.vehicleModel, owner = job.requesterId },
            { citizenid = job.requesterId }, 'CITYTOW')
    end

    if job.feeCharged and (job.fee or 0) > 0 then
        MySQL.insert('INSERT INTO tow_shop_transactions (shop, amount, type, description) VALUES (?, ?, ?, ?)',
            { 'citytow', job.fee, 'tow_payment', 'Tow fee ' .. job.id })
    end

    finish(job, TowJob.JobState.COMPLETED, nil)
end

local function cityHook(jobId)
    local job = CityTowJobs[jobId]
    if not job or job.state ~= TowJob.JobState.ON_SCENE then return end

    local decision, entity = vehicleAtPickup(job)
    if decision == 'moved' then
        finish(job, TowJob.JobState.CANCELLED, 'vehicle_gone')
        return
    end
    if decision == 'delete' then DeleteEntity(entity) end

    job.state = TowJob.JobState.TOWING
    ChooseDestination(job, nil)
    ChargeRequestFee(job)
    MySQL.update('UPDATE tow_jobs SET state = ?, dropoff_coords = ? WHERE id = ?', {
        job.state, job.destination and json.encode(job.destination.coords) or nil, job.id,
    })
    PublishRequest(job)

    local distance = job.destination and #(job.destination.coords - job.pickupCoords) or 1500.0
    local travel = TowLifecycle.etaSeconds(distance, Config.Requests.cityTow.speedMps, 60, 600)
    SetTimeout(scaled(job, travel), function() cityDeliver(jobId) end)
end

local function cityArrive(jobId)
    local job = CityTowJobs[jobId]
    if not job or job.state ~= TowJob.JobState.EN_ROUTE then return end
    job.state = TowJob.JobState.ON_SCENE
    job.etaAt = nil
    MySQL.update('UPDATE tow_jobs SET state = ? WHERE id = ?', { job.state, job.id })
    PublishRequest(job)
    SetTimeout(scaled(job, Config.Requests.cityTow.hookSec), function() cityHook(jobId) end)
end

function StartCityTow(job)
    local cfg = Config.Requests.cityTow
    local offeredTo = job.offeredTo

    TowLifecycle.removeFromQueue(TowQueue, job.id)
    job.cityTow = true
    job.driverName = cfg.name
    job.state = TowJob.JobState.EN_ROUTE
    if offeredTo then WithdrawOffer(offeredTo, 'citytow', job) end

    local eta = TowLifecycle.etaSeconds(nearestDepotDistance(job.pickupCoords), cfg.speedMps, cfg.minEtaSec, cfg.maxEtaSec)
    local wait = scaled(job, eta)
    job.etaAt = os.time() + math.ceil(wait / 1000)
    CityTowJobs[job.id] = job

    MySQL.update('UPDATE tow_jobs SET state = ?, driver_id = ? WHERE id = ?', { job.state, 'CITYTOW', job.id })
    PublishRequest(job)
    PublishQueuePositions()
    SetTimeout(wait, function() cityArrive(job.id) end)
    TowJob.Debug('City Tow took job:', job.id, 'eta', eta)
end

function CityTowCheck(jobId)
    local job = TowLifecycle.findInQueue(TowQueue, jobId)
    if not job then return end
    local eligible = TowLifecycle.eligibleCount(GetAvailableDrivers(), job)
    if TowLifecycle.shouldUseCityTow(job, eligible, os.time(), Config.Requests) then
        StartCityTow(job)
    end
end

function ScheduleCityTow(job)
    local jobId = job.id
    local cfg = Config.Requests
    SetTimeout(scaled(job, cfg.noDriverGraceSec) + 500, function() CityTowCheck(jobId) end)
    SetTimeout(scaled(job, cfg.maxWaitSec) + 500, function() CityTowCheck(jobId) end)
end

-- Server console only. Proves the whole City Tow path without a player:
--   towtest            a repair request at Legion Square, timers at 5% length
--   towtest impound    the same as an impound request
RegisterCommand('towtest', function(source, args)
    if source ~= 0 then return end
    local kind = args[1] == 'impound' and 'impound' or 'repair'
    local jobType = kind == 'impound' and TowJob.JobTypes.POLICE or TowJob.JobTypes.CUSTOMER
    local added, jobId = AddToQueue({
        type = jobType,
        priority = TowJob.GetPriority(jobType),
        coords = vector3(215.09, -805.17, 30.81),
        plate = 'TEST' .. math.random(100, 999),
        model = 'TESTCAR',
        requesterId = 'CONSOLE_TEST',
        kind = kind,
        fee = 0,
        locationLabel = 'Legion Square (console test)',
    })
    if not added then
        print('[towtest] queue refused the job: ' .. tostring(jobId))
        return
    end
    local job = TowLifecycle.findInQueue(TowQueue, jobId)
    job.timeScale = 0.05
    OpenRequests[job.requesterId] = job
    ScheduleCityTow(job)
    print(('[towtest] %s request %s queued; City Tow steps in after about %d s'):format(
        kind, jobId, math.ceil(Config.Requests.noDriverGraceSec * 0.05) + 1))
end, true)

RegisterCommand('requestdebug', function(source)
    if source ~= 0 then return end
    local count = 0
    for citizenid, job in pairs(OpenRequests) do
        count = count + 1
        local view = TowLifecycle.publicView(job, TowQueue, os.time())
        print(('[requestdebug] %s %s kind=%s status=%s position=%s eta=%s driver=%s dest=%s fee=%s cityTow=%s'):format(
            citizenid, view.id, tostring(view.kind), view.status, tostring(view.position), tostring(view.etaSeconds),
            tostring(view.driverName), tostring(view.destination), tostring(view.fee), tostring(view.cityTow)))
    end
    local offers = 0
    for _ in pairs(PendingOffers) do offers = offers + 1 end
    print(('[requestdebug] open requests=%d queue=%d available drivers=%d pending offers=%d'):format(
        count, #TowQueue, #GetAvailableDrivers(), offers))
end, true)

AddEventHandler('dps-towjob:requestUpdate', function(citizenid, view)
    if citizenid == 'CONSOLE_TEST' then
        print(('[towtest] %s -> %s%s%s'):format(view.id, view.status,
            view.destination and (' to ' .. view.destination) or '',
            view.etaSeconds and (' eta ' .. view.etaSeconds .. 's') or ''))
    end
end)
