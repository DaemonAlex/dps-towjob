-- City work licences (dps-services) needed to tow (Damon 2026-10-11):
-- clock-in needs a driver licence, Commercial B (A counts) and the Tow add-on;
-- the Large tow truck needs Commercial A.
Config = nil
dofile('config/config.lua')
dofile('shared/functions.lua')

T.test('clock-in licences are DL + Commercial B + Tow', function()
    local need = Config.Licences.clockIn
    T.eq(TowJob.MissingLicence({ driver = true, cdl_b = true, tow = true }, need), nil)
    T.eq(TowJob.MissingLicence({ driver = true, cdl_a = true, tow = true }, need), nil, 'A counts as B')
    T.eq(TowJob.MissingLicence({ driver = true, cdl_b = true }, need), 'tow')
    T.eq(TowJob.MissingLicence({ cdl_b = true, tow = true }, need), 'driver')
    T.eq(TowJob.MissingLicence(nil, need), 'driver')
end)

T.test('the Large tow truck needs Commercial A', function()
    T.eq(Config.Licences.vehicles.towtruck2, 'cdl_a')
    T.falsy(TowJob.HasLicence({ cdl_b = true }, 'cdl_a'))
    T.truthy(TowJob.HasLicence({ cdl_a = true }, 'cdl_a'))
    T.eq(Config.Licences.vehicles.flatbed, nil)
end)
