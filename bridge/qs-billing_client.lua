--[[
    dps-towjob Bridge: qs-billing (Client)
    Client-side invoice creation UI
]]

RegisterNetEvent('dps-towjob:client:openInvoiceMenu', function(targetSource)
    local input = lib.inputDialog('Create Invoice', {
        { type = 'number', label = 'Amount ($)', required = true, min = 1 },
        { type = 'input', label = 'Description', placeholder = 'Tow service, roadside repair, etc.' }
    })

    if input then
        TriggerServerEvent('dps-towjob:server:billCustomer', targetSource, input[1], input[2] or 'Tow Service')
    end
end)
