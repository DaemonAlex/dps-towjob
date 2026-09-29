dofile('shared/lifecycle.lua')
local L = TowLifecycle

local CFG = {
    noDriverGraceSec = 20, maxWaitSec = 180,
    repairTowFee = 200, emergencyTowFee = 0,
    emergencyJobTypes = { leo = true, ems = true },
}

local function queueOf(...)
    local q = {}
    for _, j in ipairs({ ... }) do q[#q + 1] = j end
    return q
end

T.test('statusFor maps every job state', function()
    T.eq(L.statusFor('queued'), 'queued')
    T.eq(L.statusFor('assigned'), 'accepted')
    T.eq(L.statusFor('en_route'), 'accepted')
    T.eq(L.statusFor('on_scene'), 'arrived')
    T.eq(L.statusFor('towing'), 'hooked')
    T.eq(L.statusFor('completed'), 'delivered')
    T.eq(L.statusFor('cancelled'), 'cancelled')
    T.eq(L.statusFor('nonsense'), 'queued')
end)

T.test('isOpenState is true only while a tow is in progress', function()
    T.truthy(L.isOpenState('queued'))
    T.truthy(L.isOpenState('en_route'))
    T.truthy(L.isOpenState('towing'))
    T.falsy(L.isOpenState('completed'))
    T.falsy(L.isOpenState('cancelled'))
    T.falsy(L.isOpenState(nil))
end)

T.test('validKind accepts repair and impound only', function()
    T.truthy(L.validKind('repair'))
    T.truthy(L.validKind('impound'))
    T.falsy(L.validKind('taxi'))
    T.falsy(L.validKind(nil))
    T.falsy(L.validKind(7))
end)

T.test('sanitizeLabel strips control characters and markup', function()
    T.eq(L.sanitizeLabel('  Zancudo Ave, Sandy Shores  ', 60), 'Zancudo Ave, Sandy Shores')
    T.eq(L.sanitizeLabel('<b>Bad</b>\n', 60), 'bBad/b')
    T.eq(L.sanitizeLabel('', 60), 'Unknown')
    T.eq(L.sanitizeLabel(nil, 60), 'Unknown')
    T.eq(L.sanitizeLabel(42, 60), 'Unknown')
    T.eq(#L.sanitizeLabel(string.rep('a', 200), 60), 60)
end)

T.test('findInQueue and removeFromQueue', function()
    local a, b = { id = 'A' }, { id = 'B' }
    local q = queueOf(a, b)
    local job, index = L.findInQueue(q, 'B')
    T.eq(job, b); T.eq(index, 2)
    T.eq(L.findInQueue(q, 'Z'), nil)
    T.eq(L.removeFromQueue(q, 'A'), a)
    T.eq(#q, 1)
    T.eq(L.removeFromQueue(q, 'A'), nil)
    T.eq(#q, 1)
end)

T.test('queuePosition counts from one', function()
    local q = queueOf({ id = 'A' }, { id = 'B' }, { id = 'C' })
    T.eq(L.queuePosition(q, 'A'), 1)
    T.eq(L.queuePosition(q, 'C'), 3)
    T.eq(L.queuePosition(q, 'Z'), nil)
    T.eq(L.queuePosition(nil, 'A'), nil)
end)

T.test('insertByPriority puts high priority first and keeps age order inside a band', function()
    local q = {}
    L.insertByPriority(q, { id = 'N1', priority = 2, createdAt = 10 })
    L.insertByPriority(q, { id = 'N2', priority = 2, createdAt = 20 })
    L.insertByPriority(q, { id = 'H1', priority = 3, createdAt = 30 })
    L.insertByPriority(q, { id = 'L1', priority = 1, createdAt = 5 })
    T.eq(q[1].id, 'H1'); T.eq(q[2].id, 'N1'); T.eq(q[3].id, 'N2'); T.eq(q[4].id, 'L1')
    -- a requeued job goes back by its original age, ahead of newer jobs in its band
    L.insertByPriority(q, { id = 'N0', priority = 2, createdAt = 1 })
    T.eq(q[2].id, 'N0')
end)

T.test('etaSeconds clamps and rejects bad input', function()
    T.eq(L.etaSeconds(1800, 18, 30, 3600), 100)
    T.eq(L.etaSeconds(10, 18, 30, 3600), 30)
    T.eq(L.etaSeconds(1000000, 18, 30, 3600), 3600)
    T.eq(L.etaSeconds(500, 12, 240, 480), 240)
    T.eq(L.etaSeconds(9000, 12, 240, 480), 480)
    T.eq(L.etaSeconds(nil, 18), nil)
    T.eq(L.etaSeconds(100, 0), nil)
    T.eq(L.etaSeconds(-5, 18), nil)
end)

T.test('offerExpired', function()
    T.falsy(L.offerExpired(100, 120, 45))
    T.truthy(L.offerExpired(100, 145, 45))
    T.truthy(L.offerExpired(100, 500, 45))
    T.truthy(L.offerExpired(nil, 500, 45))
end)

T.test('nextDriver skips drivers who declined', function()
    local drivers = { { source = 1, citizenid = 'AAA' }, { source = 2, citizenid = 'BBB' } }
    T.eq(L.nextDriver(drivers, { declined = {} }).citizenid, 'AAA')
    T.eq(L.nextDriver(drivers, { declined = { AAA = true } }).citizenid, 'BBB')
    T.eq(L.nextDriver(drivers, { declined = { AAA = true, BBB = true } }), nil)
    T.eq(L.nextDriver({}, { declined = {} }), nil)
    T.eq(L.nextDriver(drivers, {}).citizenid, 'AAA')
    T.eq(L.eligibleCount(drivers, { declined = { AAA = true } }), 1)
    T.eq(L.eligibleCount(drivers, {}), 2)
end)

T.test('shouldUseCityTow: no driver, after the grace time', function()
    local job = { kind = 'repair', state = 'queued', createdAt = 100 }
    T.falsy(L.shouldUseCityTow(job, 0, 110, CFG))
    T.truthy(L.shouldUseCityTow(job, 0, 120, CFG))
end)

T.test('shouldUseCityTow: drivers on duty, after the long wait', function()
    local job = { kind = 'repair', state = 'queued', createdAt = 100 }
    T.falsy(L.shouldUseCityTow(job, 2, 200, CFG))
    T.truthy(L.shouldUseCityTow(job, 2, 280, CFG))
end)

T.test('shouldUseCityTow: an offered job waits for the offer unless the long wait is over', function()
    local job = { kind = 'repair', state = 'queued', createdAt = 100, offeredTo = 7 }
    T.falsy(L.shouldUseCityTow(job, 0, 130, CFG))
    T.truthy(L.shouldUseCityTow(job, 0, 280, CFG))
end)

T.test('shouldUseCityTow: never for AI calls, taken jobs or jobs already with City Tow', function()
    T.falsy(L.shouldUseCityTow({ state = 'queued', createdAt = 0 }, 0, 999, CFG))
    T.falsy(L.shouldUseCityTow({ kind = 'repair', state = 'en_route', createdAt = 0 }, 0, 999, CFG))
    T.falsy(L.shouldUseCityTow({ kind = 'repair', state = 'queued', createdAt = 0, cityTow = true }, 0, 999, CFG))
    T.falsy(L.shouldUseCityTow(nil, 0, 999, CFG))
end)

T.test('canRequest refuses a second open request', function()
    local ok, reason = L.canRequest('TOW1', nil, 1000, 120)
    T.falsy(ok); T.eq(reason, 'open_request')
end)

T.test('canRequest enforces the cooldown', function()
    local ok, reason = L.canRequest(nil, 950, 1000, 120)
    T.falsy(ok); T.eq(reason, 'cooldown')
    T.truthy(L.canRequest(nil, 880, 1000, 120))
    T.truthy(L.canRequest(nil, nil, 1000, 120))
end)

T.test('canImpound needs an emergency job that is on duty', function()
    T.truthy(L.canImpound({ name = 'police', type = 'leo', onduty = true }, CFG))
    T.truthy(L.canImpound({ name = 'lsfd', type = 'ems', onduty = true }, CFG))
    T.falsy(L.canImpound({ name = 'police', type = 'leo', onduty = false }, CFG))
    T.falsy(L.canImpound({ name = 'tow', type = 'none', onduty = true }, CFG))
    T.falsy(L.canImpound(nil, CFG))
end)

T.test('jobTypeFor and feeFor', function()
    T.eq(L.jobTypeFor('impound', 'leo'), 'police')
    T.eq(L.jobTypeFor('impound', 'ems'), 'ems')
    T.eq(L.jobTypeFor('repair', 'leo'), 'customer')
    T.eq(L.jobTypeFor('repair', nil), 'customer')
    T.eq(L.feeFor('repair', CFG), 200)
    T.eq(L.feeFor('impound', CFG), 0)
end)

T.test('hookDecision', function()
    T.eq(L.hookDecision(false, false, nil, 30), 'missing')
    T.eq(L.hookDecision(true, false, 5, 30), 'missing')
    T.eq(L.hookDecision(true, true, 5, 30), 'delete')
    T.eq(L.hookDecision(true, true, 30, 30), 'delete')
    T.eq(L.hookDecision(true, true, 31, 30), 'moved')
end)

T.test('publicView: queued shows the place in line and hides the ETA', function()
    local job = { id = 'B', kind = 'repair', state = 'queued', zone = 'Zancudo Ave', fee = 200, createdAt = 50 }
    local view = L.publicView(job, queueOf({ id = 'A' }, job), 100)
    T.eq(view.status, 'queued'); T.eq(view.position, 2); T.eq(view.etaSeconds, nil)
    T.eq(view.location, 'Zancudo Ave'); T.eq(view.fee, 200); T.eq(view.cityTow, false)
end)

T.test('publicView: accepted shows the driver and the time left', function()
    local job = { id = 'B', kind = 'repair', state = 'en_route', driverName = 'Ana Ruiz', etaAt = 160 }
    local view = L.publicView(job, {}, 100)
    T.eq(view.status, 'accepted'); T.eq(view.driverName, 'Ana Ruiz'); T.eq(view.etaSeconds, 60)
    T.eq(view.position, nil)
    T.eq(L.publicView(job, {}, 500).etaSeconds, 0)
end)

T.test('publicView keeps status after requeue', function()
    local job = { id = 'B', kind = 'repair', state = 'queued', driverName = 'Ana Ruiz', etaAt = 160 }
    local view = L.publicView(job, queueOf(job), 100)
    T.eq(view.status, 'queued'); T.eq(view.position, 1); T.eq(view.etaSeconds, nil)
end)

T.test('publicView carries no server ids or coordinates', function()
    local job = { id = 'B', kind = 'repair', state = 'queued', requesterSource = 4, requesterId = 'CID',
                  pickupCoords = { x = 1, y = 2, z = 3 }, assignedTo = 9, netId = 55 }
    local view = L.publicView(job, queueOf(job), 100)
    T.eq(view.requesterSource, nil); T.eq(view.requesterId, nil)
    T.eq(view.pickupCoords, nil); T.eq(view.assignedTo, nil); T.eq(view.netId, nil)
end)
