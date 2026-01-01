--[[
    dps-towjob Server Duty
    Duty tracking and clock in/out management
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Toggle duty status
RegisterNetEvent('dps-towjob:server:toggleDuty', function(shopId)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)

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
        Player.Functions.SetJobDuty(false)

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
            state = TowJob.DriverState.AVAILABLE,
            clockedInAt = os.time(),
            lastTowCompleted = nil
        }

        Player.Functions.SetJobDuty(true)

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
RegisterNetEvent('dps-towjob:server:setDriverState', function(state)
    local source = source

    if not DutyTracker[source] then return end

    if not TowJob.DriverState[state:upper()] then
        TowJob.Debug('Invalid driver state:', state)
        return
    end

    DutyTracker[source].state = state
    TowJob.Debug('Driver state changed:', source, state)
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
        local Player = QBCore.Functions.GetPlayer(src)
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
