--[[
    dps-towjob Client Towing
    Vehicle attachment/detachment mechanics
    Optimized with dynamic threading, localized variables, and rope physics
]]

-- Localize frequently used natives for performance
local PlayerPedId = PlayerPedId
local GetEntityCoords = GetEntityCoords
local GetEntityModel = GetEntityModel
local DoesEntityExist = DoesEntityExist
local GetVehiclePedIsIn = GetVehiclePedIsIn
local GetGamePool = GetGamePool
local GetHashKey = GetHashKey
local Wait = Wait
local vector3 = vector3

-- Localize ox_lib
local lib = lib

-- Local state
local AttachedVehicle = nil
local IsAttaching = false
local TowRope = nil
local WinchActive = false

-- Cache tow vehicle hashes for faster lookup
local TowVehicleHashes = {}
CreateThread(function()
    Wait(1000)
    for model, _ in pairs(Config.TowVehicles) do
        TowVehicleHashes[GetHashKey(model)] = true
    end
end)

-- Check if vehicle is a tow truck (optimized)
local function IsTowTruck(vehicle)
    if not vehicle or vehicle == 0 then return false end
    return TowVehicleHashes[GetEntityModel(vehicle)] == true
end

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

                local ped = PlayerPedId()
                local towVehicle = GetVehiclePedIsIn(ped, true)
                if towVehicle == 0 then return false end

                if IsTowTruck(towVehicle) then
                    return CanTowVehicle(entity)
                end
                return false
            end,
            onSelect = function(data)
                AttachVehicle(data.entity)
            end
        },
        {
            name = 'tow_winch',
            label = 'Winch Vehicle',
            icon = 'fa-solid fa-arrows-up-down',
            distance = 15.0,
            canInteract = function(entity)
                if not IsOnDuty then return false end
                if IsAttaching then return false end
                if AttachedVehicle then return false end
                if WinchActive then return false end

                local towTruck = GetClosestTowTruck()
                if not towTruck then return false end

                return CanTowVehicle(entity)
            end,
            onSelect = function(data)
                StartWinch(data.entity)
            end
        }
    })
end)

-- Rope physics winching system
local function StartWinch(targetVehicle)
    local towVehicle = GetClosestTowTruck()
    if not towVehicle then
        lib.notify({ title = 'Tow Job', description = 'No tow truck nearby', type = 'error' })
        return
    end

    local towCoords = GetEntityCoords(towVehicle)
    local targetCoords = GetEntityCoords(targetVehicle)
    local distance = #(towCoords - targetCoords)

    if distance > 15.0 then
        lib.notify({ title = 'Tow Job', description = 'Vehicle too far for winch', type = 'error' })
        return
    end

    WinchActive = true
    IsAttaching = true

    -- Request rope textures
    RopeLoadTextures()
    while not RopeAreTexturesLoaded() do
        Wait(0)
    end

    -- Get attachment points
    local towBone = GetEntityBoneIndexByName(towVehicle, 'chassis')
    local targetBone = GetEntityBoneIndexByName(targetVehicle, 'chassis')

    local towAttach = GetWorldPositionOfEntityBone(towVehicle, towBone)
    local targetAttach = GetWorldPositionOfEntityBone(targetVehicle, targetBone)

    -- Create rope
    local ropeLength = distance + 2.0
    TowRope = AddRope(
        towAttach.x, towAttach.y, towAttach.z,
        0.0, 0.0, 0.0,
        ropeLength,
        1,    -- Rope type
        ropeLength,
        0.5,  -- Min length
        0.5,  -- Length change rate
        false,
        false,
        false,
        1.0,
        true,
        nil
    )

    -- Attach rope to both vehicles
    AttachRopeToEntity(TowRope, towVehicle, towAttach.x, towAttach.y, towAttach.z, true)
    AttachRopeToEntity(TowRope, targetVehicle, targetAttach.x, targetAttach.y, targetAttach.z, true)

    lib.notify({ title = 'Winching', description = 'Hold position while winching...', type = 'inform' })

    -- Winch animation - slowly pull vehicle
    local winchProgress = lib.progressCircle({
        duration = 8000,
        label = 'Winching vehicle...',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true }
    })

    if winchProgress then
        -- Winch complete - attach normally
        DeleteRope(TowRope)
        TowRope = nil
        RopeUnloadTextures()

        -- Move vehicle close and attach
        local attachPoint = GetOffsetFromEntityInWorldCoords(towVehicle, 0.0, -5.0, 0.0)
        SetEntityCoords(targetVehicle, attachPoint.x, attachPoint.y, attachPoint.z, false, false, false, false)

        Wait(500)
        AttachVehicleInternal(towVehicle, targetVehicle)
    else
        -- Cancelled
        if TowRope then
            DeleteRope(TowRope)
            TowRope = nil
        end
        RopeUnloadTextures()
        lib.notify({ title = 'Winch', description = 'Winching cancelled', type = 'error' })
    end

    WinchActive = false
    IsAttaching = false
end

-- Internal attach function (no progress bar)
local function AttachVehicleInternal(towVehicle, targetVehicle)
    local plate = GetVehicleNumberPlateText(targetVehicle)
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(targetVehicle))
    local location = TowJob.GetStreetName(GetEntityCoords(targetVehicle))

    local towModel = GetEntityModel(towVehicle)

    if towModel == GetHashKey('flatbed') then
        AttachEntityToEntity(targetVehicle, towVehicle, GetEntityBoneIndexByName(towVehicle, 'chassis'), 0.0, -1.5, 0.5, 0.0, 0.0, 0.0, true, true, false, true, 0, true)
    else
        local boneIndex = GetEntityBoneIndexByName(towVehicle, 'chassis_dummy')
        if boneIndex == -1 then boneIndex = 0 end
        AttachVehicleToTowTruck(towVehicle, targetVehicle, boneIndex, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    end

    AttachedVehicle = targetVehicle

    -- Use State Bag instead of TriggerServerEvent for sync
    LocalPlayer.state:set('towingVehicle', NetworkGetNetworkIdFromEntity(targetVehicle), true)

    if CurrentJob then
        TriggerServerEvent('dps-towjob:server:vehicleAttached', CurrentJob.id, {
            plate = plate,
            model = model,
            location = location
        })
    end

    lib.notify({ title = 'Tow Job', description = 'Vehicle attached', type = 'success' })
end

-- Attach vehicle to tow truck
function AttachVehicle(targetVehicle)
    if IsAttaching then return end
    if AttachedVehicle then
        lib.notify({ title = 'Tow Job', description = 'Already have a vehicle attached', type = 'error' })
        return
    end

    local ped = PlayerPedId()
    local towVehicle = GetVehiclePedIsIn(ped, true)

    if towVehicle == 0 then
        towVehicle = GetClosestTowTruck()
        if not towVehicle then
            lib.notify({ title = 'Tow Job', description = 'Get in your tow truck first', type = 'error' })
            return
        end
    end

    local towCoords = GetEntityCoords(towVehicle)
    local targetCoords = GetEntityCoords(targetVehicle)

    if #(towCoords - targetCoords) > Config.Towing.attachDistance then
        lib.notify({ title = 'Tow Job', description = 'Move closer to the vehicle', type = 'error' })
        return
    end

    IsAttaching = true

    if lib.progressCircle({
        duration = 5000,
        label = 'Attaching vehicle...',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_player' }
    }) then
        AttachVehicleInternal(towVehicle, targetVehicle)
    end

    IsAttaching = false
end

-- Detach vehicle
function DetachVehicle()
    if not AttachedVehicle then
        lib.notify({ title = 'Tow Job', description = 'No vehicle attached', type = 'error' })
        return
    end

    local ped = PlayerPedId()
    local towVehicle = GetVehiclePedIsIn(ped, true)

    if towVehicle == 0 then
        towVehicle = GetClosestTowTruck()
    end

    if not towVehicle then return end

    if lib.progressCircle({
        duration = 3000,
        label = 'Detaching vehicle...',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true }
    }) then
        DetachVehicleFromTowTruck(towVehicle, AttachedVehicle)
        DetachEntity(AttachedVehicle, true, true)
        SetVehicleOnGroundProperly(AttachedVehicle)

        local detachedVehicle = AttachedVehicle
        AttachedVehicle = nil

        -- Clear state bag
        LocalPlayer.state:set('towingVehicle', nil, true)

        lib.notify({ title = 'Tow Job', description = 'Vehicle detached', type = 'success' })
        return detachedVehicle
    end
end

-- Get closest tow truck (optimized with hash cache)
function GetClosestTowTruck()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicles = GetGamePool('CVehicle')
    local closest = nil
    local closestDist = Config.Towing.attachDistance

    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if TowVehicleHashes[GetEntityModel(vehicle)] then
            local vehCoords = GetEntityCoords(vehicle)
            local dist = #(coords - vehCoords)
            if dist < closestDist then
                closest = vehicle
                closestDist = dist
            end
        end
    end

    return closest
end

-- Dropoff zones
CreateThread(function()
    Wait(2000)

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
                            if not IsOnDuty or not AttachedVehicle or not CurrentJob then return false end
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
                        if not IsOnDuty or not AttachedVehicle or not CurrentJob then return false end
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
    if not AttachedVehicle or not CurrentJob then return end

    local detachedVehicle = DetachVehicle()
    if not detachedVehicle then return end

    local plate = GetVehicleNumberPlateText(detachedVehicle)
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(detachedVehicle))

    if destinationType == TowJob.DestinationType.IMPOUND then
        TriggerServerEvent('dps-towjob:server:impoundVehicle', plate, destinationId)
        DeleteEntity(detachedVehicle)
    else
        TriggerServerEvent('dps-towjob:server:createServiceTicket', destinationId, {
            plate = plate,
            model = model,
            owner = CurrentJob.requesterId
        }, {
            source = CurrentJob.requesterSource
        })
        SetVehicleDoorsLocked(detachedVehicle, 1)
        SetVehicleHandbrake(detachedVehicle, true)
    end

    TriggerServerEvent('dps-towjob:server:completeJob', CurrentJob.id)
end

-- DYNAMIC THREADING: Speed limit warning while towing
CreateThread(function()
    local GetEntitySpeed = GetEntitySpeed

    while true do
        local sleepTime = 1000  -- Default sleep when not towing

        if AttachedVehicle and DoesEntityExist(AttachedVehicle) then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 then
                local speed = GetEntitySpeed(vehicle) * 2.236936

                if speed > Config.Towing.speedLimit then
                    lib.notify({ title = 'Warning', description = 'Slow down! Vehicle may detach', type = 'warning' })
                    sleepTime = 500  -- Check more frequently when speeding
                elseif speed > Config.Towing.speedLimit * 0.8 then
                    sleepTime = 250  -- Approaching limit, check frequently
                else
                    sleepTime = 1000  -- Normal speed, relax checks
                end
            end
        else
            sleepTime = 2000  -- Not towing, sleep longer
        end

        Wait(sleepTime)
    end
end)

-- DYNAMIC THREADING: Monitor attached vehicle distance
CreateThread(function()
    while true do
        local sleepTime = 2000  -- Default when not towing

        if AttachedVehicle and DoesEntityExist(AttachedVehicle) then
            local towVehicle = GetClosestTowTruck()
            if towVehicle then
                local towCoords = GetEntityCoords(towVehicle)
                local attachedCoords = GetEntityCoords(AttachedVehicle)
                local dist = #(towCoords - attachedCoords)

                if dist > Config.Towing.maxTowDistance then
                    DetachEntity(AttachedVehicle, true, true)
                    SetVehicleOnGroundProperly(AttachedVehicle)
                    AttachedVehicle = nil
                    LocalPlayer.state:set('towingVehicle', nil, true)
                    lib.notify({ title = 'Tow Job', description = 'Vehicle detached due to distance', type = 'error' })
                elseif dist > Config.Towing.maxTowDistance * 0.7 then
                    sleepTime = 100  -- Close to detach, check rapidly
                else
                    sleepTime = 500  -- Normal towing
                end
            end
        end

        Wait(sleepTime)
    end
end)

-- Manual detach keybind (chat only, G key handled in thread below)
RegisterCommand('towdetach', function()
    if AttachedVehicle then
        DetachVehicle()
    end
end, false)

-- G key only active for tow job players while towing (does not reserve the key globally)
CreateThread(function()
    while true do
        local sleep = 500
        if PlayerData.job and PlayerData.job.name == Config.JobName and AttachedVehicle then
            sleep = 0
            if IsControlJustPressed(0, 47) then -- 47 = G
                DetachVehicle()
            end
        end
        Wait(sleep)
    end
end)

-- Exports
exports('HasAttachedVehicle', function()
    return AttachedVehicle ~= nil
end)

exports('GetAttachedVehicle', function()
    return AttachedVehicle
end)
