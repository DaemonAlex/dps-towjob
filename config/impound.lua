--[[
    dps-towjob Impound Configuration
]]

Config.ImpoundLots = {
    ['city'] = {
        label = 'LSPD Impound',
        coords = vector3(409.0, -1623.0, 29.0),
        spawn = vector4(409.0, -1623.0, 29.0, 90.0),
        dropoff = vector3(401.0, -1630.0, 29.0),
        radius = 50.0,
        blip = true,
        fee = {
            base = 250,
            perDay = 100,
            towFee = 175,
            maxDays = 7,
        },
        coverage = { -- Areas this impound covers
            'DTVINE', 'DAVIS', 'RANCHO', 'STRAW', 'CHAMH',
            'BANNING', 'CYPRE', 'SANAND', 'TERMINA', 'AIRP',
            'BEACH', 'VESP', 'DELPE', 'MORN', 'ROCKF',
            'ALTA', 'HAlfia', 'BURTON', 'VESPBE',
        },
    },
    ['sandy'] = {
        label = 'Sandy Shores Impound',
        coords = vector3(1880.0, 3692.0, 33.0),
        spawn = vector4(1880.0, 3692.0, 33.0, 30.0),
        dropoff = vector3(1875.0, 3700.0, 33.0),
        radius = 40.0,
        blip = true,
        fee = {
            base = 150,
            perDay = 50,
            towFee = 150,
            maxDays = 14,
        },
        coverage = {
            'SANDY', 'HUMLAB', 'GRAPES', 'JAIL', 'ALAMO',
            'DESRT', 'LAGO', 'MTCHIL', 'MTGORDO', 'CANNY',
        },
    },
    ['paleto'] = {
        label = 'Paleto Bay Impound',
        coords = vector3(-211.0, 6252.0, 31.0),
        spawn = vector4(-211.0, 6252.0, 31.0, 315.0),
        dropoff = vector3(-205.0, 6258.0, 31.0),
        radius = 35.0,
        blip = true,
        fee = {
            base = 150,
            perDay = 50,
            towFee = 150,
            maxDays = 14,
        },
        coverage = {
            'PALETO', 'PROCOB', 'PALFOR', 'CMSW', 'BRADT',
        },
    },
}

-- Get nearest impound lot to coordinates
function GetNearestImpound(coords)
    local nearest = nil
    local nearestDist = math.huge

    for impoundId, impound in pairs(Config.ImpoundLots) do
        local dist = #(coords - impound.coords)
        if dist < nearestDist then
            nearest = impoundId
            nearestDist = dist
        end
    end

    return nearest, nearestDist
end

-- Get impound by zone
function GetImpoundByZone(zoneName)
    for impoundId, impound in pairs(Config.ImpoundLots) do
        for _, zone in ipairs(impound.coverage) do
            if zone == zoneName then
                return impoundId
            end
        end
    end
    -- Default to city if zone not found
    return 'city'
end

-- Calculate impound fee
function CalculateImpoundFee(impoundId, daysStored)
    local impound = Config.ImpoundLots[impoundId]
    if not impound then return 0 end

    daysStored = math.min(daysStored or 0, impound.fee.maxDays)
    return impound.fee.base + (impound.fee.perDay * daysStored) + impound.fee.towFee
end
