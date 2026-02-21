--[[
    dps-towjob Client NUI
    Dispatch Dashboard UI Handler
]]

local isUIOpen = false

-- Open dispatch UI
function OpenDispatchUI()
    if isUIOpen then return end
    if not IsOnDuty then
        Bridge.Notify('Tow Job', 'You must be on duty', 'error')
        return
    end

    isUIOpen = true
    SetNuiFocus(true, true)

    -- Request data from server
    lib.callback('dps-towjob:server:getDispatchData', false, function(data)
        SendNUIMessage({
            action = 'open',
            queue = data.queue,
            activeJobs = data.activeJobs,
            drivers = data.drivers,
            stats = data.stats,
            playerData = {
                onDuty = IsOnDuty,
                shop = CurrentShop
            }
        })
    end)
end

-- Close dispatch UI
function CloseDispatchUI()
    isUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- NUI Callbacks
RegisterNUICallback('close', function(_, cb)
    CloseDispatchUI()
    cb('ok')
end)

RegisterNUICallback('acceptJob', function(data, cb)
    TriggerServerEvent('dps-towjob:server:acceptJob', data.jobId)
    cb('ok')
end)

RegisterNUICallback('viewOnMap', function(data, cb)
    -- Get job coords from server and set waypoint
    lib.callback('dps-towjob:server:getJobCoords', false, function(coords)
        if coords then
            SetNewWaypoint(coords.x, coords.y)
            Bridge.Notify('Tow Job', 'Waypoint set', 'success')
        end
    end, data.jobId)
    CloseDispatchUI()
    cb('ok')
end)

RegisterNUICallback('refresh', function(_, cb)
    lib.callback('dps-towjob:server:getDispatchData', false, function(data)
        SendNUIMessage({
            action = 'refresh',
            queue = data.queue,
            activeJobs = data.activeJobs,
            drivers = data.drivers,
            stats = data.stats
        })
    end)
    cb('ok')
end)

-- Update UI when data changes
RegisterNetEvent('dps-towjob:client:updateQueue', function(queue)
    if not isUIOpen then return end
    SendNUIMessage({
        action = 'updateQueue',
        queue = queue
    })
end)

RegisterNetEvent('dps-towjob:client:updateActiveJobs', function(activeJobs)
    if not isUIOpen then return end
    SendNUIMessage({
        action = 'updateActiveJobs',
        activeJobs = activeJobs
    })
end)

RegisterNetEvent('dps-towjob:client:updateDrivers', function(drivers)
    if not isUIOpen then return end
    SendNUIMessage({
        action = 'updateDrivers',
        drivers = drivers
    })
end)

RegisterNetEvent('dps-towjob:client:updateStats', function(stats)
    if not isUIOpen then return end
    SendNUIMessage({
        action = 'updateStats',
        stats = stats
    })
end)

-- Toast notification via NUI
function ShowUIToast(message, toastType)
    if not isUIOpen then return end
    SendNUIMessage({
        action = 'toast',
        message = message,
        type = toastType or 'info'
    })
end

-- Command to open dispatch (chat only, F6 handled in thread below)
RegisterCommand('dispatch', function()
    if not Bridge.HasJob(Config.JobName) then
        Bridge.Notify('Tow Job', 'You are not a tow driver', 'error')
        return
    end
    OpenDispatchUI()
end, false)

-- F6 key only active for tow job players (does not reserve the key globally)
CreateThread(function()
    while true do
        local sleep = 500
        if PlayerData.job and PlayerData.job.name == Config.JobName then
            sleep = 0
            if IsControlJustPressed(0, 167) then -- 167 = F6
                OpenDispatchUI()
            end
        end
        Wait(sleep)
    end
end)

-- Export
exports('OpenDispatchUI', OpenDispatchUI)
exports('CloseDispatchUI', CloseDispatchUI)
