-- config/config.lua is plain Lua with no natives at load time.
Config = nil
dofile('config/config.lua')

T.test('Config.Requests carries the agreed numbers', function()
    local r = Config.Requests
    T.truthy(r, 'Config.Requests')
    T.eq(r.cooldownSec, 120)
    T.eq(r.offerTimeoutSec, 45)
    T.eq(r.noDriverGraceSec, 20)
    T.eq(r.maxWaitSec, 180)
    T.eq(r.repairTowFee, 200)
    T.eq(r.emergencyTowFee, 0)
    T.eq(r.vehicleRange, 10.0)
    T.eq(r.arriveRadius, 30.0)
    T.eq(r.driverSpeedMps, 18.0)
    T.truthy(r.emergencyJobTypes.leo)
    T.truthy(r.emergencyJobTypes.ems)
    T.eq(r.cityTow.name, 'City Tow')
    T.eq(r.cityTow.minEtaSec, 240)
    T.eq(r.cityTow.maxEtaSec, 480)
    T.eq(r.cityTow.hookSec, 25)
    T.eq(r.cityTow.speedMps, 12.0)
end)
