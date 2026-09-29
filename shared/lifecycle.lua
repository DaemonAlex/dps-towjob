--[[
    dps-towjob shared/lifecycle.lua
    Pure decisions for service requests. No natives, no framework, no I/O,
    so tests/ can run every function under plain lua5.4.
]]

TowLifecycle = {}

local STATE_TO_STATUS = {
    queued = 'queued',
    assigned = 'accepted',
    en_route = 'accepted',
    on_scene = 'arrived',
    towing = 'hooked',
    completed = 'delivered',
    settled = 'delivered',
    cancelled = 'cancelled',
}

local OPEN_STATES = { queued = true, assigned = true, en_route = true, on_scene = true, towing = true }

local KINDS = { repair = true, impound = true }

--- What the requester is told for a given job state.
function TowLifecycle.statusFor(jobState)
    return STATE_TO_STATUS[jobState] or 'queued'
end

function TowLifecycle.isOpenState(jobState)
    return OPEN_STATES[jobState] == true
end

function TowLifecycle.validKind(kind)
    return type(kind) == 'string' and KINDS[kind] == true
end

--- Clean a client-supplied label before it is stored or shown.
function TowLifecycle.sanitizeLabel(text, maxLen)
    if type(text) ~= 'string' then return 'Unknown' end
    maxLen = maxLen or 60
    local clean = text:gsub('[%c<>]', '')
    clean = clean:gsub('^%s+', '')
    clean = clean:gsub('%s+$', '')
    if #clean == 0 then return 'Unknown' end
    if #clean > maxLen then clean = clean:sub(1, maxLen) end
    return clean
end

function TowLifecycle.findInQueue(queue, jobId)
    if type(queue) ~= 'table' then return nil end
    for i = 1, #queue do
        if queue[i].id == jobId then return queue[i], i end
    end
    return nil
end

function TowLifecycle.removeFromQueue(queue, jobId)
    local job, index = TowLifecycle.findInQueue(queue, jobId)
    if not job then return nil end
    table.remove(queue, index)
    return job
end

function TowLifecycle.queuePosition(queue, jobId)
    local _, index = TowLifecycle.findInQueue(queue, jobId)
    return index
end

--- Higher priority first; inside a priority band, older jobs first.
function TowLifecycle.insertByPriority(queue, job)
    local priority, created = job.priority or 2, job.createdAt or 0
    for i = 1, #queue do
        local other = queue[i]
        local otherPriority, otherCreated = other.priority or 2, other.createdAt or 0
        if priority > otherPriority or (priority == otherPriority and created < otherCreated) then
            table.insert(queue, i, job)
            return i
        end
    end
    queue[#queue + 1] = job
    return #queue
end

function TowLifecycle.etaSeconds(distanceMeters, speedMps, minSec, maxSec)
    if type(distanceMeters) ~= 'number' or distanceMeters < 0 then return nil end
    if type(speedMps) ~= 'number' or speedMps <= 0 then return nil end
    local eta = math.ceil(distanceMeters / speedMps)
    minSec = minSec or 30
    maxSec = maxSec or 3600
    if eta < minSec then eta = minSec end
    if eta > maxSec then eta = maxSec end
    return eta
end

function TowLifecycle.offerExpired(offeredAt, now, timeoutSec)
    if type(offeredAt) ~= 'number' then return true end
    return (now - offeredAt) >= timeoutSec
end

local function declinedBy(job, driver)
    local declined = job.declined
    if not declined then return false end
    return declined[driver.citizenid or driver.source] == true
end

--- First available driver who has not already passed on this job.
function TowLifecycle.nextDriver(available, job)
    for i = 1, #available do
        if not declinedBy(job, available[i]) then return available[i] end
    end
    return nil
end

function TowLifecycle.eligibleCount(available, job)
    local count = 0
    for i = 1, #available do
        if not declinedBy(job, available[i]) then count = count + 1 end
    end
    return count
end

--- City Tow takes a player request when nobody can, or nobody did in time.
--- AI calls (no kind) are for drivers only and never go to City Tow.
function TowLifecycle.shouldUseCityTow(job, eligibleCount, now, cfg)
    if type(job) ~= 'table' or not job.kind then return false end
    if job.cityTow then return false end
    if job.state ~= 'queued' then return false end
    local waited = now - (job.createdAt or now)
    if waited >= cfg.maxWaitSec then return true end
    if eligibleCount == 0 and not job.offeredTo and waited >= cfg.noDriverGraceSec then return true end
    return false
end

function TowLifecycle.canRequest(openJobId, lastRequestAt, now, cooldownSec)
    if openJobId then return false, 'open_request' end
    if lastRequestAt and (now - lastRequestAt) < cooldownSec then return false, 'cooldown' end
    return true
end

function TowLifecycle.canImpound(playerJob, cfg)
    if type(playerJob) ~= 'table' then return false end
    if playerJob.onduty ~= true then return false end
    return cfg.emergencyJobTypes[playerJob.type] == true
end

function TowLifecycle.jobTypeFor(kind, playerJobType)
    if kind == 'impound' then
        if playerJobType == 'leo' then return 'police' end
        return 'ems'
    end
    return 'customer'
end

function TowLifecycle.feeFor(kind, cfg)
    if kind == 'impound' then return cfg.emergencyTowFee end
    return cfg.repairTowFee
end

--- What City Tow does with the vehicle at hook time.
--- 'delete'  the right vehicle is at the pickup: remove it from the world
--- 'missing' no matching vehicle exists: finish the paperwork only
--- 'moved'   the vehicle was driven away: cancel the request
function TowLifecycle.hookDecision(found, plateMatches, distance, maxDistance)
    if not found or not plateMatches then return 'missing' end
    if distance and distance > maxDistance then return 'moved' end
    return 'delete'
end

--- The only shape a requester ever receives. No server ids, no coordinates.
function TowLifecycle.publicView(job, queue, now)
    local status = TowLifecycle.statusFor(job.state)
    local view = {
        id = job.id,
        kind = job.kind,
        status = status,
        plate = job.vehiclePlate,
        model = job.vehicleModel,
        location = job.zone,
        destination = job.destinationLabel,
        fee = job.fee or 0,
        feeDue = job.feeDue == true,
        cityTow = job.cityTow == true,
        driverName = job.driverName,
        reason = job.cancelReason,
        createdAt = job.createdAt,
        updatedAt = now,
    }
    if status == 'queued' then
        view.position = TowLifecycle.queuePosition(queue, job.id)
        view.driverName = nil
    elseif status == 'accepted' and job.etaAt then
        local left = job.etaAt - now
        if left < 0 then left = 0 end
        view.etaSeconds = left
    end
    return view
end

return TowLifecycle
