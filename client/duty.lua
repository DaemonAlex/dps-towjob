--[[
    dps-towjob Client Duty
    Clock in/out targets and depot interactions
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Create duty targets at shop depots
CreateThread(function()
    Wait(2000) -- Wait for config to load

    for shopId, shop in pairs(Config.ShopJobMapping) do
        if shop.towShop and shop.depot then
            -- Create ox_target zone for clock in/out
            exports.ox_target:addSphereZone({
                coords = vector3(shop.depot.x, shop.depot.y, shop.depot.z),
                radius = 2.0,
                debug = Config.Debug,
                options = {
                    {
                        name = 'tow_clockin_' .. shopId,
                        label = 'Clock In/Out',
                        icon = 'fa-solid fa-clock',
                        distance = 2.0,
                        canInteract = function()
                            return PlayerData.job and PlayerData.job.name == Config.JobName
                        end,
                        onSelect = function()
                            TriggerServerEvent('dps-towjob:server:toggleDuty', shopId)
                        end
                    },
                    {
                        name = 'tow_vehicle_' .. shopId,
                        label = 'Get Tow Vehicle',
                        icon = 'fa-solid fa-truck-pickup',
                        distance = 2.0,
                        canInteract = function()
                            return IsOnDuty and CurrentShop == shopId
                        end,
                        onSelect = function()
                            OpenVehicleMenu(shopId)
                        end
                    },
                    {
                        name = 'tow_return_' .. shopId,
                        label = 'Return Vehicle',
                        icon = 'fa-solid fa-warehouse',
                        distance = 2.0,
                        canInteract = function()
                            if not IsOnDuty then return false end
                            local veh = GetVehiclePedIsIn(PlayerPedId(), false)
                            if veh == 0 then return false end
                            local model = GetEntityModel(veh)
                            for towModel, _ in pairs(Config.TowVehicles) do
                                if GetHashKey(towModel) == model then
                                    return true
                                end
                            end
                            return false
                        end,
                        onSelect = function()
                            ReturnTowVehicle()
                        end
                    }
                }
            })

            -- Create blip (visible to everyone)
            if shop.blip then
                local blip = AddBlipForCoord(shop.depot.x, shop.depot.y, shop.depot.z)
                SetBlipSprite(blip, Config.Blips.depot.sprite)
                SetBlipColour(blip, Config.Blips.depot.color)
                SetBlipScale(blip, Config.Blips.depot.scale)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(shop.label)
                EndTextCommandSetBlipName(blip)
            end
        end
    end

    TowJob.Debug('Duty targets created')
end)

-- Vehicle selection menu
function OpenVehicleMenu(shopId)
    local shop = Config.ShopJobMapping[shopId]
    if not shop then return end

    local grade = PlayerData.job.grade.level or 0
    local available = GetAvailableTowVehicles(grade)

    local options = {}

    for model, data in pairs(available) do
        table.insert(options, {
            title = data.label,
            description = string.format('Grade %d+ required', data.minGrade),
            icon = 'fa-solid fa-truck',
            disabled = grade < data.minGrade,
            onSelect = function()
                SpawnTowVehicle(shopId, model)
            end
        })
    end

    if #options == 0 then
        lib.notify({
            title = 'Tow Job',
            description = 'No vehicles available for your grade',
            type = 'error'
        })
        return
    end

    lib.registerContext({
        id = 'tow_vehicle_menu',
        title = 'Select Vehicle',
        options = options
    })

    lib.showContext('tow_vehicle_menu')
end

-- Spawn tow vehicle
function SpawnTowVehicle(shopId, model)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.vehicleSpawn then
        lib.notify({
            title = 'Tow Job',
            description = 'No spawn point configured',
            type = 'error'
        })
        return
    end

    -- Check if already has a tow vehicle
    if CurrentVehicle and DoesEntityExist(CurrentVehicle) then
        lib.notify({
            title = 'Tow Job',
            description = 'Return your current vehicle first',
            type = 'error'
        })
        return
    end

    local spawn = shop.vehicleSpawn

    -- Load model
    local hash = GetHashKey(model)
    RequestModel(hash)

    local timeout = 10000
    while not HasModelLoaded(hash) and timeout > 0 do
        Wait(100)
        timeout = timeout - 100
    end

    if not HasModelLoaded(hash) then
        lib.notify({
            title = 'Tow Job',
            description = 'Failed to load vehicle model',
            type = 'error'
        })
        return
    end

    -- Check if spawn is clear
    local vehicles = GetGamePool('CVehicle')
    for _, veh in ipairs(vehicles) do
        local vehCoords = GetEntityCoords(veh)
        if #(vector3(spawn.x, spawn.y, spawn.z) - vehCoords) < 3.0 then
            lib.notify({
                title = 'Tow Job',
                description = 'Spawn point blocked',
                type = 'error'
            })
            SetModelAsNoLongerNeeded(hash)
            return
        end
    end

    -- Create vehicle
    local vehicle = CreateVehicle(hash, spawn.x, spawn.y, spawn.z, spawn.w, true, false)

    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleNumberPlateText(vehicle, 'TOW' .. math.random(1000, 9999))
    SetVehicleFuelLevel(vehicle, 100.0)
    SetVehicleEngineHealth(vehicle, 1000.0)

    -- Set as job vehicle
    SetVehicleExtra(vehicle, 1, false) -- Enable extra 1 if exists (lightbar, etc.)

    -- Give keys
    TriggerEvent('vehiclekeys:client:SetOwner', GetVehicleNumberPlateText(vehicle))

    CurrentVehicle = vehicle
    SetModelAsNoLongerNeeded(hash)

    -- Warp player in
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)

    lib.notify({
        title = 'Tow Job',
        description = 'Vehicle ready',
        type = 'success'
    })

    TowJob.Debug('Spawned tow vehicle:', model)
end

-- Return tow vehicle
function ReturnTowVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        lib.notify({
            title = 'Tow Job',
            description = 'You must be in a vehicle',
            type = 'error'
        })
        return
    end

    -- Check if it's a tow vehicle
    local model = GetEntityModel(vehicle)
    local isTowVehicle = false

    for towModel, _ in pairs(Config.TowVehicles) do
        if GetHashKey(towModel) == model then
            isTowVehicle = true
            break
        end
    end

    if not isTowVehicle then
        lib.notify({
            title = 'Tow Job',
            description = 'This is not a tow vehicle',
            type = 'error'
        })
        return
    end

    -- Check for attached vehicle
    if GetVehicleTowTruckAssistedVehicle(vehicle) ~= 0 then
        lib.notify({
            title = 'Tow Job',
            description = 'Detach the vehicle first',
            type = 'error'
        })
        return
    end

    -- Exit and delete
    TaskLeaveVehicle(ped, vehicle, 0)
    Wait(1500)

    if DoesEntityExist(vehicle) then
        DeleteEntity(vehicle)
    end

    CurrentVehicle = nil

    lib.notify({
        title = 'Tow Job',
        description = 'Vehicle returned',
        type = 'success'
    })
end

-- Duty status check
CreateThread(function()
    while true do
        Wait(60000) -- Every minute

        if IsOnDuty and CurrentShop then
            -- Could add idle check, fuel reminder, etc.
        end
    end
end)
