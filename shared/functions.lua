--[[
    dps-towjob Shared Functions
]]

TowJob = {}

-- Debug print
function TowJob.Debug(...)
    if Config.Debug then
        print('[dps-towjob]', ...)
    end
end

-- Format money
function TowJob.FormatMoney(amount)
    return '$' .. string.format('%0.2f', amount)
end

-- Calculate distance in miles
function TowJob.CalculateDistance(from, to)
    local dist = #(vector3(from.x, from.y, from.z) - vector3(to.x, to.y, to.z))
    -- Convert meters to miles (1 mile = 1609.34 meters)
    return dist / 1609.34
end

-- Calculate tow payment
function TowJob.CalculatePayment(distance, isPve)
    local base = Config.Payment.baseRate
    local perMile = Config.Payment.perMile * distance
    local total = base + perMile

    if isPve then
        total = total * Config.Payment.pveMultiplier
    end

    return math.floor(total)
end

-- Split payment between shop and driver
function TowJob.SplitPayment(total)
    local shopCut = math.floor(total * Config.Payment.shopCut)
    local driverCut = total - shopCut
    return driverCut, shopCut
end

-- Get zone name from coords
function TowJob.GetZoneName(coords)
    return GetNameOfZone(coords.x, coords.y, coords.z)
end

-- Get street name from coords
function TowJob.GetStreetName(coords)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local crossing = GetStreetNameFromHashKey(crossingHash)

    if crossing and crossing ~= '' then
        return street .. ' & ' .. crossing
    end
    return street
end

-- Generate unique ID
function TowJob.GenerateId()
    return 'TOW' .. os.time() .. math.random(1000, 9999)
end

-- Job types
TowJob.JobTypes = {
    PVE = 'pve',
    CUSTOMER = 'customer',
    POLICE = 'police',
    EMS = 'ems',
}

-- Job priorities
TowJob.Priority = {
    LOW = 1,      -- PVE
    NORMAL = 2,   -- Customer
    HIGH = 3,     -- Police/EMS
}

-- Get priority for job type
function TowJob.GetPriority(jobType)
    if jobType == TowJob.JobTypes.POLICE or jobType == TowJob.JobTypes.EMS then
        return TowJob.Priority.HIGH
    elseif jobType == TowJob.JobTypes.PVE then
        return TowJob.Priority.LOW
    else
        return TowJob.Priority.NORMAL
    end
end

-- Driver states
TowJob.DriverState = {
    OFF_DUTY = 'off_duty',
    AVAILABLE = 'available',
    BUSY = 'busy',
}

-- Job states
TowJob.JobState = {
    QUEUED = 'queued',
    ASSIGNED = 'assigned',
    EN_ROUTE = 'en_route',
    ON_SCENE = 'on_scene',
    TOWING = 'towing',
    COMPLETED = 'completed',
    CANCELLED = 'cancelled',
}

-- Destination types
TowJob.DestinationType = {
    IMPOUND = 'impound',
    SHOP = 'shop',
    CUSTOM = 'custom',
}

return TowJob
