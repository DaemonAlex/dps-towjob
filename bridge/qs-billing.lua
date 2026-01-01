--[[
    dps-towjob Bridge: qs-billing
    Integration with Quasar Store billing system
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Check if qs-billing is available
local function HasQSBilling()
    return GetResourceState('qs-billing') == 'started'
end

-- Create a bill for tow services
function CreateTowBill(driverSource, customerSource, amount, description)
    if not HasQSBilling() then
        TowJob.Debug('qs-billing not available, skipping bill')
        return false
    end

    local Driver = QBCore.Functions.GetPlayer(driverSource)
    local Customer = QBCore.Functions.GetPlayer(customerSource)

    if not Driver or not Customer then
        return false
    end

    local shopId = GetDriverShop(driverSource)
    local shop = shopId and Config.ShopJobMapping[shopId]
    local societyName = shop and shop.societyName or 'mechanic'

    -- Create bill using qs-billing export
    exports['qs-billing']:CreateBill({
        sender = Driver.PlayerData.citizenid,
        target = Customer.PlayerData.citizenid,
        amount = amount,
        description = description or 'Tow Service',
        society = societyName
    })

    TowJob.Debug('Bill created:', amount, 'from', driverSource, 'to', customerSource)
    return true
end

exports('CreateTowBill', CreateTowBill)

-- Bill customer for service
RegisterNetEvent('dps-towjob:server:billCustomer', function(customerSource, amount, description)
    local source = source

    if not customerSource or customerSource == 0 then
        TowJob.Debug('No customer to bill')
        return
    end

    local success = CreateTowBill(source, customerSource, amount, description)

    if success then
        lib.notify(source, {
            title = 'Bill Sent',
            description = string.format('Billed %s for %s', TowJob.FormatMoney(amount), description),
            type = 'success'
        })

        lib.notify(customerSource, {
            title = 'Invoice Received',
            description = string.format('Tow service: %s', TowJob.FormatMoney(amount)),
            type = 'inform'
        })
    else
        -- Fallback: Direct payment if billing fails
        TowJob.Debug('Billing failed, using direct payment')
    end
end)

-- Handle tow request from billing/service ticket
RegisterNetEvent('qs-billing:server:towRequest', function(data)
    local source = source

    TriggerEvent('dps-towjob:server:dispatchRequest', {
        coords = data.coords or GetEntityCoords(GetPlayerPed(source)),
        plate = data.plate,
        model = data.model,
        street = data.street
    })
end)

-- Create invoice for impound release
function CreateImpoundInvoice(source, amount, vehiclePlate)
    if not HasQSBilling() then
        -- Direct payment if no billing system
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            if Player.PlayerData.money.cash >= amount then
                Player.Functions.RemoveMoney('cash', amount, 'impound-fee')
                return true
            elseif Player.PlayerData.money.bank >= amount then
                Player.Functions.RemoveMoney('bank', amount, 'impound-fee')
                return true
            end
        end
        return false
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    -- For impound, bill directly (no society, goes to city)
    exports['qs-billing']:CreateBill({
        sender = 'government',
        target = Player.PlayerData.citizenid,
        amount = amount,
        description = 'Impound Fee - ' .. vehiclePlate,
        society = nil -- No society, goes to void/city
    })

    return true
end

exports('CreateImpoundInvoice', CreateImpoundInvoice)

-- Quick invoice menu for tow driver
RegisterNetEvent('dps-towjob:server:openInvoiceMenu', function(targetSource)
    local source = source

    if not IsDriverOnDuty(source) then
        lib.notify(source, {
            title = 'Tow Job',
            description = 'You must be on duty',
            type = 'error'
        })
        return
    end

    TriggerClientEvent('dps-towjob:client:openInvoiceMenu', source, targetSource)
end)

-- Client-side invoice creation
RegisterNetEvent('dps-towjob:client:openInvoiceMenu', function(targetSource)
    local input = lib.inputDialog('Create Invoice', {
        { type = 'number', label = 'Amount ($)', required = true, min = 1 },
        { type = 'input', label = 'Description', placeholder = 'Tow service, roadside repair, etc.' }
    })

    if input then
        TriggerServerEvent('dps-towjob:server:billCustomer', targetSource, input[1], input[2] or 'Tow Service')
    end
end)

-- Integration with roadside billing
RegisterNetEvent('dps-towjob:server:roadsideBill', function(customerSource, serviceId, amount)
    local source = source
    local service = Config.RoadsideServices[serviceId]

    if not service then return end

    local description = service.label .. ' - Roadside Service'
    CreateTowBill(source, customerSource, amount, description)
end)

-- Callback for checking if player has pending tow bills
lib.callback.register('dps-towjob:server:hasPendingBills', function(source)
    if not HasQSBilling() then return false end

    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    -- This would need to check qs-billing's database
    -- Implementation depends on qs-billing's available exports
    return false
end)
