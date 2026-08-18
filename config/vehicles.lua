--[[
    dps-towjob Vehicle Configuration
]]

Config.TowVehicles = {
    ['flatbed'] = {
        label = 'Flatbed',
        minGrade = 0,
        price = 0,
        capacity = 1,
        canTowBoats = false,
    },
    ['towtruck'] = {
        label = 'Tow Truck',
        minGrade = 0,
        price = 0,
        capacity = 1,
        canTowBoats = false,
    },
    ['towtruck2'] = {
        label = 'Tow Truck (Large)',
        minGrade = 2,
        price = 0,
        capacity = 1,
        canTowBoats = false,
    },
    ['slamtruck'] = {
        label = 'Slam Truck',
        minGrade = 3,
        price = 0,
        capacity = 1,
        canTowBoats = false,
    },
}

-- Vehicle classes that can be towed
Config.TowableClasses = {
    [0] = true,   -- Compacts
    [1] = true,   -- Sedans
    [2] = true,   -- SUVs
    [3] = true,   -- Coupes
    [4] = true,   -- Muscle
    [5] = true,   -- Sports Classics
    [6] = true,   -- Sports
    [7] = true,   -- Super
    [8] = false,  -- Motorcycles
    [9] = true,   -- Off-road
    [10] = true,  -- Industrial
    [11] = true,  -- Utility
    [12] = true,  -- Vans
    [13] = false, -- Cycles
    [14] = false, -- Boats
    [15] = false, -- Helicopters
    [16] = false, -- Planes
    [17] = true,  -- Service
    [18] = true,  -- Emergency
    [19] = true,  -- Military
    [20] = true,  -- Commercial
    [21] = false, -- Trains
}

-- Check if vehicle can be towed
function CanTowVehicle(vehicle)
    if not DoesEntityExist(vehicle) then return false end

    local class = GetVehicleClass(vehicle)
    return Config.TowableClasses[class] == true
end

-- Get tow vehicles available for grade
function GetAvailableTowVehicles(grade)
    local available = {}
    for model, data in pairs(Config.TowVehicles) do
        if grade >= data.minGrade then
            available[model] = data
        end
    end
    return available
end
