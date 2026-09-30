--[[
    dps-towjob server/handoff.lua
    Where a towed vehicle ends up.

    Deleting a car out of the world is only half a tow. jg-advancedgarages
    decides where an owned car is by the `player_vehicles` columns `in_garage`,
    `garage_id`, `impound`, `impound_retrievable` and `impound_data`, and
    dps-vehiclepersistence spawns a parked car again at every server start
    unless it is told the car was handled. So the hand-off writes exactly the
    statements the garage script writes itself, then tells persistence.

    HandOffVehicle(job) runs once per delivered request, on the City Tow path
    and on a player driver's. Never for a console test, never for an AI call.
]]

local PERSISTENCE = 'dps-vehiclepersistence'

--- Tell the persistence script to forget a car it is holding, so it is not
--- spawned again in the street at the next server start.
local function tellPersistence(plate, action)
    if GetResourceState(PERSISTENCE) ~= 'started' then return false end
    local ok, err = pcall(function()
        exports[PERSISTENCE]:NotifyVehicleHandled(plate, action, 'dps-towjob')
    end)
    if not ok then
        TowJob.Debug('NotifyVehicleHandled failed:', tostring(err))
    end
    return ok
end

--- The garage script's own list of garages and impound lots.
local function loadPlaces()
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT name, kind, restriction_type, vehicle_type, disabled, map_position
            FROM garage_locations
        ]])
    end)
    if not ok or type(rows) ~= 'table' then
        TowJob.Debug('garage_locations could not be read; no hand-off place chosen')
        return {}
    end
    local places = {}
    for i = 1, #rows do
        local row = rows[i]
        local position
        if type(row.map_position) == 'string' then
            local decoded, value = pcall(json.decode, row.map_position)
            if decoded and type(value) == 'table' then position = value end
        elseif type(row.map_position) == 'table' then
            position = row.map_position
        end
        if position then
            places[#places + 1] = {
                name = row.name,
                kind = row.kind,
                restriction_type = row.restriction_type,
                vehicle_type = row.vehicle_type,
                disabled = row.disabled,
                x = tonumber(position.x),
                y = tonumber(position.y),
                z = tonumber(position.z),
            }
        end
    end
    return places
end

--- The owner's row, found by the plate however it is spelled. Ordered, so two
--- rows that differ only by their padding always resolve to the same one.
local function ownedVehicle(plate)
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT plate, citizenid, garage_id, in_garage FROM player_vehicles
            WHERE REPLACE(plate, ' ', '') = ? ORDER BY id LIMIT 1
        ]], { plate })
    end)
    if not ok or type(row) ~= 'table' then return nil end
    return row
end

--- The garage script's own store statement and nothing else: a repair tow does
--- not touch the impound columns.
local function storeInGarage(row, garageName)
    MySQL.update.await([[
        UPDATE player_vehicles SET in_garage = 1, garage_id = ? WHERE plate = ?
    ]], { garageName, row.plate })
end

local function putInImpound(row, job, lotName)
    local data = json.encode({
        charname = job.requesterName or 'City Services',
        reason = 'Towed at the request of ' .. (job.requesterJobLabel or 'the city'),
        retrieval_date = os.time(),
        retrieval_cost = Config.Requests.impoundReleaseFee or 0,
        original_garage_id = row.garage_id,
    })
    MySQL.update.await([[
        UPDATE player_vehicles
        SET impound = 1, impound_retrievable = 1, in_garage = 0, garage_id = ?, impound_data = ?
        WHERE plate = ?
    ]], { lotName, data, row.plate })
end

--- Tell an owner who did not ask for the tow where their vehicle went.
local function tellOwner(row, job, plate, label)
    if not row or not row.citizenid or row.citizenid == job.requesterId then return end
    local player = Bridge.GetPlayerByIdentifier(row.citizenid)
    if not player or not player.PlayerData then return end
    Bridge.Notify(player.PlayerData.source, 'City Services',
        ('Your vehicle %s was impounded. Collect it at %s.'):format(plate, label), 'inform')
end

--- Put the towed vehicle where the app says it is. Returns the place's name,
--- or nil when there was nothing to move (an unowned or job vehicle).
---
--- Only a vehicle that left the world is moved on paper. A player driver who
--- drops a repair tow at a shop leaves the vehicle standing there for the
--- mechanic, and "Delivered to <shop>" is already true for it; filing it into
--- a garage as well would let the owner drive a second copy out.
function HandOffVehicle(job)
    if type(job) ~= 'table' or job.test or not job.kind then return nil end
    if job.handoffDone then return job.handoffLabel end
    job.handoffDone = true

    local plate = TowLifecycle.cleanPlate(job.vehiclePlate)
    if not plate then return nil end

    local impound = job.kind == 'impound'
    if not impound and not job.cityTow then
        TowJob.Debug('Hand-off: repair tow left at the shop, nothing to file:', plate)
        return nil
    end
    local dropoff = (job.destination and job.destination.coords) or job.pickupCoords
    local placeName = TowLifecycle.nearestPlace(loadPlaces(), dropoff, impound and 'impound' or 'garage')
    local row = ownedVehicle(plate)

    local action = TowLifecycle.handoffAction(job.kind, row)
    if action == 'in_garage' then
        -- The row says the car is parked in a garage, so this is not the car
        -- that was towed. Leave the owner's row alone.
        print(('[dps-towjob] hand-off skipped: %s is already in a garage, impound row not written (job %s)')
            :format(plate, tostring(job.id)))
    elseif not placeName then
        if row then TowJob.Debug('No place found for the hand-off of', plate, 'job', job.id) end
    elseif action == 'impound' then
        putInImpound(row, job, placeName)
        job.handoffLabel = placeName
        tellOwner(row, job, plate, placeName)
    elseif action == 'garage' then
        storeInGarage(row, placeName)
        job.handoffLabel = placeName .. ' garage'
    end

    -- An unowned or job vehicle has no row to move, but persistence still has
    -- to be told, or it puts the car back in the street at the next start.
    tellPersistence(plate, impound and 'impounded' or 'stored')

    TowJob.Debug('Hand-off:', plate, job.kind, job.handoffLabel or 'no place')
    return job.handoffLabel
end

exports('HandOffVehicle', HandOffVehicle)
