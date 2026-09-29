--[[
    dps-towjob server/offers.lua
    A queued job is OFFERED to a driver, who accepts or declines. Until a
    driver accepts, the job stays in the queue and the requester keeps their
    place in line. Declining or letting an offer run out costs no rating.
]]

PendingOffers = {}   -- driver source -> { jobId = string, offeredAt = number }

local function offerPayload(job)
    local c = job.pickupCoords
    return {
        id = job.id,
        type = job.type,
        kind = job.kind,
        zone = job.zone,
        priority = job.priority,
        vehicleModel = job.vehicleModel,
        vehiclePlate = job.vehiclePlate,
        vehicleCode = job.vehicleCode,
        violationText = job.violationText,
        commission = job.commission,
        coords = c and { x = c.x, y = c.y, z = c.z } or nil,
        timeoutSec = Config.Requests.offerTimeoutSec,
        offeredAt = job.offeredAt,
    }
end

local function driverChanged(source)
    TriggerEvent('dps-towjob:driverUpdate', source)
end

--- Take an offer back. job is optional: pass it when the job has already
--- left the queue (a cancelled request, a City Tow start).
function WithdrawOffer(source, reason, job)
    local pending = PendingOffers[source]
    if not pending then return end
    PendingOffers[source] = nil

    job = job or TowLifecycle.findInQueue(TowQueue, pending.jobId)
    if job and job.offeredTo == source then
        job.offeredTo = nil
        job.offeredAt = nil
        if reason == 'timeout' or reason == 'declined' then
            local duty = DutyTracker[source]
            job.declined = job.declined or {}
            job.declined[duty and duty.citizenid or source] = true
        end
    end

    local duty = DutyTracker[source]
    if duty and duty.state == TowJob.DriverState.OFFERED then
        duty.state = TowJob.DriverState.AVAILABLE
    end

    TriggerClientEvent('dps-towjob:client:offerWithdrawn', source, pending.jobId, reason)
    driverChanged(source)

    -- The driver is free again, so look at the queue whatever the reason was
    TriggerEvent('dps-towjob:server:checkQueue')
    if reason == 'timeout' or reason == 'declined' or reason == 'disconnect' or reason == 'offduty' then
        if job and job.kind and CityTowCheck then CityTowCheck(job.id) end
    end
end

function OfferJob(source, job)
    local duty = DutyTracker[source]
    if not duty then return false end

    job.offeredTo = source
    job.offeredAt = os.time()
    PendingOffers[source] = { jobId = job.id, offeredAt = job.offeredAt }
    duty.state = TowJob.DriverState.OFFERED

    TriggerClientEvent('dps-towjob:client:jobOffered', source, offerPayload(job))
    driverChanged(source)

    local jobId, offeredAt = job.id, job.offeredAt
    SetTimeout(Config.Requests.offerTimeoutSec * 1000, function()
        local pending = PendingOffers[source]
        if pending and pending.jobId == jobId and pending.offeredAt == offeredAt then
            WithdrawOffer(source, 'timeout')
        end
    end)
    return true
end

local function acceptOffer(source, jobId)
    local pending = PendingOffers[source]
    if not pending or pending.jobId ~= jobId then return false, 'no_offer' end
    if TowLifecycle.offerExpired(pending.offeredAt, os.time(), Config.Requests.offerTimeoutSec) then
        WithdrawOffer(source, 'timeout')
        return false, 'expired'
    end
    if not DutyTracker[source] then
        PendingOffers[source] = nil
        return false, 'no_offer'
    end

    local job = TowLifecycle.removeFromQueue(TowQueue, jobId)
    PendingOffers[source] = nil
    if not job then
        DutyTracker[source].state = TowJob.DriverState.AVAILABLE
        driverChanged(source)
        return false, 'gone'
    end

    job.offeredTo = nil
    job.offeredAt = nil
    job.accepted = true

    -- Work out the ETA first, so the requester's first "accepted" message carries it
    local ped = GetPlayerPed(source)
    if ped and ped ~= 0 then
        local distance = #(GetEntityCoords(ped) - job.pickupCoords)
        local eta = TowLifecycle.etaSeconds(distance, Config.Requests.driverSpeedMps, 30, 3600)
        if eta then job.etaAt = os.time() + eta end
    end

    AssignJobToDriver(source, job)

    job.state = TowJob.JobState.EN_ROUTE
    MySQL.update('UPDATE tow_jobs SET state = ? WHERE id = ?', { job.state, job.id })

    TriggerClientEvent('dps-towjob:client:jobStateChanged', source, job)
    PublishRequest(job)
    PublishQueuePositions()
    driverChanged(source)
    return true
end

local function declineOffer(source, jobId)
    local pending = PendingOffers[source]
    if not pending or pending.jobId ~= jobId then return false, 'no_offer' end
    WithdrawOffer(source, 'declined')
    return true
end

RegisterNetEvent('dps-towjob:server:acceptOffer', function(jobId)
    local source = source
    local ok, reason = acceptOffer(source, jobId)
    if not ok then
        Bridge.Notify(source, 'Tow Request', reason == 'gone' and 'That request was cancelled' or 'That offer has ended', 'error')
    end
end)

RegisterNetEvent('dps-towjob:server:declineOffer', function(jobId)
    declineOffer(source, jobId)
end)

--- What the City Services app shows a tow driver. nil for anyone who does
--- not hold the tow job, so the app never draws a driver tab for them.
local function getDriverView(source)
    local player = Bridge.GetPlayer(source)
    if not player then return nil end
    local job = player.PlayerData.job
    if not job or job.name ~= Config.JobName then return nil end

    local view = { onDuty = DutyTracker[source] ~= nil }
    local pending = PendingOffers[source]
    if pending then
        local offered = TowLifecycle.findInQueue(TowQueue, pending.jobId)
        if offered then
            view.offer = offerPayload(offered)
            local left = Config.Requests.offerTimeoutSec - (os.time() - pending.offeredAt)
            view.offer.secondsLeft = left > 0 and left or 0
        end
    end
    local active = ActiveJobs[source]
    if active then
        local c = active.state == TowJob.JobState.TOWING and active.destination and active.destination.coords
            or active.pickupCoords
        view.job = {
            id = active.id,
            kind = active.kind,
            type = active.type,
            state = active.state,
            zone = active.zone,
            vehiclePlate = active.vehiclePlate,
            vehicleModel = active.vehicleModel,
            vehicleCode = active.vehicleCode,
            destination = active.destinationLabel,
            coords = c and { x = c.x, y = c.y } or nil,
        }
    end
    return view
end

exports('AcceptOffer', acceptOffer)
exports('DeclineOffer', declineOffer)
exports('GetDriverView', getDriverView)
