--[[
    dps-towjob server/requests.lua
    Requests made by players through the City Services app, and the status
    they are shown. The queue itself still lives in server/queue.lua.
]]

OpenRequests = {}            -- citizenid -> job (one open request per player)
local LastRequestAt = {}     -- citizenid -> os.time() of the last request
local RefundOwed = {}        -- citizenid -> true while a fee is waiting to be paid back

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

--- Give the fee back when the tow did not happen. fee_paid: 0 not paid,
--- 1 paid, 2 refund owed. A requester who is offline is paid the next time
--- they open the app.
function RefundRequestFee(job)
    if not job then return 'none' end
    local src = sourceFor(job.requesterId)
    local decision = TowLifecycle.refundDecision(job, src ~= nil)
    if decision == 'none' then return decision end

    local fee = job.fee or 0
    job.feeCharged = nil
    if decision == 'refund' then
        Bridge.AddMoney(src, 'bank', fee)
        job.refund = 'refunded'
        MySQL.update('UPDATE tow_jobs SET fee_paid = 0 WHERE id = ?', { job.id })
    else
        job.refund = 'owed'
        RefundOwed[job.requesterId] = true
        MySQL.update('UPDATE tow_jobs SET fee_paid = 2 WHERE id = ?', { job.id })
    end
    return decision
end

--- Pay back anything this player is owed. Only ever reaches the database for
--- a citizen the server already knows is owed something.
local function payOwedRefunds(source, citizenid)
    if not RefundOwed[citizenid] then return end
    RefundOwed[citizenid] = nil
    local rows = MySQL.query.await('SELECT id, fee FROM tow_jobs WHERE requester_id = ? AND fee_paid = 2', { citizenid })
    if type(rows) ~= 'table' then return end
    local total = 0
    for i = 1, #rows do
        local fee = tonumber(rows[i].fee) or 0
        if fee > 0 then
            total = total + fee
            MySQL.update('UPDATE tow_jobs SET fee_paid = 0 WHERE id = ?', { rows[i].id })
        end
    end
    if total > 0 then
        Bridge.AddMoney(source, 'bank', total)
        Bridge.Notify(source, 'City Services', ('Your $%d tow fee was paid back.'):format(total), 'success')
    end
end

--- Is a tow already on the way for this vehicle? Two requests for one plate
--- end with one job deleting the car out from under the other.
local function plateHasOpenJob(plate)
    for i = 1, #TowQueue do
        if TowLifecycle.cleanPlate(TowQueue[i].vehiclePlate) == plate then return true end
    end
    for _, job in pairs(ActiveJobs) do
        if TowLifecycle.cleanPlate(job.vehiclePlate) == plate then return true end
    end
    for _, job in pairs(OpenRequests) do
        if TowLifecycle.cleanPlate(job.vehiclePlate) == plate then return true end
    end
    return false
end

local function makeRequest(source, player, data)
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

    -- Everything about the vehicle is read from the entity the net id resolves
    -- to. The client's plate, model and coordinates are not used.
    local netId = tonumber(data.netId)
    local entity = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then
        return false, 'no_vehicle'
    end

    local coords = GetEntityCoords(entity)
    local plate = TowLifecycle.cleanPlate(GetVehicleNumberPlateText(entity))
    if not plate then return false, 'no_vehicle' end

    if not ValidateDistance(source, coords, Config.Requests.vehicleRange + 15.0) then
        return false, 'too_far'
    end

    if plateHasOpenJob(plate) then return false, 'already_requested' end

    if kind ~= 'impound' then
        local owns = MySQL.scalar.await(
            "SELECT 1 FROM player_vehicles WHERE citizenid = ? AND REPLACE(plate, ' ', '') = ? LIMIT 1",
            { citizenid, plate })
        if not owns then return false, 'not_owner' end
    end

    local vehicleCode, vehicleLabel
    local gotEntry, entry = pcall(function() return exports.qbx_core:GetVehiclesByHash(GetEntityModel(entity)) end)
    if not gotEntry or type(entry) ~= 'table' then entry = nil end
    if entry and type(entry.model) == 'string' then
        vehicleCode = entry.model:lower()
        if type(entry.name) == 'string' and entry.name ~= '' then
            vehicleLabel = ((type(entry.brand) == 'string' and entry.brand ~= '') and (entry.brand .. ' ') or '') .. entry.name
        end
    end

    local fee = TowLifecycle.feeFor(kind, Config.Requests)
    if fee > 0 and Bridge.GetMoney(source, 'bank') < fee then return false, 'no_funds' end

    local jobType = TowLifecycle.jobTypeFor(kind, pdata.job and pdata.job.type)
    local added, jobId = AddToQueue({
        type = jobType,
        priority = TowJob.GetPriority(jobType),
        coords = coords,
        plate = plate,
        model = TowLifecycle.sanitizeLabel(vehicleLabel or data.model, 30),
        code = vehicleCode,
        requesterId = citizenid,
        requesterSource = source,
        kind = kind,
        fee = fee,
        netId = netId,
        locationLabel = TowLifecycle.sanitizeLabel(data.location, 60),
    })
    if not added then return false, 'queue_full' end

    local job = TowLifecycle.findInQueue(TowQueue, jobId)
    if not job then return false, 'queue_full' end

    -- Kept on the job so the impound record still names the caller when they
    -- have logged off by the time the vehicle is delivered.
    local charinfo = pdata.charinfo or {}
    job.requesterName = TowLifecycle.sanitizeLabel(
        ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')), 50)
    job.requesterJobLabel = TowLifecycle.sanitizeLabel(pdata.job and pdata.job.label, 50)

    OpenRequests[citizenid] = job
    LastRequestAt[citizenid] = now
    MySQL.update('UPDATE tow_jobs SET kind = ?, fee = ? WHERE id = ?', { kind, fee, jobId })

    if ScheduleCityTow then ScheduleCityTow(job) end
    PublishRequest(job)
    PublishQueuePositions()
    return true, TowLifecycle.publicView(job, TowQueue, os.time())
end

--- The checks inside makeRequest wait for the database, so two requests sent
--- in the same instant both used to get through. The citizen is marked while
--- one is being built, and the mark is cleared on every way out, errors too.
local Requesting = {}

local function requestService(source, data)
    local player = Bridge.GetPlayer(source)
    if not player then return false, 'no_player' end
    if type(data) ~= 'table' then return false, 'bad_request' end

    local citizenid = player.PlayerData.citizenid
    if Requesting[citizenid] then return false, 'open_request' end
    Requesting[citizenid] = true

    local ok, a, b = pcall(makeRequest, source, player, data)
    Requesting[citizenid] = nil

    if not ok then
        print('[dps-towjob] request failed: ' .. tostring(a))
        return false, 'bad_request'
    end
    return a, b
end

local function getRequestStatus(source)
    local player = Bridge.GetPlayer(source)
    if not player then return nil end
    payOwedRefunds(source, player.PlayerData.citizenid)
    local job = OpenRequests[player.PlayerData.citizenid]
    if not job then return nil end
    job.requesterSource = source
    return TowLifecycle.publicView(job, TowQueue, os.time())
end

--- A requester may call a tow off while it is still in line or while the driver
--- is on the way. Once the driver has arrived it is too late: no fee has been
--- taken before the hook, so a cancel here never owes anything back.
local function cancelRequest(source)
    local player = Bridge.GetPlayer(source)
    if not player then return false, 'no_player' end
    local job = OpenRequests[player.PlayerData.citizenid]
    if not job then return false, 'no_request' end
    local status = TowLifecycle.statusFor(job.state)
    if status ~= 'queued' and status ~= 'accepted' then return false, 'too_late' end

    -- City Tow is already on its way: it has its own timers to stop.
    if job.cityTow then
        if not CancelCityTow then return false, 'too_late' end
        CancelCityTow(job, 'requester')
        PublishQueuePositions()
        return true
    end

    local offeredTo = job.offeredTo
    local driver = job.assignedTo
    TowLifecycle.removeFromQueue(TowQueue, job.id)
    job.state = TowJob.JobState.CANCELLED
    job.cancelReason = 'requester'
    if offeredTo and WithdrawOffer then WithdrawOffer(offeredTo, 'cancelled', job) end

    -- Free the driver who accepted it, so they are not stuck on a job nobody
    -- wants any more and the requester is not stuck behind them.
    if driver and ActiveJobs[driver] == job then
        ActiveJobs[driver] = nil
        if DutyTracker[driver] then DutyTracker[driver].state = TowJob.DriverState.AVAILABLE end
        Bridge.Notify(driver, 'Tow Request', 'The caller cancelled that tow.', 'inform')
        TriggerClientEvent('dps-towjob:client:jobCancelled', driver, DriverJobView and DriverJobView(job) or nil)
        TriggerEvent('dps-towjob:driverUpdate', driver)
    end

    MySQL.update('UPDATE tow_jobs SET state = ? WHERE id = ?', { job.state, job.id })
    PublishRequest(job)
    PublishQueuePositions()
    TriggerEvent('dps-towjob:server:checkQueue')
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
-- close the rows a previous run left behind. A row that was already on the
-- truck had its fee taken, so it is marked as a refund owed first, and the
-- requester is paid when they next open the app.
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

    -- A vehicle that was on the truck had its fee taken and will never be
    -- delivered, so the fee is owed back before the row is closed.
    local owed = MySQL.update.await([[
        UPDATE tow_jobs SET fee_paid = 2 WHERE state = 'towing' AND fee_paid = 1
    ]])
    TowJob.Debug('Tow fees owed back after the previous run:', owed)

    -- Everyone with a request that is about to be closed hears about it once.
    local open = MySQL.query.await([[
        SELECT requester_id FROM tow_jobs
        WHERE kind IS NOT NULL AND requester_id IS NOT NULL
          AND state IN ('queued', 'assigned', 'en_route', 'on_scene', 'towing')
    ]])
    local closed = MySQL.update.await([[
        UPDATE tow_jobs SET state = 'cancelled'
        WHERE state IN ('queued', 'assigned', 'en_route', 'on_scene', 'towing')
    ]])
    TowJob.Debug('Closed stale tow jobs from the previous run:', closed)

    local refundRows = MySQL.query.await('SELECT DISTINCT requester_id FROM tow_jobs WHERE fee_paid = 2 AND requester_id IS NOT NULL')
    if type(refundRows) == 'table' then
        for i = 1, #refundRows do RefundOwed[refundRows[i].requester_id] = true end
    end

    if type(open) == 'table' then
        local told = {}
        for i = 1, #open do
            local citizenid = open[i].requester_id
            if citizenid and not told[citizenid] then
                told[citizenid] = true
                local src = sourceFor(citizenid)
                if src then
                    Bridge.Notify(src, 'City Services',
                        'Tow dispatch restarted. Your open tow request was closed. You can ask again.', 'inform')
                end
            end
        end
    end
end)
