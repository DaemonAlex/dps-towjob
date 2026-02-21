--[[
    dps-towjob Bridge: qs-billing
    Integration with Quasar Store billing system
]]

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

    local driverCid = Bridge.GetIdentifier(driverSource)
    local customerCid = Bridge.GetIdentifier(customerSource)

    if not driverCid or not customerCid then
        return false
    end

    local shopId = GetDriverShop(driverSource)
    local shop = shopId and Config.ShopJobMapping[shopId]
    local societyName = shop and shop.societyName or 'mechanic'

    -- Create bill using qs-billing export
    exports['qs-billing']:CreateBill({
        sender = driverCid,
        target = customerCid,
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
        local cash = Bridge.GetMoney(source, 'cash')
        if cash >= amount then
            Bridge.RemoveMoney(source, 'cash', amount)
            return true
        end
        local bank = Bridge.GetMoney(source, 'bank')
        if bank >= amount then
            Bridge.RemoveMoney(source, 'bank', amount)
            return true
        end
        return false
    end

    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return false end

    -- For impound, bill directly (no society, goes to city)
    exports['qs-billing']:CreateBill({
        sender = 'government',
        target = citizenid,
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

-- Client-side invoice UI is in bridge/qs-billing_client.lua

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

    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return false end

    -- This would need to check qs-billing's database
    -- Implementation depends on qs-billing's available exports
    return false
end)
