--[[
    dps-towjob client/offers.lua
    Shows a tow driver an offer and sends back their answer.
]]

local currentOffer = nil

local function offerTitle(offer)
    if offer.kind == 'impound' then return 'Impound tow' end
    if offer.kind == 'repair' then return 'Repair tow' end
    if offer.type == 'predatory' then return 'Illegal parking' end
    return 'Breakdown'
end

local function offerLine(offer)
    local vehicle = offer.vehicleModel or 'Vehicle'
    if offer.vehiclePlate then vehicle = vehicle .. ' [' .. offer.vehiclePlate .. ']' end
    return ('%s at %s'):format(vehicle, offer.zone or 'Unknown')
end

RegisterNetEvent('dps-towjob:client:jobOffered', function(offer)
    if type(offer) ~= 'table' or not offer.id then return end
    currentOffer = offer

    lib.notify({
        title = offerTitle(offer),
        description = ('%s. You have %d seconds to answer.'):format(offerLine(offer), offer.timeoutSec or 45),
        type = 'inform',
        duration = 10000,
        icon = 'truck-ramp-box',
    })

    lib.registerContext({
        id = 'tow_offer_menu',
        title = offerTitle(offer),
        options = {
            {
                title = 'Accept',
                description = offerLine(offer),
                icon = 'check',
                onSelect = function()
                    TriggerServerEvent('dps-towjob:server:acceptOffer', offer.id)
                end,
            },
            {
                title = 'Decline',
                description = 'Pass it to the next driver. No penalty.',
                icon = 'xmark',
                onSelect = function()
                    TriggerServerEvent('dps-towjob:server:declineOffer', offer.id)
                end,
            },
        },
    })
    lib.showContext('tow_offer_menu')
end)

RegisterNetEvent('dps-towjob:client:offerWithdrawn', function(jobId, reason)
    if not currentOffer or currentOffer.id ~= jobId then return end
    currentOffer = nil
    if lib.getOpenContextMenu() == 'tow_offer_menu' then lib.hideContext() end
    if reason == 'timeout' then
        lib.notify({ title = 'Tow Request', description = 'The request went to another driver', type = 'inform' })
    elseif reason == 'cancelled' then
        lib.notify({ title = 'Tow Request', description = 'The caller cancelled', type = 'inform' })
    end
end)

RegisterNetEvent('dps-towjob:client:jobAssigned', function()
    currentOffer = nil
end)

exports('GetCurrentOffer', function() return currentOffer end)
