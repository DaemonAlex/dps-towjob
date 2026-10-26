-- The company's cut of a tow goes into the driver's own company account
-- through wasabi_banking's qb-management exports (Damon 2026-10-11).
Config = nil
dofile('config/config.lua')
dofile('shared/functions.lua')

local deposits = {}
local depositAnswer = true
local qbManagement = {
    AddMoney = function(_, account, amount, reason)
        deposits[#deposits + 1] = { account = account, amount = amount, reason = reason }
        return depositAnswer
    end,
}
local savedExports, savedBridge = exports, Bridge
exports = setmetatable({ ['qb-management'] = qbManagement }, { __call = function() end })
RegisterNetEvent = RegisterNetEvent or function() end
local savedLib = lib
lib = lib or { callback = { register = function() end } }
local jobs = {}
Bridge = { GetPlayerJob = function(src) return jobs[src] end }

dofile('server/payment.lua')

local function reset() deposits = {}; depositAnswer = true end

T.test('Camel Tow cut lands in the cameltow account', function()
    reset()
    jobs[1] = { name = 'cameltow', grade = { level = 0 } }
    T.truthy(PayCompanyCut(1, 18))
    T.eq(#deposits, 1)
    T.eq(deposits[1].account, 'cameltow')
    T.eq(deposits[1].amount, 18)
end)

T.test('a shop Tow Driver pays their own shop', function()
    reset()
    jobs[2] = { name = 'bayareacustoms', grade = { level = 1 } }
    T.truthy(PayCompanyCut(2, 22.7))
    T.eq(deposits[1].account, 'bayareacustoms')
    T.eq(deposits[1].amount, 22)
end)

T.test('no deposit for a non-tow job, zero, or bad amounts', function()
    reset()
    jobs[3] = { name = 'police', grade = { level = 4 } }
    T.falsy(PayCompanyCut(3, 50))
    jobs[4] = { name = 'cameltow', grade = { level = 0 } }
    T.falsy(PayCompanyCut(4, 0))
    T.falsy(PayCompanyCut(4, -5))
    T.falsy(PayCompanyCut(4, nil))
    T.eq(#deposits, 0)
end)

T.test('a refused deposit reports not paid', function()
    reset()
    depositAnswer = false
    jobs[5] = { name = 'lscustoms', grade = { level = 2 } }
    T.falsy(PayCompanyCut(5, 30))
end)

exports, Bridge, lib = savedExports, savedBridge, savedLib
