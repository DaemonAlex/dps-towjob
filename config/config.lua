--[[
    dps-towjob Configuration
    Base: qb-towjob (QBCore Team)
    Enhanced: @daemonAlex
]]

Config = {}

-- Debug mode
Config.Debug = false

-- Use ox_lib for UI
Config.UseOxLib = true

-- Job name
Config.JobName = 'tow'

-- Payment settings
Config.Payment = {
    baseRate = 100,         -- Base pay per tow
    perMile = 15,           -- Additional pay per mile
    shopCut = 0.15,         -- 15% to shop society
    driverCut = 0.85,       -- 85% to driver
    pveMultiplier = 0.8,    -- PVE tows pay 80% of normal
}

-- Max amount a driver may bill/charge a customer in one invoice (server clamp).
Config.MaxBillAmount = 5000

-- Max distance (metres) between driver and customer for a bill to be valid.
Config.MaxBillDistance = 20.0

-- Queue settings
Config.Queue = {
    maxSize = 50,           -- Max jobs in queue
    pveEnabled = true,      -- Enable NPC breakdown calls
    pveInterval = 300000,   -- 5 min between PVE spawns
    maxPveActive = 3,       -- Max PVE jobs at once
    priorityTypes = { 'police', 'ems' }, -- High priority callers
}

-- Tow mechanics
Config.Towing = {
    attachDistance = 5.0,   -- Distance to attach vehicle
    maxTowDistance = 10.0,  -- Max distance while towing
    speedLimit = 50.0,      -- Speed limit while towing (mph)
}

-- Roadside services (driver can perform)
Config.RoadsideServices = {
    ['tire_change'] = {
        label = 'Change Flat Tire',
        item = 'tyre_replacement',
        time = 10000,
        price = 50,
    },
    ['quick_patch'] = {
        label = 'Quick Patch',
        item = 'duct_tape',
        time = 5000,
        price = 25,
    },
    ['jumpstart'] = {
        label = 'Jumpstart Battery',
        item = nil,
        time = 8000,
        price = 35,
    },
    ['fluid_topoff'] = {
        label = 'Top Off Fluids',
        item = nil,
        time = 6000,
        price = 30,
    },
}

-- Damage thresholds (anything above = must tow)
Config.DamageThresholds = {
    engine = 300,   -- Engine damage threshold
    body = 400,     -- Body damage threshold
}

-- Blip settings
Config.Blips = {
    depot = {
        sprite = 68,
        color = 5,
        scale = 0.8,
        label = 'Tow Depot',
    },
    impound = {
        sprite = 477,
        color = 1,
        scale = 0.7,
        label = 'Impound Lot',
    },
    job = {
        sprite = 477,
        color = 3,
        scale = 0.8,
        label = 'Tow Request',
    },
}

-- Notification settings
Config.NotifyDuration = 5000
