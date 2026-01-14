--[[
    dps-towjob Server Bridge
    Framework-agnostic server functions
]]

if not Bridge then Bridge = {} end

-- Get player object
function Bridge.GetPlayer(source)
    if Bridge.IsQB() then
        local fw = Bridge.GetFramework()
        return fw.Functions.GetPlayer(source)
    elseif Bridge.IsESX() then
        local fw = Bridge.GetFramework()
        return fw.GetPlayerFromId(source)
    end
    return nil
end

-- Get player by identifier
function Bridge.GetPlayerByIdentifier(identifier)
    if Bridge.IsQB() then
        local fw = Bridge.GetFramework()
        return fw.Functions.GetPlayerByCitizenId(identifier)
    elseif Bridge.IsESX() then
        local fw = Bridge.GetFramework()
        return fw.GetPlayerFromIdentifier(identifier)
    end
    return nil
end

-- Get all players
function Bridge.GetPlayers()
    if Bridge.IsQB() then
        local fw = Bridge.GetFramework()
        return fw.Functions.GetPlayers()
    elseif Bridge.IsESX() then
        local fw = Bridge.GetFramework()
        return fw.GetPlayers()
    end
    return {}
end

-- Get player identifier
function Bridge.GetIdentifier(source)
    local player = Bridge.GetPlayer(source)
    if not player then return nil end

    if Bridge.IsQB() then
        return player.PlayerData.citizenid
    elseif Bridge.IsESX() then
        return player.identifier
    end
    return nil
end

-- Get player name
function Bridge.GetPlayerName(source)
    local player = Bridge.GetPlayer(source)
    if not player then return 'Unknown' end

    if Bridge.IsQB() then
        local info = player.PlayerData.charinfo
        return info.firstname .. ' ' .. info.lastname
    elseif Bridge.IsESX() then
        return player.getName()
    end
    return 'Unknown'
end

-- Get player job
function Bridge.GetPlayerJob(source)
    local player = Bridge.GetPlayer(source)
    if not player then return nil end

    if Bridge.IsQB() then
        return player.PlayerData.job
    elseif Bridge.IsESX() then
        return player.getJob()
    end
    return nil
end

-- Check if player has job
function Bridge.HasJob(source, jobName)
    local job = Bridge.GetPlayerJob(source)
    if not job then return false end

    return job.name == jobName
end

-- Check if player is on duty
function Bridge.IsOnDuty(source)
    local job = Bridge.GetPlayerJob(source)
    if not job then return false end

    if Bridge.IsQB() then
        return job.onduty == true
    elseif Bridge.IsESX() then
        -- ESX doesn't have native duty, return true or check custom metadata
        return true
    end
    return false
end

-- Set player duty
function Bridge.SetDuty(source, onDuty)
    if Bridge.IsQB() then
        local player = Bridge.GetPlayer(source)
        if player then
            player.Functions.SetJobDuty(onDuty)
        end
    elseif Bridge.IsESX() then
        -- ESX doesn't have native duty system
        -- Could emit custom event or set metadata
    end
end

-- Add money to player
function Bridge.AddMoney(source, account, amount)
    local player = Bridge.GetPlayer(source)
    if not player then return false end

    if Bridge.IsQB() then
        player.Functions.AddMoney(account, amount, 'dps-towjob')
        return true
    elseif Bridge.IsESX() then
        if account == 'cash' then
            player.addMoney(amount)
        else
            player.addAccountMoney(account, amount)
        end
        return true
    end
    return false
end

-- Remove money from player
function Bridge.RemoveMoney(source, account, amount)
    local player = Bridge.GetPlayer(source)
    if not player then return false end

    if Bridge.IsQB() then
        return player.Functions.RemoveMoney(account, amount, 'dps-towjob')
    elseif Bridge.IsESX() then
        if account == 'cash' then
            player.removeMoney(amount)
        else
            player.removeAccountMoney(account, amount)
        end
        return true
    end
    return false
end

-- Get player money
function Bridge.GetMoney(source, account)
    local player = Bridge.GetPlayer(source)
    if not player then return 0 end

    if Bridge.IsQB() then
        return player.PlayerData.money[account] or 0
    elseif Bridge.IsESX() then
        if account == 'cash' then
            return player.getMoney()
        else
            return player.getAccount(account).money
        end
    end
    return 0
end

-- Add item to player
function Bridge.AddItem(source, item, count)
    count = count or 1

    if Bridge.Resources.inventory == 'ox_inventory' then
        return exports.ox_inventory:AddItem(source, item, count)
    elseif Bridge.Resources.inventory == 'qs-inventory' then
        return exports['qs-inventory']:AddItem(source, item, count)
    elseif Bridge.Resources.inventory == 'qb-inventory' then
        return exports['qb-inventory']:AddItem(source, item, count)
    else
        -- Fallback to framework
        local player = Bridge.GetPlayer(source)
        if player then
            if Bridge.IsQB() then
                return player.Functions.AddItem(item, count)
            elseif Bridge.IsESX() then
                player.addInventoryItem(item, count)
                return true
            end
        end
    end
    return false
end

-- Remove item from player
function Bridge.RemoveItem(source, item, count)
    count = count or 1

    if Bridge.Resources.inventory == 'ox_inventory' then
        return exports.ox_inventory:RemoveItem(source, item, count)
    elseif Bridge.Resources.inventory == 'qs-inventory' then
        return exports['qs-inventory']:RemoveItem(source, item, count)
    elseif Bridge.Resources.inventory == 'qb-inventory' then
        return exports['qb-inventory']:RemoveItem(source, item, count)
    else
        local player = Bridge.GetPlayer(source)
        if player then
            if Bridge.IsQB() then
                return player.Functions.RemoveItem(item, count)
            elseif Bridge.IsESX() then
                player.removeInventoryItem(item, count)
                return true
            end
        end
    end
    return false
end

-- Check if player has item
function Bridge.HasItem(source, item, count)
    count = count or 1

    if Bridge.Resources.inventory == 'ox_inventory' then
        local items = exports.ox_inventory:GetInventoryItems(source)
        for _, v in pairs(items or {}) do
            if v.name == item then
                return v.count >= count
            end
        end
        return false
    elseif Bridge.Resources.inventory == 'qs-inventory' then
        local itemCount = exports['qs-inventory']:GetItemTotalAmount(source, item)
        return itemCount >= count
    elseif Bridge.Resources.inventory == 'qb-inventory' then
        return exports['qb-inventory']:HasItem(source, item, count)
    else
        local player = Bridge.GetPlayer(source)
        if player then
            if Bridge.IsQB() then
                return player.Functions.GetItemByName(item) ~= nil
            elseif Bridge.IsESX() then
                local playerItem = player.getInventoryItem(item)
                return playerItem and playerItem.count >= count
            end
        end
    end
    return false
end

-- Notify player
function Bridge.Notify(source, title, message, notifyType, duration)
    notifyType = notifyType or 'inform'
    duration = duration or 5000

    TriggerClientEvent('ox_lib:notify', source, {
        title = title,
        description = message,
        type = notifyType,
        duration = duration
    })
end

-- Society funds
Bridge.Society = {}

function Bridge.Society.GetBalance(society)
    if Bridge.Resources.management == 'qb-management' then
        local result = MySQL.scalar.await('SELECT amount FROM management_funds WHERE job_name = ?', { society })
        return result or 0
    elseif Bridge.Resources.management == 'esx_society' then
        local result = MySQL.scalar.await('SELECT money FROM addon_account_data WHERE account_name = ?', { 'society_' .. society })
        return result or 0
    end
    return 0
end

function Bridge.Society.AddMoney(society, amount)
    if Bridge.Resources.management == 'qb-management' then
        exports['qb-management']:AddMoney(society, amount)
        return true
    elseif Bridge.Resources.management == 'esx_society' then
        TriggerEvent('esx_addonaccount:getSharedAccount', 'society_' .. society, function(account)
            if account then
                account.addMoney(amount)
            end
        end)
        return true
    end
    return false
end

function Bridge.Society.RemoveMoney(society, amount)
    if Bridge.Resources.management == 'qb-management' then
        exports['qb-management']:RemoveMoney(society, amount)
        return true
    elseif Bridge.Resources.management == 'esx_society' then
        TriggerEvent('esx_addonaccount:getSharedAccount', 'society_' .. society, function(account)
            if account then
                account.removeMoney(amount)
            end
        end)
        return true
    end
    return false
end

-- Billing
function Bridge.CreateBill(source, target, amount, description, society)
    if Bridge.Resources.billing == 'qs-billing' then
        exports['qs-billing']:CreateBill({
            sender = source,
            target = target,
            amount = amount,
            description = description,
            society = society
        })
        return true
    elseif Bridge.Resources.billing == 'qb-billing' then
        TriggerEvent('qb-billing:server:createBill', source, target, amount, description, society)
        return true
    end
    return false
end

-- Dispatch integration
function Bridge.SendDispatch(data)
    if Bridge.Resources.dispatch == 'qs-dispatch' then
        TriggerEvent('qs-dispatch:server:CreateDispatch', {
            job = data.jobs or { 'tow' },
            coords = data.coords,
            message = data.message,
            gender = data.gender,
            displayCode = data.code or 'TOW',
            description = data.description,
            radius = data.radius or 0,
            recipientList = data.recipients,
            blip = data.blip or {
                sprite = 477,
                scale = 1.0,
                colour = 3,
                flashes = true,
                text = 'Tow Request',
                time = 5
            }
        })
        return true
    elseif Bridge.Resources.dispatch == 'ps-dispatch' then
        TriggerEvent('ps-dispatch:server:notify', {
            dispatchcodename = data.code or 'towrequest',
            dispatchCode = '10-TOW',
            firstStreet = data.street,
            gender = data.gender,
            model = data.model,
            plate = data.plate,
            coords = data.coords,
            jobs = data.jobs or { 'tow' }
        })
        return true
    end
    return false
end

-- Admin check
function Bridge.IsAdmin(source)
    if Bridge.IsQB() then
        local fw = Bridge.GetFramework()
        return fw.Functions.HasPermission(source, 'admin') or IsPlayerAceAllowed(source, 'command')
    elseif Bridge.IsESX() then
        local player = Bridge.GetPlayer(source)
        if player then
            local group = player.getGroup()
            return group == 'admin' or group == 'superadmin'
        end
    end
    return IsPlayerAceAllowed(source, 'command')
end
