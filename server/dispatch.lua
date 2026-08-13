--[[
    dps-towjob Server Dispatch
    Integration with qs-dispatch for police/EMS tow requests
]]

-- Framework access goes through Bridge (qbx has no GetCoreObject on this box).
-- NOTE: no standalone dispatch (ps/cd/qs) is installed on this box; the
-- qs-dispatch:* listeners below are inert (never fire) and safe to keep.

-- Handle tow request from qs-dispatch
RegisterNetEvent('dps-towjob:server:dispatchRequest', function(data)
    local source = source
    local Player = Bridge.GetPlayer(source)

    if not Player then return end

    local job = Player.PlayerData.job
    local jobType = TowJob.JobTypes.CUSTOMER

    -- Determine priority based on job
    if job.name == 'police' then
        jobType = TowJob.JobTypes.POLICE
    elseif job.name == 'ambulance' or job.name == 'ems' then
        jobType = TowJob.JobTypes.EMS
    end

    local success, jobId = AddToQueue({
        type = jobType,
        priority = TowJob.GetPriority(jobType),
        coords = data.coords,
        plate = data.plate,
        model = data.model,
        requesterId = Player.PlayerData.citizenid,
        requesterSource = source
    })

    if success then
        lib.notify(source, {
            title = 'Tow Request',
            description = 'Tow requested. Job ID: ' .. jobId,
            type = 'success'
        })

        -- Notify available tow drivers
        local drivers = GetAvailableDrivers()
        for _, driver in ipairs(drivers) do
            lib.notify(driver.source, {
                title = 'New Tow Request',
                description = string.format('%s request - %s', jobType:upper(), data.street or 'Unknown location'),
                type = 'inform',
                icon = 'truck-ramp-box'
            })
        end
    else
        lib.notify(source, {
            title = 'Tow Request',
            description = 'Failed to request tow: ' .. (jobId or 'Unknown error'),
            type = 'error'
        })
    end
end)

-- qs-dispatch integration event
RegisterNetEvent('qs-dispatch:server:requestTow', function(data)
    local source = source

    TriggerEvent('dps-towjob:server:dispatchRequest', {
        coords = data.coords or GetEntityCoords(GetPlayerPed(source)),
        plate = data.plate,
        model = data.model,
        street = data.street
    })
end)

-- Customer request from phone/mechanic call
RegisterNetEvent('dps-towjob:server:customerRequest', function(coords, description)
    local source = source
    local Player = Bridge.GetPlayer(source)

    if not Player then return end

    local success, jobId = AddToQueue({
        type = TowJob.JobTypes.CUSTOMER,
        coords = coords or GetEntityCoords(GetPlayerPed(source)),
        requesterId = Player.PlayerData.citizenid,
        requesterSource = source
    })

    if success then
        lib.notify(source, {
            title = 'Tow Request',
            description = 'A tow driver will be dispatched shortly',
            type = 'success'
        })
    else
        lib.notify(source, {
            title = 'Tow Request',
            description = 'Unable to request tow at this time',
            type = 'error'
        })
    end
end)

-- Get estimated wait time
lib.callback.register('dps-towjob:server:getWaitTime', function(source)
    local queueLength = #TowQueue
    local availableDrivers = #GetAvailableDrivers()

    if availableDrivers == 0 then
        return nil, 'No drivers available'
    end

    -- Rough estimate: 5 minutes per job in queue
    local estimatedMinutes = math.ceil(queueLength * 5 / availableDrivers)

    return estimatedMinutes
end)

-- Notify mechanics when vehicle is dropped off
RegisterNetEvent('dps-towjob:server:notifyMechanics', function(shopId, data)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.mechanicJob then return end

    local players = Bridge.GetPlayers()

    for _, src in ipairs(players) do
        local Player = Bridge.GetPlayer(src)
        if Player then
            local job = Player.PlayerData.job
            if job.name == shop.mechanicJob and job.onduty then
                lib.notify(src, {
                    title = 'Incoming Vehicle',
                    description = string.format('%s [%s] dropped off by tow', data.vehicleModel, data.plate),
                    type = 'inform',
                    duration = 8000,
                    icon = 'truck-ramp-box'
                })
            end
        end
    end
end)

-- Create service ticket when vehicle delivered to shop
RegisterNetEvent('dps-towjob:server:createServiceTicket', function(shopId, vehicleData, customerData)
    local source = source
    local Player = Bridge.GetPlayer(source)

    if not Player then return end

    local ticketId = TowJob.GenerateId()

    MySQL.insert.await([[
        INSERT INTO tow_service_tickets (id, shop, vehicle_data, customer_data, status, towed_by)
        VALUES (?, ?, ?, ?, 'awaiting_repair', ?)
    ]], {
        ticketId,
        shopId,
        json.encode(vehicleData),
        json.encode(customerData),
        Player.PlayerData.citizenid
    })

    -- Notify mechanics
    TriggerEvent('dps-towjob:server:notifyMechanics', shopId, {
        vehicleModel = vehicleData.model,
        plate = vehicleData.plate
    })

    TowJob.Debug('Service ticket created:', ticketId)

    return ticketId
end)
