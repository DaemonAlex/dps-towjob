--[[
    dps-towjob Client Queue
    Queue display and status updates
]]

-- Queue update from server
RegisterNetEvent('dps-towjob:client:queueUpdate', function(queueInfo)
    -- Could display queue status in UI
    TowJob.Debug('Queue update received:', #queueInfo.queue, 'jobs')
end)

-- View queue command (for drivers)
RegisterCommand('towqueue', function()
    if not IsOnDuty then
        lib.notify({
            title = 'Tow Job',
            description = 'You must be on duty',
            type = 'error'
        })
        return
    end

    lib.callback('dps-towjob:server:getQueueInfo', false, function(info)
        if not info then return end

        local content = string.format([[
**Queue Status**
Jobs waiting: %d
Available drivers: %d

**Your Status**
State: %s
Shop: %s
        ]],
            info.length,
            #info.drivers,
            CurrentJob and 'BUSY' or 'AVAILABLE',
            CurrentShop or 'None'
        )

        lib.alertDialog({
            header = 'Tow Queue',
            content = content,
            centered = true
        })
    end)
end, false)

-- View on-duty drivers
RegisterCommand('towdrivers', function()
    lib.callback('dps-towjob:server:getOnDutyDrivers', false, function(drivers)
        if not drivers or #drivers == 0 then
            lib.notify({
                title = 'Tow Service',
                description = 'No drivers on duty',
                type = 'inform'
            })
            return
        end

        local options = {}
        for _, driver in ipairs(drivers) do
            local shop = Config.ShopJobMapping[driver.shop]
            table.insert(options, {
                title = driver.name,
                description = string.format('%s - %s', shop and shop.label or 'Unknown', driver.state:upper()),
                icon = driver.state == 'available' and 'fa-solid fa-circle-check' or 'fa-solid fa-truck',
                iconColor = driver.state == 'available' and 'green' or 'orange'
            })
        end

        lib.registerContext({
            id = 'tow_drivers_list',
            title = 'On Duty Tow Drivers (' .. #drivers .. ')',
            options = options
        })

        lib.showContext('tow_drivers_list')
    end)
end, false)

-- Request tow as customer
RegisterCommand('calltow', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    -- Check if near a vehicle
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)

    if vehicle == 0 then
        lib.notify({
            title = 'Tow Service',
            description = 'No vehicle nearby',
            type = 'error'
        })
        return
    end

    -- Get wait time estimate
    lib.callback('dps-towjob:server:getWaitTime', false, function(minutes, error)
        if error then
            lib.notify({
                title = 'Tow Service',
                description = error,
                type = 'error'
            })
            return
        end

        local confirm = lib.alertDialog({
            header = 'Request Tow',
            content = string.format([[
A tow truck will be dispatched to your location.

Estimated wait: ~%d minutes

Proceed with request?
            ]], minutes or 5),
            centered = true,
            cancel = true
        })

        if confirm == 'confirm' then
            TriggerServerEvent('dps-towjob:server:customerRequest', coords)
        end
    end)
end, false)

-- NUI callbacks (if using custom UI)
RegisterNUICallback('acceptJob', function(data, cb)
    if CurrentJob and CurrentJob.id == data.jobId then
        TriggerServerEvent('dps-towjob:server:acceptJob', data.jobId)
    end
    cb('ok')
end)

RegisterNUICallback('cancelJob', function(data, cb)
    if CurrentJob and CurrentJob.id == data.jobId then
        TriggerServerEvent('dps-towjob:server:cancelJob', data.jobId, data.reason or 'Driver cancelled')
    end
    cb('ok')
end)

RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)
