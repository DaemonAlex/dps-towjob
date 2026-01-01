--[[
    dps-towjob Client Towing
    Vehicle attachment/detachment mechanics
]]

local QBCore = exports['qb-core']:GetCoreObject()

local AttachedVehicle = nil
local IsAttaching = false

-- Target for towable vehicles
CreateThread(function()
    exports.ox_target:addGlobalVehicle({
        {
            name = 'tow_attach',
            label = 'Attach to Tow Truck',
            icon = 'fa-solid fa-link',
            distance = 3.0,
            canInteract = function(entity)
                if not IsOnDuty then return false end
                if IsAttaching then return false end
                if AttachedVehicle then return false end

                -- Check if we're in a tow truck
                local ped = PlayerPedId()
                local towVehicle = GetVehiclePedIsIn(ped, true)
                if towVehicle == 0 then return false end

                -- Check if it's a tow truck
                local model = GetEntityModel(towVehicle)
                for towModel, _ in pairs(Config.TowVehicles) do
                    if GetHashKey(towModel) == model then
                        -- Check if target can be towed
                        return CanTowVehicle(entity)
                    end
                end

                return false
            end,
            onSelect = function(data)
                AttachVehicle(data.entity)
            end
        }
    })
end)

-- Attach vehicle to tow truck
function AttachVehicle(targetVehicle)
    if IsAttaching then return end
    if AttachedVehicle then
        lib.notify({
            title = 'Tow Job',
            description = 'Already have a vehicle attached',
            type = 'error'
        })
        return
    end

    local ped = PlayerPedId()
    local towVehicle = GetVehiclePedIsIn(ped, true)

    if towVehicle == 0 then
        -- Try to find nearby tow truck
        towVehicle = GetClosestTowTruck()
        if not towVehicle then
            lib.notify({
                title = 'Tow Job',
                description = 'Get in your tow truck first',
                type = 'error'
            })
            return
        end
    end

    -- Check distance
    local towCoords = GetEntityCoords(towVehicle)
    local targetCoords = GetEntityCoords(targetVehicle)

    if #(towCoords - targetCoords) > Config.Towing.attachDistance then
        lib.notify({
            title = 'Tow Job',
            description = 'Move closer to the vehicle',
            type = 'error'
        })
        return
    end

    IsAttaching = true

    -- Progress bar for attaching
    if lib.progressCircle({
        duration = 5000,
        label = 'Attaching vehicle...',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true
        },
        anim = {
            dict = 'mini@repair',
            clip = 'fixing_a_player'
        }
    }) then
        -- Get vehicle info before attaching
        local plate = GetVehicleNumberPlateText(targetVehicle)
        local model = GetDisplayNameFromVehicleModel(GetEntityModel(targetVehicle))
        local location = TowJob.GetStreetName(targetCoords)

        -- Native attach for flatbed/towtruck
        local towModel = GetEntityModel(towVehicle)

        if towModel == GetHashKey('flatbed') then
            -- Flatbed attachment
            AttachEntityToEntity(targetVehicle, towVehicle, GetEntityBoneIndexByName(towVehicle, 'chassis'), 0.0, -1.5, 0.5, 0.0, 0.0, 0.0, true, true, false, true, 0, true)
        else
            -- Standard tow truck hook
            AttachVehicleToTowTruck(towVehicle, targetVehicle, GetEntityBoneIndexByName(towVehicle, 'chassis_dummy') ~= -1 and GetEntityBoneIndexByName(towVehicle, 'chassis_dummy') or -1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        end

        AttachedVehicle = targetVehicle

        -- Notify server
        if CurrentJob then
            TriggerServerEvent('dps-towjob:server:vehicleAttached', CurrentJob.id, {
                plate = plate,
                model = model,
                location = location
            })
        end

        lib.notify({
            title = 'Tow Job',
            description = 'Vehicle attached',
            type = 'success'
        })
    end

    IsAttaching = false
end

-- Detach vehicle
function DetachVehicle()
    if not AttachedVehicle then
        lib.notify({
            title = 'Tow Job',
            description = 'No vehicle attached',
            type = 'error'
        })
        return
    end

    local ped = PlayerPedId()
    local towVehicle = GetVehiclePedIsIn(ped, true)

    if towVehicle == 0 then
        towVehicle = GetClosestTowTruck()
    end

    if not towVehicle then return end

    -- Progress bar for detaching
    if lib.progressCircle({
        duration = 3000,
        label = 'Detaching vehicle...',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true
        }
    }) then
        -- Detach
        DetachVehicleFromTowTruck(towVehicle, AttachedVehicle)
        DetachEntity(AttachedVehicle, true, true)

        -- Set on ground
        SetVehicleOnGroundProperly(AttachedVehicle)

        local detachedVehicle = AttachedVehicle
        AttachedVehicle = nil

        lib.notify({
            title = 'Tow Job',
            description = 'Vehicle detached',
            type = 'success'
        })

        return detachedVehicle
    end
end

-- Get closest tow truck
function GetClosestTowTruck()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicles = GetGamePool('CVehicle')
    local closest = nil
    local closestDist = Config.Towing.attachDistance

    for _, vehicle in ipairs(vehicles) do
        local model = GetEntityModel(vehicle)
        for towModel, _ in pairs(Config.TowVehicles) do
            if GetHashKey(towModel) == model then
                local vehCoords = GetEntityCoords(vehicle)
                local dist = #(coords - vehCoords)
                if dist < closestDist then
                    closest = vehicle
                    closestDist = dist
                end
            end
        end
    end

    return closest
end

-- Dropoff zones
CreateThread(function()
    Wait(2000)

    -- Shop dropoff zones
    for shopId, shop in pairs(Config.ShopJobMapping) do
        if shop.towShop and shop.vehicleDropoff then
            exports.ox_target:addSphereZone({
                coords = shop.vehicleDropoff,
                radius = 5.0,
                debug = Config.Debug,
                options = {
                    {
                        name = 'tow_dropoff_' .. shopId,
                        label = 'Drop Off Vehicle',
                        icon = 'fa-solid fa-truck-ramp-box',
                        distance = 5.0,
                        canInteract = function()
                            if not IsOnDuty then return false end
                            if not AttachedVehicle then return false end
                            if not CurrentJob then return false end
                            if CurrentJob.destination and CurrentJob.destination.type == TowJob.DestinationType.SHOP then
                                return CurrentJob.destination.id == shopId
                            end
                            return false
                        end,
                        onSelect = function()
                            CompleteDropoff(shopId, TowJob.DestinationType.SHOP)
                        end
                    }
                }
            })
        end
    end

    -- Impound dropoff zones
    for impoundId, impound in pairs(Config.ImpoundLots) do
        exports.ox_target:addSphereZone({
            coords = impound.dropoff,
            radius = 5.0,
            debug = Config.Debug,
            options = {
                {
                    name = 'tow_impound_' .. impoundId,
                    label = 'Impound Vehicle',
                    icon = 'fa-solid fa-warehouse',
                    distance = 5.0,
                    canInteract = function()
                        if not IsOnDuty then return false end
                        if not AttachedVehicle then return false end
                        if not CurrentJob then return false end
                        if CurrentJob.destination and CurrentJob.destination.type == TowJob.DestinationType.IMPOUND then
                            return CurrentJob.destination.id == impoundId
                        end
                        return false
                    end,
                    onSelect = function()
                        CompleteDropoff(impoundId, TowJob.DestinationType.IMPOUND)
                    end
                }
            }
        })
    end
end)

-- Complete dropoff
function CompleteDropoff(destinationId, destinationType)
    if not AttachedVehicle then return end
    if not CurrentJob then return end

    local detachedVehicle = DetachVehicle()
    if not detachedVehicle then return end

    -- Get vehicle data before deleting/storing
    local plate = GetVehicleNumberPlateText(detachedVehicle)
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(detachedVehicle))

    if destinationType == TowJob.DestinationType.IMPOUND then
        -- Impound the vehicle - update database
        TriggerServerEvent('dps-towjob:server:impoundVehicle', plate, destinationId)

        -- Delete entity
        DeleteEntity(detachedVehicle)
    else
        -- Shop dropoff - notify mechanics
        TriggerServerEvent('dps-towjob:server:createServiceTicket', destinationId, {
            plate = plate,
            model = model,
            owner = CurrentJob.requesterId
        }, {
            source = CurrentJob.requesterSource
        })

        -- Leave vehicle parked
        SetVehicleDoorsLocked(detachedVehicle, 1)
        SetVehicleHandbrake(detachedVehicle, true)
    end

    -- Complete the job
    TriggerServerEvent('dps-towjob:server:completeJob', CurrentJob.id)
end

-- Speed limit warning while towing
CreateThread(function()
    while true do
        Wait(1000)

        if AttachedVehicle and DoesEntityExist(AttachedVehicle) then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 then
                local speed = GetEntitySpeed(vehicle) * 2.236936 -- Convert to mph

                if speed > Config.Towing.speedLimit then
                    lib.notify({
                        title = 'Warning',
                        description = 'Slow down! Vehicle may detach',
                        type = 'warning'
                    })
                end
            end
        end
    end
end)

-- Monitor attached vehicle distance
CreateThread(function()
    while true do
        Wait(500)

        if AttachedVehicle and DoesEntityExist(AttachedVehicle) then
            local towVehicle = GetClosestTowTruck()
            if towVehicle then
                local towCoords = GetEntityCoords(towVehicle)
                local attachedCoords = GetEntityCoords(AttachedVehicle)
                local dist = #(towCoords - attachedCoords)

                if dist > Config.Towing.maxTowDistance then
                    -- Force detach
                    DetachEntity(AttachedVehicle, true, true)
                    SetVehicleOnGroundProperly(AttachedVehicle)
                    AttachedVehicle = nil

                    lib.notify({
                        title = 'Tow Job',
                        description = 'Vehicle detached due to distance',
                        type = 'error'
                    })
                end
            end
        end
    end
end)

-- Manual detach keybind
RegisterCommand('towdetach', function()
    if AttachedVehicle then
        DetachVehicle()
    end
end, false)

RegisterKeyMapping('towdetach', 'Detach Towed Vehicle', 'keyboard', 'G')

-- Exports
exports('HasAttachedVehicle', function()
    return AttachedVehicle ~= nil
end)

exports('GetAttachedVehicle', function()
    return AttachedVehicle
end)
