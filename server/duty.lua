--[[
    dps-towjob Server Duty
    Duty tracking and clock in/out management
]]

-- Framework access goes through Bridge (qbx has no GetCoreObject on this box)

-- Toggle duty status
RegisterNetEvent('dps-towjob:server:toggleDuty', function(shopId)
    local source = source
    local Player = Bridge.GetPlayer(source)

    if not Player then return end

    local job = Player.PlayerData.job
    if job.name ~= Config.JobName then
        lib.notify(source, {
            title = 'Tow Job',
            description = 'You are not a tow driver',
            type = 'error'
        })
        return
    end

    local currentDuty = DutyTracker[source]

    if currentDuty then
        -- Clock out
        TowJob.Debug('Driver clocking out:', source)

        -- Check for active job
        if ActiveJobs[source] then
            lib.notify(source, {
                title = 'Tow Job',
                description = 'Complete your current job first',
                type = 'error'
            })
            return
        end

        DutyTracker[source] = nil
        Bridge.SetDuty(source, false)

        lib.notify(source, {
            title = 'Tow Job',
            description = 'You are now off duty',
            type = 'inform'
        })

        TriggerClientEvent('dps-towjob:client:dutyChanged', source, false, nil)
    else
        -- Clock in
        local shop = Config.ShopJobMapping[shopId]
        if not shop or not shop.towShop then
            lib.notify(source, {
                title = 'Tow Job',
                description = 'Invalid shop location',
                type = 'error'
            })
            return
        end

        TowJob.Debug('Driver clocking in at:', shopId)

        DutyTracker[source] = {
            shop = shopId,
            citizenid = Player.PlayerData.citizenid,
            state = TowJob.DriverState.AVAILABLE,
            clockedInAt = os.time(),
            lastTowCompleted = nil
        }

        Bridge.SetDuty(source, true)

        lib.notify(source, {
            title = 'Tow Job',
            description = 'Clocked in at ' .. shop.label,
            type = 'success'
        })

        TriggerClientEvent('dps-towjob:client:dutyChanged', source, true, shopId)

        -- Check queue for available jobs
        TriggerEvent('dps-towjob:server:checkQueue')
    end
end)

-- Set driver state
-- M1: validate against the enum AND the driver's current job. A client must
-- not be able to flip itself to AVAILABLE while it still has an active job
-- (which would let it grab a second assignment). Only AVAILABLE/BUSY may be
-- set here; OFF_DUTY is controlled exclusively by toggleDuty.
RegisterNetEvent('dps-towjob:server:setDriverState', function(state)
    local source = source

    if not DutyTracker[source] then return end
    if type(state) ~= 'string' then return end

    local normalized = TowJob.DriverState[state:upper()]
    if not normalized then
        TowJob.Debug('Invalid driver state:', state)
        return
    end

    -- Only allow the two work states through this event.
    if normalized ~= TowJob.DriverState.AVAILABLE and normalized ~= TowJob.DriverState.BUSY then
        TowJob.Debug('Rejected driver state via setDriverState:', source, normalized)
        return
    end

    -- Cannot become AVAILABLE while a job is still active.
    if normalized == TowJob.DriverState.AVAILABLE and ActiveJobs[source] then
        TowJob.Debug('Rejected AVAILABLE while job active:', source)
        return
    end

    DutyTracker[source].state = normalized
    TowJob.Debug('Driver state changed:', source, normalized)
end)

-- Get driver's shop
function GetDriverShop(source)
    local duty = DutyTracker[source]
    return duty and duty.shop or nil
end

exports('GetDriverShop', GetDriverShop)

-- Check if driver is on duty
function IsDriverOnDuty(source)
    return DutyTracker[source] ~= nil
end

exports('IsDriverOnDuty', IsDriverOnDuty)

-- Get driver state
function GetDriverState(source)
    local duty = DutyTracker[source]
    return duty and duty.state or TowJob.DriverState.OFF_DUTY
end

exports('GetDriverState', GetDriverState)

-- Sync with QBCore duty changes
RegisterNetEvent('QBCore:Server:OnJobUpdate', function(source, job)
    if job.name ~= Config.JobName then
        -- Player changed jobs, remove from duty tracker
        if DutyTracker[source] then
            DutyTracker[source] = nil
            TriggerClientEvent('dps-towjob:client:dutyChanged', source, false, nil)
        end
    end
end)

-- Get all on-duty drivers
lib.callback.register('dps-towjob:server:getOnDutyDrivers', function(source)
    local drivers = {}

    for src, duty in pairs(DutyTracker) do
        local Player = Bridge.GetPlayer(src)
        if Player then
            table.insert(drivers, {
                source = src,
                name = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
                shop = duty.shop,
                state = duty.state,
                clockedInAt = duty.clockedInAt
            })
        end
    end

    return drivers
end)
