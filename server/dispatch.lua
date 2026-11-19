--[[
    dps-towjob Server Dispatch
    Integration with qs-dispatch for police/EMS tow requests
]]

-- Framework access goes through Bridge (qbx has no GetCoreObject on this box).
-- NOTE: no standalone dispatch (ps/cd/qs) is installed on this box; the
-- qs-dispatch:* listeners below are inert (never fire) and safe to keep.

--- Does this player already have a call waiting or being worked? One at a time.
local function hasOpenCall(citizenid)
    for i = 1, #TowQueue do
        if TowQueue[i].requesterId == citizenid then return true end
    end
    for _, job in pairs(ActiveJobs) do
        if job.requesterId == citizenid then return true end
    end
    return false
end

--- Is there a vehicle within range of this player? The server looks itself.
local function vehicleNear(source, range)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    local at = GetEntityCoords(ped)
    for _, veh in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(veh) - at) <= range then return true end
    end
    return false
end

--- Coordinates that arrive as a plain table are turned into a vector before
--- anything measures a distance with them. A bad value answers nil, and the
--- caller refuses the request rather than throwing later on.
local function toVector(value)
    if value == nil then return nil end
    if type(value) ~= 'table' then
        local ok = pcall(function() return value.x + 0.0 end)
        if ok and value.x and value.y and value.z then return vector3(value.x + 0.0, value.y + 0.0, value.z + 0.0) end
        return nil
    end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not x or not y or not z then return nil end
    return vector3(x + 0.0, y + 0.0, z + 0.0)
end

-- Handle tow request from qs-dispatch
RegisterNetEvent('dps-towjob:server:dispatchRequest', function(data)
    local source = source
    local Player = Bridge.GetPlayer(source)

    if not Player then return end
    if type(data) ~= 'table' then return end

    -- Police and medical only, on duty. Everyone else uses the City Services
    -- app or /calltow, which have their own checks.
    local job = Player.PlayerData.job
    local jobType
    -- DPS 2026-09-25: job types from qbx_core (leo / ems) instead of vendor names
    if job.type == 'leo' or job.name == 'police' then
        jobType = TowJob.JobTypes.POLICE
    elseif job.type == 'ems' or job.name == 'sams' or job.name == 'lsmc' then
        jobType = TowJob.JobTypes.EMS
    end
    if not jobType or not job.onduty then return end
    if CheckCooldown(source, 'dispatchRequest') then
        lib.notify(source, { title = 'Tow Request', description = 'Wait a moment before asking for another tow', type = 'error' })
        return
    end

    -- The vehicle has to be near the officer asking: within 150 m, or the
    -- officer's own position is used.
    local here = GetEntityCoords(GetPlayerPed(source))
    local coords = toVector(data.coords)
    if not coords or #(coords - here) > 150.0 then coords = here end

    local success, jobId = AddToQueue({
        type = jobType,
        priority = TowJob.GetPriority(jobType),
        coords = coords,
        plate = TowLifecycle.sanitizeLabel(data.plate, 10),
        model = TowLifecycle.sanitizeLabel(data.model, 30),
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

-- Customer request from phone/mechanic call
RegisterNetEvent('dps-towjob:server:customerRequest', function(coords, description)
    local source = source
    local Player = Bridge.GetPlayer(source)

    if not Player then return end

    -- The pickup is where the caller stands, read by the server. A vehicle has
    -- to be next to them, they can have one call open, and there is a wait
    -- between calls. This is what stops a queue full of made-up calls.
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end
    local at = GetEntityCoords(ped)
    local function refuse(why)
        lib.notify(source, { title = 'Tow Request', description = why, type = 'error' })
    end
    if hasOpenCall(Player.PlayerData.citizenid) then return refuse('You already have a tow on the way') end
    if not vehicleNear(source, Config.Requests.vehicleRange or 10.0) then return refuse('No vehicle nearby') end
    if CheckCooldown(source, 'customerRequest') then return refuse('Wait a couple of minutes before calling again') end

    local success, jobId = AddToQueue({
        type = TowJob.JobTypes.CUSTOMER,
        coords = at,
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

--- Tell the shop's mechanics a vehicle arrived. Server side only.
local function notifyMechanics(shopId, data)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.mechanicJob or type(data) ~= 'table' then return end

    local players = Bridge.GetPlayers()

    for _, src in ipairs(players) do
        local Player = Bridge.GetPlayer(src)
        if Player then
            local job = Player.PlayerData.job
            if job.name == shop.mechanicJob and job.onduty then
                lib.notify(src, {
                    title = 'Incoming Vehicle',
                    description = string.format('%s [%s] dropped off by tow',
                        TowLifecycle.sanitizeLabel(data.vehicleModel, 30),
                        TowLifecycle.sanitizeLabel(data.plate, 10)),
                    type = 'inform',
                    duration = 8000,
                    icon = 'truck-ramp-box'
                })
            end
        end
    end
end

-- The same notice from a client. Any client could send a shop a fake arrival,
-- so the sender must hold the mechanic or the tow job and be on duty.
RegisterNetEvent('dps-towjob:server:notifyMechanics', function(shopId, data)
    local source = source
    if not IsShopStaff(source) then return end
    notifyMechanics(shopId, data)
end)

--- Create a repair ticket at a shop. towedBy is a citizenid, or 'CITYTOW'.
function CreateServiceTicket(shopId, vehicleData, customerData, towedBy)
    if not Config.ShopJobMapping[shopId] or type(vehicleData) ~= 'table' then return nil end

    local ticketId = TowJob.GenerateId()

    MySQL.insert.await([[
        INSERT INTO tow_service_tickets (id, shop, vehicle_data, customer_data, status, towed_by)
        VALUES (?, ?, ?, ?, 'awaiting_repair', ?)
    ]], {
        ticketId,
        shopId,
        json.encode(vehicleData),
        json.encode(customerData or {}),
        towedBy,
    })

    notifyMechanics(shopId, {
        vehicleModel = vehicleData.model,
        plate = vehicleData.plate,
    })

    TowJob.Debug('Service ticket created:', ticketId)
    return ticketId
end

-- Create service ticket when a driver delivers a vehicle to a shop. The ticket
-- is written from the server's own record of the job, never from what the
-- client sent with it.
RegisterNetEvent('dps-towjob:server:createServiceTicket', function(shopId)
    local source = source
    local Player = Bridge.GetPlayer(source)
    if not Player then return end
    local job = ActiveJobs[source]
    if not job or not job.destination or job.destination.id ~= shopId then return end
    CreateServiceTicket(shopId,
        { plate = job.vehiclePlate, model = job.vehicleModel, owner = job.requesterId },
        { citizenid = job.requesterId }, Player.PlayerData.citizenid)
end)
