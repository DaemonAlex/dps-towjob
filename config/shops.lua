--[[
    dps-towjob Shop Configuration
    Maps tow depots to mechanic shops
]]

-- Shop job mapping for jg-mechanic integration
Config.ShopJobMapping = {
    ['lscustoms_burton'] = {
        label = 'LS Customs Burton',
        mechanicJob = 'mechanic',
        towShop = true,
        societyName = 'mechanic',
        depot = vector4(-337.39, -133.38, 39.01, 249.0),
        vehicleSpawn = vector4(-331.58, -138.46, 38.68, 250.0),
        vehicleDropoff = vector3(-345.0, -130.0, 39.0),
        blip = true,
    },
    ['bennys_strawberry'] = {
        label = "Benny's Strawberry",
        mechanicJob = 'bennys',
        towShop = true,
        societyName = 'bennys',
        depot = vector4(-205.83, -1312.93, 31.29, 180.0),
        vehicleSpawn = vector4(-212.73, -1320.91, 30.89, 180.0),
        vehicleDropoff = vector3(-200.0, -1308.0, 31.0),
        blip = true,
    },
    ['lscustoms_lamesa'] = {
        label = 'LS Customs La Mesa',
        mechanicJob = 'mechanic2',
        towShop = true,
        societyName = 'mechanic2',
        depot = vector4(731.81, -1088.82, 22.17, 90.0),
        vehicleSpawn = vector4(724.66, -1082.83, 22.17, 90.0),
        vehicleDropoff = vector3(738.0, -1085.0, 22.0),
        blip = true,
    },
    ['beekers_paleto'] = {
        label = "Beeker's Paleto",
        mechanicJob = 'beeker',
        towShop = true,
        societyName = 'beeker',
        depot = vector4(110.99, 6626.38, 31.79, 225.0),
        vehicleSpawn = vector4(118.73, 6619.15, 31.85, 225.0),
        vehicleDropoff = vector3(105.0, 6630.0, 32.0),
        blip = true,
    },
    ['hayes_auto'] = {
        label = 'Hayes Auto',
        mechanicJob = 'mechanic3',
        towShop = true,
        societyName = 'mechanic3',
        depot = vector4(-1420.55, -450.29, 35.91, 32.0),
        vehicleSpawn = vector4(-1427.09, -443.24, 35.63, 32.0),
        vehicleDropoff = vector3(-1415.0, -455.0, 36.0),
        blip = true,
    },
    ['lscustoms_harmony'] = {
        label = 'LS Customs Harmony',
        mechanicJob = nil,  -- Self-service
        towShop = false,
        societyName = nil,
        depot = nil,
        blip = false,
    },
    ['lscustoms_lsia'] = {
        label = 'LS Customs LSIA',
        mechanicJob = nil,  -- Self-service
        towShop = false,
        societyName = nil,
        depot = nil,
        blip = false,
    },
}

-- Get shop by mechanic job name
function GetShopByJob(jobName)
    for shopId, shop in pairs(Config.ShopJobMapping) do
        if shop.mechanicJob == jobName then
            return shopId
        end
    end
    return nil
end

-- Check if job is a mechanic job
function IsMechanicJob(jobName)
    for _, shop in pairs(Config.ShopJobMapping) do
        if shop.mechanicJob == jobName then
            return true
        end
    end
    return false
end

-- Get shops with tow depots
function GetTowShops()
    local shops = {}
    for shopId, shop in pairs(Config.ShopJobMapping) do
        if shop.towShop then
            shops[shopId] = shop
        end
    end
    return shops
end
