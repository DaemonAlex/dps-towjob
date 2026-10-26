--[[
    dps-towjob Bridge: billing
    Invoices go through wasabi_billing (2026-10-12). qs-billing had no CreateBill
    export, so every bill sent through it failed without an error.
]]

local function HasWasabiBilling()
    return GetResourceState('wasabi_billing') == 'started'
end

-- Create a bill for tow services. False = no invoice made; the caller then takes
-- the money directly.
function CreateTowBill(driverSource, customerSource, amount, description)
    if not HasWasabiBilling() then
        TowJob.Debug('wasabi_billing not running, no invoice')
        return false
    end

    local customerCid = Bridge.GetIdentifier(customerSource)
    if not customerCid then
        return false
    end

    -- The bill is from the driver's own company (Camel Tow or their shop), not the
    -- depot they clocked in at; wasabi_billing takes the issuing company from the
    -- driver's job, which must be on its send list.
    local driver = Bridge.GetPlayer(driverSource)
    local driverJob = driver and driver.PlayerData.job
    local invoiceType = TowJob.CanTow(driverJob) and 'society' or 'personal'

    local reference = exports.wasabi_billing:CreateInvoice(driverSource, customerCid, amount,
        (description or 'Tow Service'):sub(1, 200), invoiceType, 'personal')
    if not reference then
        TowJob.Debug('wasabi_billing refused the invoice', driverSource, customerSource, amount)
        return false
    end

    TowJob.Debug('Invoice created:', reference, amount, 'from', driverSource, 'to', customerSource)
    return true
end

exports('CreateTowBill', CreateTowBill)

-- Bill customer for service
-- H4: gate on an on-duty tow driver, validate the target is a real, nearby,
-- online player, and clamp the amount to config. Sender/amount are never
-- trusted blindly. Works with or without qs-billing (direct-pay fallback).
RegisterNetEvent('dps-towjob:server:billCustomer', function(customerSource, amount, description)
    local source = source

    -- Sender must be an on-duty tow driver
    if not IsDriverOnDuty(source) or not IsTowDriver(source) then
        TowJob.Debug('billCustomer rejected: not an on-duty tow driver', source)
        return
    end

    -- Validate amount and clamp to config
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        TowJob.Debug('billCustomer rejected: bad amount', source, tostring(amount))
        return
    end
    amount = math.min(math.floor(amount), Config.MaxBillAmount or 5000)

    -- Target must be a real, connected player
    customerSource = tonumber(customerSource)
    if not customerSource or customerSource == 0 then
        TowJob.Debug('No customer to bill')
        return
    end
    if not Bridge.GetPlayer(customerSource) then
        TowJob.Debug('billCustomer rejected: target not online', customerSource)
        return
    end

    -- Target must be physically near the driver (server-side ped distance)
    local driverPed = GetPlayerPed(source)
    local customerPed = GetPlayerPed(customerSource)
    if not driverPed or driverPed == 0 or not customerPed or customerPed == 0 then
        return
    end
    local dist = #(GetEntityCoords(driverPed) - GetEntityCoords(customerPed))
    if dist > (Config.MaxBillDistance or 20.0) then
        TowJob.Debug('billCustomer rejected: target too far', source, customerSource, dist)
        lib.notify(source, { title = 'Bill', description = 'Customer is too far away', type = 'error' })
        return
    end

    local success = CreateTowBill(source, customerSource, amount, description)

    if success then
        lib.notify(source, {
            title = 'Bill Sent',
            description = string.format('Billed %s for %s', TowJob.FormatMoney(amount), description or 'service'),
            type = 'success'
        })

        lib.notify(customerSource, {
            title = 'Invoice Received',
            description = string.format('Tow service: %s', TowJob.FormatMoney(amount)),
            type = 'inform'
        })
    else
        -- Fallback: no billing resource — settle directly. Charge the customer
        -- (cash then bank) and pay the driver. Amount already clamped above.
        local custCash = Bridge.GetMoney(customerSource, 'cash')
        local custBank = Bridge.GetMoney(customerSource, 'bank')
        local payType = custCash >= amount and 'cash' or (custBank >= amount and 'bank' or nil)

        if not payType then
            lib.notify(source, { title = 'Bill', description = 'Customer cannot afford this', type = 'error' })
            lib.notify(customerSource, { title = 'Bill', description = 'You cannot afford the tow charge', type = 'error' })
            return
        end

        Bridge.RemoveMoney(customerSource, payType, amount)
        Bridge.AddMoney(source, 'bank', amount)

        lib.notify(source, {
            title = 'Payment Received',
            description = string.format('%s for %s', TowJob.FormatMoney(amount), description or 'service'),
            type = 'success'
        })
        lib.notify(customerSource, {
            title = 'Charged',
            description = string.format('Tow service: %s', TowJob.FormatMoney(amount)),
            type = 'inform'
        })
        TowJob.Debug('Direct-pay fallback settled:', source, customerSource, amount)
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

-- Impound release fee: taken directly (cash first, then bank). The owner pays it
-- themselves, and a player cannot invoice themselves in wasabi_billing; the fee
-- goes to the city, not a company.
function CreateImpoundInvoice(source, amount, vehiclePlate)
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

    -- Same trust boundary as billCustomer: only an on-duty driver, a clamped
    -- amount (prefer the configured service price), and a nearby target.
    if not IsDriverOnDuty(source) or not IsTowDriver(source) then return end
    amount = tonumber(service.price or amount)
    if not amount or amount <= 0 then return end
    amount = math.min(math.floor(amount), Config.MaxBillAmount or 5000)
    local target = tonumber(customerSource)
    if not target or not GetPlayerName(target) then return end
    local dPed, cPed = GetPlayerPed(source), GetPlayerPed(target)
    if dPed == 0 or cPed == 0 then return end
    if #(GetEntityCoords(dPed) - GetEntityCoords(cPed)) > (Config.MaxBillDistance or 20.0) then return end

    local description = service.label .. ' - Roadside Service'
    CreateTowBill(source, target, amount, description)
end)

-- Callback for checking if player has pending tow bills
lib.callback.register('dps-towjob:server:hasPendingBills', function(source)
    if not HasWasabiBilling() then return false end

    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return false end

    -- Any unpaid or overdue tow/roadside invoice addressed to this character
    for _, inv in ipairs(exports.wasabi_billing:GetInvoicesByIdentifier(citizenid) or {}) do
        if inv.receiver_identifier == citizenid and (inv.status == 'unpaid' or inv.status == 'overdue')
            and type(inv.reason) == 'string' and (inv.reason:find('Tow', 1, true) or inv.reason:find('Roadside', 1, true)) then
            return true
        end
    end
    return false
end)

-- Server console only: which billing exports exist (both billing scripts are escrowed,
-- so this is the only way to know). Calls each with no arguments inside pcall; a missing
-- export fails with "No such export" before anything runs.
RegisterCommand('towbillcheck', function(src)
    if src ~= 0 then return end
    for _, pair in ipairs({ { 'qs-billing', 'CreateBill' }, { 'qs-billing', 'CreateBillingForIdentifier' }, { 'wasabi_billing', 'CreateInvoice' } }) do
        local res, name = pair[1], pair[2]
        local ok, err = pcall(function() return exports[res][name]() end)
        local missing = (not ok) and tostring(err):find('No such export', 1, true) ~= nil
        print(('[dps-towjob] towbillcheck %s %s: %s'):format(res, name,
            missing and 'MISSING' or ('present (' .. (ok and 'ran' or ('errored: ' .. tostring(err):sub(1, 120))) .. ')')))
    end
end, true)
