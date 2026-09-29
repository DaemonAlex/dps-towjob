--[[
    dps-towjob server/requests.lua
    Requests made by players through the City Services app, and the status
    they are shown. The queue itself still lives in server/queue.lua.
]]

OpenRequests = {}            -- citizenid -> job (one open request per player)
local LastRequestAt = {}     -- citizenid -> os.time() of the last request

local function sourceFor(citizenid)
    local player = Bridge.GetPlayerByIdentifier(citizenid)
    if not player or not player.PlayerData then return nil end
    return player.PlayerData.source
end

--- Send the requester their current status. Safe to call for any job:
--- jobs that did not come from a player (AI calls) are ignored.
function PublishRequest(job)
    if not job or not job.kind or not job.requesterId then return end
    local view = TowLifecycle.publicView(job, TowQueue, os.time())
    local changed = job.lastPublishedStatus ~= view.status
    job.lastPublishedStatus = view.status

    if view.status == 'delivered' or view.status == 'cancelled' then
        if OpenRequests[job.requesterId] == job then OpenRequests[job.requesterId] = nil end
    end

    TriggerEvent('dps-towjob:requestUpdate', job.requesterId, view, changed)

    local src = sourceFor(job.requesterId)
    job.requesterSource = src
    if src then
        TriggerClientEvent('dps-towjob:client:requestUpdate', src, view, changed)
    end
end

--- Tell everyone still waiting what their place in line is now.
function PublishQueuePositions()
    for _, job in pairs(OpenRequests) do
        if job.state == TowJob.JobState.QUEUED then PublishRequest(job) end
    end
end

--- Charge the tow fee once, when the vehicle is hooked. A requester who is
--- offline or short of money is marked as owing; the garage hand-off collects it.
function ChargeRequestFee(job)
    if not job or not job.kind or job.feeCharged or job.feeDue then return end
    local fee = job.fee or 0
    if fee <= 0 then
        job.feeCharged = true
        return
    end
    local src = sourceFor(job.requesterId)
    if src and Bridge.GetMoney(src, 'bank') >= fee and Bridge.RemoveMoney(src, 'bank', fee) then
        job.feeCharged = true
        MySQL.update('UPDATE tow_jobs SET fee_paid = 1 WHERE id = ?', { job.id })
    else
        job.feeDue = true
    end
end

local function requestService(source, data)
    local player = Bridge.GetPlayer(source)
    if not player then return false, 'no_player' end
    if type(data) ~= 'table' then return false, 'bad_request' end

    local kind = data.kind
    if not TowLifecycle.validKind(kind) then return false, 'bad_kind' end

    local pdata = player.PlayerData
    local citizenid = pdata.citizenid
    local now = os.time()
    local open = OpenRequests[citizenid]
    local ok, reason = TowLifecycle.canRequest(open and open.id, LastRequestAt[citizenid], now, Config.Requests.cooldownSec)
    if not ok then return false, reason end

    if kind == 'impound' and not TowLifecycle.canImpound(pdata.job, Config.Requests) then
        return false, 'not_allowed'
    end

    local c = data.coords
    if c == nil then return false, 'bad_coords' end
    local x, y, z = tonumber(c.x), tonumber(c.y), tonumber(c.z)
    if not x or not y or not z then return false, 'bad_coords' end
    local coords = vector3(x + 0.0, y + 0.0, z + 0.0)

    if not ValidateDistance(source, coords, Config.Requests.vehicleRange + 15.0) then
        return false, 'too_far'
    end

    local plate = TowLifecycle.sanitizeLabel(data.plate, 10)
    if plate == 'Unknown' then return false, 'no_vehicle' end

    if kind ~= 'impound' then
        local owns = MySQL.scalar.await('SELECT 1 FROM player_vehicles WHERE citizenid = ? AND plate = ? LIMIT 1', { citizenid, plate })
        if not owns then return false, 'not_owner' end
    end

    local fee = TowLifecycle.feeFor(kind, Config.Requests)
    if fee > 0 and Bridge.GetMoney(source, 'bank') < fee then return false, 'no_funds' end

    local jobType = TowLifecycle.jobTypeFor(kind, pdata.job and pdata.job.type)
    local added, jobId = AddToQueue({
        type = jobType,
        priority = TowJob.GetPriority(jobType),
        coords = coords,
        plate = plate,
        model = TowLifecycle.sanitizeLabel(data.model, 30),
        requesterId = citizenid,
        requesterSource = source,
        kind = kind,
        fee = fee,
        netId = tonumber(data.netId),
        locationLabel = TowLifecycle.sanitizeLabel(data.location, 60),
    })
    if not added then return false, 'queue_full' end

    local job = TowLifecycle.findInQueue(TowQueue, jobId)
    if not job then return false, 'queue_full' end

    OpenRequests[citizenid] = job
    LastRequestAt[citizenid] = now
    MySQL.update('UPDATE tow_jobs SET kind = ?, fee = ? WHERE id = ?', { kind, fee, jobId })

    if ScheduleCityTow then ScheduleCityTow(job) end
    PublishRequest(job)
    PublishQueuePositions()
    return true, TowLifecycle.publicView(job, TowQueue, os.time())
end

local function getRequestStatus(source)
    local player = Bridge.GetPlayer(source)
    if not player then return nil end
    local job = OpenRequests[player.PlayerData.citizenid]
    if not job then return nil end
    job.requesterSource = source
    return TowLifecycle.publicView(job, TowQueue, os.time())
end

local function cancelRequest(source)
    local player = Bridge.GetPlayer(source)
    if not player then return false, 'no_player' end
    local job = OpenRequests[player.PlayerData.citizenid]
    if not job then return false, 'no_request' end
    if TowLifecycle.statusFor(job.state) ~= 'queued' then return false, 'too_late' end

    local offeredTo = job.offeredTo
    TowLifecycle.removeFromQueue(TowQueue, job.id)
    job.state = TowJob.JobState.CANCELLED
    job.cancelReason = 'requester'
    if offeredTo and WithdrawOffer then WithdrawOffer(offeredTo, 'cancelled', job) end

    MySQL.update('UPDATE tow_jobs SET state = ? WHERE id = ?', { job.state, job.id })
    PublishRequest(job)
    PublishQueuePositions()
    return true
end

exports('RequestService', requestService)
exports('GetRequestStatus', getRequestStatus)
exports('CancelRequest', cancelRequest)
exports('GetRequestConfig', function()
    local r = Config.Requests
    return {
        repairTowFee = r.repairTowFee,
        emergencyTowFee = r.emergencyTowFee,
        vehicleRange = r.vehicleRange,
        emergencyJobTypes = r.emergencyJobTypes,
        jobName = Config.JobName,
    }
end)

-- The queue lives in memory. After a restart nothing is open any more, so
-- close the rows a previous run left behind. Nobody was charged for them:
-- the fee is only taken at hook time.
MySQL.ready(function()
    -- server/main.lua creates tow_jobs without waiting for the result, so make
    -- sure the table is there before touching it.
    local tries = 0
    while tries < 30 and not MySQL.scalar.await("SHOW TABLES LIKE 'tow_jobs'") do
        tries = tries + 1
        Wait(1000)
    end
    if tries >= 30 then
        print('[dps-towjob] tow_jobs table not found after 30 s; request columns and the stale sweep were skipped')
        return
    end

    MySQL.query.await('ALTER TABLE tow_jobs ADD COLUMN IF NOT EXISTS kind VARCHAR(20) NULL')
    MySQL.query.await('ALTER TABLE tow_jobs ADD COLUMN IF NOT EXISTS fee INT NOT NULL DEFAULT 0')
    MySQL.query.await('ALTER TABLE tow_jobs ADD COLUMN IF NOT EXISTS fee_paid TINYINT(1) NOT NULL DEFAULT 0')
    local closed = MySQL.update.await([[
        UPDATE tow_jobs SET state = 'cancelled'
        WHERE state IN ('queued', 'assigned', 'en_route', 'on_scene', 'towing')
    ]])
    TowJob.Debug('Closed stale tow jobs from the previous run:', closed)
end)
