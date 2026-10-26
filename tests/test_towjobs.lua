-- Who takes tow calls: Camel Tow at every rank, the repair shops from their
-- Tow Driver rank (Damon 2026-10-11).
Config = nil
dofile('config/config.lua')
dofile('shared/functions.lua')

local function job(name, level)
    return { name = name, grade = { level = level } }
end

T.test('Config.TowJobs lists Camel Tow and the three repair shops', function()
    T.eq(Config.TowJobs.cameltow, 0)
    T.eq(Config.TowJobs.lscustoms, 1)
    T.eq(Config.TowJobs.bayareacustoms, 1)
    T.eq(Config.TowJobs.sandymechanic, 1)
    T.eq(Config.TowJobs.tow, nil, 'old City Tow job gets no calls')
end)

T.test('Camel Tow tows from Trainee Driver up', function()
    T.truthy(TowJob.CanTow(job('cameltow', 0)))
    T.truthy(TowJob.CanTow(job('cameltow', 5)))
end)

T.test('a shop Apprentice does not tow, Tow Driver and up do', function()
    T.falsy(TowJob.CanTow(job('lscustoms', 0)))
    T.truthy(TowJob.CanTow(job('lscustoms', 1)))
    T.truthy(TowJob.CanTow(job('bayareacustoms', 3)))
    T.truthy(TowJob.CanTow(job('sandymechanic', 5)))
end)

T.test('other jobs and bad input never tow', function()
    T.falsy(TowJob.CanTow(job('tow', 0)))
    T.falsy(TowJob.CanTow(job('police', 4)))
    T.falsy(TowJob.CanTow(nil))
    T.falsy(TowJob.CanTow({ name = 'lscustoms' }))
end)

T.test('a plain number grade works too', function()
    T.truthy(TowJob.CanTow({ name = 'lscustoms', grade = 2 }))
    T.falsy(TowJob.CanTow({ name = 'lscustoms', grade = 0 }))
end)

T.test('truck rank counts from the job tow rank', function()
    T.eq(TowJob.TowGrade(job('cameltow', 0)), 0)
    T.eq(TowJob.TowGrade(job('lscustoms', 1)), 0)
    T.eq(TowJob.TowGrade(job('lscustoms', 3)), 2)
    T.eq(TowJob.TowGrade(job('cameltow', 3)), 3)
    T.eq(TowJob.TowGrade(job('police', 3)), 0)
end)
