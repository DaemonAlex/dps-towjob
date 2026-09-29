--[[
    dps-towjob client/arrival.lua
    Tells the server when the driver reaches the pickup. One ox_lib point,
    no loop.
]]

local arrivalPoint = nil

local function clearArrival()
    if arrivalPoint then
        arrivalPoint:remove()
        arrivalPoint = nil
    end
end

local function watchArrival(job)
    clearArrival()
    if type(job) ~= 'table' or not job.pickupCoords then return end
    local c = job.pickupCoords
    local jobId = job.id
    arrivalPoint = lib.points.new({
        coords = vec3(c.x, c.y, c.z),
        distance = Config.Requests.arriveRadius,
        onEnter = function()
            TriggerServerEvent('dps-towjob:server:arrivedOnScene', jobId)
            clearArrival()
        end,
    })
end

RegisterNetEvent('dps-towjob:client:jobAssigned', function(job)
    watchArrival(job)
end)

RegisterNetEvent('dps-towjob:client:jobStateChanged', function(job)
    if type(job) ~= 'table' then return end
    if job.state == TowJob.JobState.ON_SCENE or job.state == TowJob.JobState.TOWING then clearArrival() end
end)

RegisterNetEvent('dps-towjob:client:jobCompleted', clearArrival)
RegisterNetEvent('dps-towjob:client:jobCancelled', clearArrival)

-- The arrival point belongs to the character who took the job.
RegisterNetEvent('QBCore:Client:OnPlayerUnload', clearArrival)
