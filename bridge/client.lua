--[[
    dps-towjob Client Bridge
    Framework-agnostic client functions
]]

if not Bridge then Bridge = {} end

-- Cache
local PlayerData = nil

-- Get player data
function Bridge.GetPlayerData()
    if Bridge.IsQB() then
        local fw = Bridge.GetFramework()
        return fw.Functions.GetPlayerData()
    elseif Bridge.IsESX() then
        local fw = Bridge.GetFramework()
        return fw.GetPlayerData()
    end
    return nil
end

-- Get player job
function Bridge.GetPlayerJob()
    local data = Bridge.GetPlayerData()
    if not data then return nil end

    if Bridge.IsQB() then
        return data.job
    elseif Bridge.IsESX() then
        return data.job
    end
    return nil
end

-- Check if player has job
function Bridge.HasJob(jobName)
    local job = Bridge.GetPlayerJob()
    if not job then return false end

    return job.name == jobName
end

-- Check if player is on duty
function Bridge.IsOnDuty()
    local job = Bridge.GetPlayerJob()
    if not job then return false end

    if Bridge.IsQB() then
        return job.onduty == true
    elseif Bridge.IsESX() then
        -- ESX doesn't have native duty system, check metadata or always true
        return true
    end
    return false
end

-- Get player identifier
function Bridge.GetIdentifier()
    local data = Bridge.GetPlayerData()
    if not data then return nil end

    if Bridge.IsQB() then
        return data.citizenid
    elseif Bridge.IsESX() then
        return data.identifier
    end
    return nil
end

-- Get player name
function Bridge.GetPlayerName()
    local data = Bridge.GetPlayerData()
    if not data then return 'Unknown' end

    if Bridge.IsQB() then
        local info = data.charinfo
        return info.firstname .. ' ' .. info.lastname
    elseif Bridge.IsESX() then
        return data.firstName .. ' ' .. data.lastName
    end
    return 'Unknown'
end

-- Notify player
function Bridge.Notify(title, message, notifyType, duration)
    notifyType = notifyType or 'inform'
    duration = duration or 5000

    lib.notify({
        title = title,
        description = message,
        type = notifyType,
        duration = duration
    })
end

-- Show progress bar
function Bridge.Progress(data)
    return lib.progressCircle({
        duration = data.duration or 5000,
        label = data.label or 'Working...',
        position = data.position or 'bottom',
        useWhileDead = data.useWhileDead or false,
        canCancel = data.canCancel or true,
        disable = data.disable or {
            car = true,
            move = true,
            combat = true
        },
        anim = data.anim
    })
end

-- Input dialog
function Bridge.Input(title, inputs)
    return lib.inputDialog(title, inputs)
end

-- Alert dialog
function Bridge.Alert(header, content)
    return lib.alertDialog({
        header = header,
        content = content,
        centered = true
    })
end

-- Context menu
function Bridge.ContextMenu(id, title, options)
    lib.registerContext({
        id = id,
        title = title,
        options = options
    })
    lib.showContext(id)
end

-- Close context menu
function Bridge.CloseMenu()
    lib.hideContext()
end

-- Show text UI
function Bridge.ShowTextUI(text, options)
    lib.showTextUI(text, options)
end

-- Hide text UI
function Bridge.HideTextUI()
    lib.hideTextUI()
end

-- Add target to entity
function Bridge.AddTargetEntity(entity, options)
    if Bridge.Resources.target == 'ox_target' then
        exports.ox_target:addLocalEntity(entity, options)
    elseif Bridge.Resources.target == 'qb-target' then
        exports['qb-target']:AddTargetEntity(entity, {
            options = options,
            distance = options[1] and options[1].distance or 2.5
        })
    end
end

-- Remove target from entity
function Bridge.RemoveTargetEntity(entity, optionNames)
    if Bridge.Resources.target == 'ox_target' then
        exports.ox_target:removeLocalEntity(entity, optionNames)
    elseif Bridge.Resources.target == 'qb-target' then
        exports['qb-target']:RemoveTargetEntity(entity, optionNames)
    end
end

-- Add target zone
function Bridge.AddTargetZone(name, data)
    if Bridge.Resources.target == 'ox_target' then
        exports.ox_target:addBoxZone({
            name = name,
            coords = data.coords,
            size = data.size or vec3(2.0, 2.0, 2.0),
            rotation = data.heading or 0,
            debug = Config.Debug,
            options = data.options
        })
    elseif Bridge.Resources.target == 'qb-target' then
        exports['qb-target']:AddBoxZone(name, data.coords, data.size.x or 2.0, data.size.y or 2.0, {
            name = name,
            heading = data.heading or 0,
            debugPoly = Config.Debug,
            minZ = data.coords.z - 1.0,
            maxZ = data.coords.z + 2.0
        }, {
            options = data.options,
            distance = data.distance or 2.5
        })
    end
end

-- Remove target zone
function Bridge.RemoveTargetZone(name)
    if Bridge.Resources.target == 'ox_target' then
        exports.ox_target:removeZone(name)
    elseif Bridge.Resources.target == 'qb-target' then
        exports['qb-target']:RemoveZone(name)
    end
end

-- Check if player has item
function Bridge.HasItem(item, count)
    count = count or 1

    if Bridge.Resources.inventory == 'ox_inventory' then
        local itemCount = exports.ox_inventory:Search('count', item)
        return itemCount >= count
    elseif Bridge.Resources.inventory == 'qs-inventory' then
        local itemCount = exports['qs-inventory']:GetItemTotalAmount(item)
        return itemCount >= count
    elseif Bridge.Resources.inventory == 'qb-inventory' then
        local hasItem = exports['qb-inventory']:HasItem(item, count)
        return hasItem
    else
        -- Fallback to framework inventory
        if Bridge.IsQB() then
            local fw = Bridge.GetFramework()
            local hasItem = fw.Functions.HasItem(item, count)
            return hasItem
        end
    end

    return false
end

-- Framework event listeners
CreateThread(function()
    -- Wait for player to be logged in
    while not Bridge.GetPlayerData() do
        Wait(500)
    end

    PlayerData = Bridge.GetPlayerData()

    if Bridge.IsQB() then
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
            PlayerData = Bridge.GetPlayerData()
        end)

        RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
            if PlayerData then
                PlayerData.job = job
            end
        end)
    elseif Bridge.IsESX() then
        RegisterNetEvent('esx:playerLoaded', function(xPlayer)
            PlayerData = xPlayer
        end)

        RegisterNetEvent('esx:setJob', function(job)
            if PlayerData then
                PlayerData.job = job
            end
        end)
    end
end)
