--[[
    dps-towjob Client Roadside
    Roadside repair services (tire change, jumpstart, etc.)
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Target for roadside services on vehicles
CreateThread(function()
    exports.ox_target:addGlobalVehicle({
        {
            name = 'tow_roadside',
            label = 'Roadside Services',
            icon = 'fa-solid fa-toolbox',
            distance = 3.0,
            canInteract = function(entity)
                if not IsOnDuty then return false end

                -- Check if vehicle needs service (damaged)
                local engineHealth = GetVehicleEngineHealth(entity)
                local bodyHealth = GetVehicleBodyHealth(entity)

                return engineHealth < 900 or bodyHealth < 900
            end,
            onSelect = function(data)
                OpenRoadsideMenu(data.entity)
            end
        }
    })
end)

-- Open roadside services menu
function OpenRoadsideMenu(vehicle)
    local options = {}

    local engineHealth = GetVehicleEngineHealth(vehicle)
    local bodyHealth = GetVehicleBodyHealth(vehicle)

    -- Check if vehicle needs towing instead
    if engineHealth < Config.DamageThresholds.engine or bodyHealth < Config.DamageThresholds.body then
        lib.notify({
            title = 'Roadside Service',
            description = 'Vehicle damage too severe - must be towed to shop',
            type = 'error'
        })
        return
    end

    for serviceId, service in pairs(Config.RoadsideServices) do
        local canPerform = true
        local reason = ''

        -- Check if item required
        if service.item then
            local hasItem = exports.ox_inventory:Search('count', service.item) > 0
            if not hasItem then
                canPerform = false
                reason = 'Missing: ' .. service.item
            end
        end

        table.insert(options, {
            title = service.label,
            description = canPerform and ('Price: ' .. TowJob.FormatMoney(service.price)) or reason,
            icon = GetServiceIcon(serviceId),
            disabled = not canPerform,
            onSelect = function()
                PerformRoadsideService(vehicle, serviceId, service)
            end
        })
    end

    -- Option to tow instead
    table.insert(options, {
        title = 'Tow to Shop',
        description = 'Attach and tow for repairs',
        icon = 'fa-solid fa-truck-pickup',
        onSelect = function()
            AttachVehicle(vehicle)
        end
    })

    lib.registerContext({
        id = 'roadside_menu',
        title = 'Roadside Services',
        options = options
    })

    lib.showContext('roadside_menu')
end

-- Get icon for service type
function GetServiceIcon(serviceId)
    local icons = {
        tire_change = 'fa-solid fa-tire',
        quick_patch = 'fa-solid fa-bandage',
        jumpstart = 'fa-solid fa-car-battery',
        fluid_topoff = 'fa-solid fa-oil-can'
    }
    return icons[serviceId] or 'fa-solid fa-wrench'
end

-- Perform roadside service
function PerformRoadsideService(vehicle, serviceId, service)
    local ped = PlayerPedId()

    -- Check for owner/permission
    -- For now, assume driver permission granted

    -- Remove item if required
    if service.item then
        TriggerServerEvent('dps-towjob:server:useItem', service.item)
    end

    -- Progress bar
    if lib.progressCircle({
        duration = service.time,
        label = service.label .. '...',
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
        -- Apply service effect
        ApplyServiceEffect(vehicle, serviceId)

        -- Bill the customer or add to job earnings
        if CurrentJob and CurrentJob.requesterSource then
            -- Bill via qs-billing
            TriggerServerEvent('dps-towjob:server:billCustomer', CurrentJob.requesterSource, service.price, service.label)
        end

        lib.notify({
            title = 'Service Complete',
            description = service.label .. ' - ' .. TowJob.FormatMoney(service.price),
            type = 'success'
        })
    else
        lib.notify({
            title = 'Service Cancelled',
            description = 'Roadside service aborted',
            type = 'error'
        })
    end
end

-- Apply effect based on service
function ApplyServiceEffect(vehicle, serviceId)
    if serviceId == 'tire_change' then
        -- Fix tires
        SetVehicleTyreFixed(vehicle, 0)
        SetVehicleTyreFixed(vehicle, 1)
        SetVehicleTyreFixed(vehicle, 2)
        SetVehicleTyreFixed(vehicle, 3)
        SetVehicleTyreFixed(vehicle, 4)
        SetVehicleTyreFixed(vehicle, 5)

    elseif serviceId == 'quick_patch' then
        -- Minor body repair
        local currentHealth = GetVehicleBodyHealth(vehicle)
        SetVehicleBodyHealth(vehicle, math.min(1000.0, currentHealth + 200))

    elseif serviceId == 'jumpstart' then
        -- Fix engine enough to drive
        local currentHealth = GetVehicleEngineHealth(vehicle)
        SetVehicleEngineHealth(vehicle, math.min(500.0, currentHealth + 300))
        SetVehicleUndriveable(vehicle, false)
        SetVehicleEngineOn(vehicle, true, true, false)

    elseif serviceId == 'fluid_topoff' then
        -- Top off oil (represented by slight engine health boost)
        local currentHealth = GetVehicleEngineHealth(vehicle)
        SetVehicleEngineHealth(vehicle, math.min(1000.0, currentHealth + 100))

        -- Also set fuel if using a fuel system
        -- SetVehicleFuelLevel(vehicle, GetVehicleFuelLevel(vehicle) + 10.0)
    end
end

-- Check vehicle damage level
function GetVehicleDamageLevel(vehicle)
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local bodyHealth = GetVehicleBodyHealth(vehicle)

    local engineDamage = 1000 - engineHealth
    local bodyDamage = 1000 - bodyHealth

    if engineDamage > Config.DamageThresholds.engine or bodyDamage > Config.DamageThresholds.body then
        return 'severe'
    elseif engineDamage > 200 or bodyDamage > 200 then
        return 'moderate'
    elseif engineDamage > 0 or bodyDamage > 0 then
        return 'minor'
    else
        return 'none'
    end
end

exports('GetVehicleDamageLevel', GetVehicleDamageLevel)
