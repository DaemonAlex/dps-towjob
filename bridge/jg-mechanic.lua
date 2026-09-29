--[[
    dps-towjob Bridge: jg-mechanic
    Integration with JG Scripts mechanic system

    jg-mechanic IS installed on this box. Every jg-mechanic:server:* handler
    below is still gated via JGActive() so nothing runs if it is ever removed,
    and every shop-floor net event requires the sender to hold the mechanic or
    the tow job and be on duty. Service tickets are matched on the plate inside
    the stored JSON, never with a LIKE over the whole row.
    The generic mechanic-count helpers only read job.onduty and are framework-safe.
]]

-- True only when jg-mechanic is actually running.
local function JGActive()
    return GetResourceState('jg-mechanic') == 'started'
end

-- Listen for jg-mechanic duty changes
RegisterNetEvent('jg-mechanic:server:toggle-duty', function()
    if not JGActive() then return end
    local source = source
    local job = Bridge.GetPlayerJob(source)

    if not job then return end

    -- Update shop employee status for mechanic jobs
    if IsMechanicJob(job.name) then
        local shopId = GetShopByJob(job.name)
        if shopId then
            UpdateShopEmployeeStatus(shopId, source, job.onduty)

            TowJob.Debug('Mechanic duty update:', Bridge.GetIdentifier(source), job.name, job.onduty)
        end
    end
end)

-- Track shop employee status
ShopEmployees = {}

function UpdateShopEmployeeStatus(shopId, source, onDuty)
    if not ShopEmployees[shopId] then
        ShopEmployees[shopId] = {}
    end

    if onDuty then
        ShopEmployees[shopId][source] = {
            citizenid = Bridge.GetIdentifier(source),
            clockedIn = os.time()
        }
    else
        ShopEmployees[shopId][source] = nil
    end
end

-- Get on-duty mechanic count for shop
function GetMechanicOnDutyCount(shopId)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.mechanicJob then return 0 end

    local count = 0
    local players = Bridge.GetPlayers()

    for _, src in ipairs(players) do
        local job = Bridge.GetPlayerJob(src)
        if job and job.name == shop.mechanicJob and job.onduty then
            count = count + 1
        end
    end

    return count
end

exports('GetMechanicOnDutyCount', GetMechanicOnDutyCount)

-- Check if shop has on-duty mechanics (alias for ShopHasEmployees)
function MechanicShopHasEmployees(shopId)
    return GetMechanicOnDutyCount(shopId) > 0
end

exports('MechanicShopHasEmployees', MechanicShopHasEmployees)

-- Notify all on-duty mechanics at a shop
function NotifyShopMechanics(shopId, title, description, notifyType)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.mechanicJob then return end

    local players = Bridge.GetPlayers()

    for _, src in ipairs(players) do
        local job = Bridge.GetPlayerJob(src)
        if job and job.name == shop.mechanicJob and job.onduty then
            lib.notify(src, {
                title = title,
                description = description,
                type = notifyType or 'inform',
                duration = 8000
            })
        end
    end
end

exports('NotifyShopMechanics', NotifyShopMechanics)

-- Vehicle dropoff notification
RegisterNetEvent('dps-towjob:server:vehicleDroppedAtShop', function(shopId, vehicleData)
    if not IsShopStaff(source) then return end
    if type(vehicleData) ~= 'table' then return end

    NotifyShopMechanics(shopId,
        'Vehicle Dropped Off',
        string.format('%s [%s] ready for service',
            TowLifecycle.sanitizeLabel(vehicleData.model, 30),
            TowLifecycle.sanitizeLabel(vehicleData.plate, 10)),
        'inform'
    )

    -- Create service ticket if jg-mechanic supports it
    -- This could integrate with jg-mechanic's ticket system if available
    TowJob.Debug('Vehicle dropped at shop:', shopId, vehicleData.plate)
end)

-- Get available shops with mechanics on duty
function GetActiveRepairShops()
    local active = {}

    for shopId, shop in pairs(Config.ShopJobMapping) do
        if shop.towShop and MechanicShopHasEmployees(shopId) then
            table.insert(active, {
                id = shopId,
                label = shop.label,
                mechanicCount = GetMechanicOnDutyCount(shopId),
                waitTime = ShopWaitTimes[shopId] or 0
            })
        end
    end

    return active
end

exports('GetActiveRepairShops', GetActiveRepairShops)

-- Hook for when mechanic starts/completes repair
-- This allows tow system to track service completion
RegisterNetEvent('jg-mechanic:server:repairStarted', function(vehiclePlate)
    if not JGActive() then return end
    if not IsShopStaff(source) then return end
    local plate = TowLifecycle.cleanPlate(vehiclePlate)
    if not plate then return end

    -- Matched on the plate stored inside the ticket's JSON, not with a LIKE
    -- over the whole row: a LIKE let one client's text match any ticket.
    MySQL.update.await([[
        UPDATE tow_service_tickets SET status = 'in_progress'
        WHERE REPLACE(UPPER(JSON_UNQUOTE(JSON_EXTRACT(vehicle_data, '$.plate'))), ' ', '') = ?
          AND status = 'awaiting_repair'
    ]], { plate })

    TowJob.Debug('Repair started for:', plate)
end)

RegisterNetEvent('jg-mechanic:server:repairCompleted', function(vehiclePlate, repairCost)
    if not JGActive() then return end
    local source = source
    if not IsShopStaff(source) then return end
    local plate = TowLifecycle.cleanPlate(vehiclePlate)
    if not plate then return end
    local citizenid = Bridge.GetIdentifier(source)
    local cost = math.max(0, math.floor(tonumber(repairCost) or 0))

    if citizenid then
        MySQL.update.await([[
            UPDATE tow_service_tickets
            SET status = 'completed', completed_at = NOW(), repaired_by = ?, repair_cost = ?
            WHERE REPLACE(UPPER(JSON_UNQUOTE(JSON_EXTRACT(vehicle_data, '$.plate'))), ' ', '') = ?
              AND status = 'in_progress'
        ]], { citizenid, cost, plate })
    end

    TowJob.Debug('Repair completed for:', plate)
end)

-- Callback to get shop info for UI
lib.callback.register('dps-towjob:server:getShopInfo', function(source, shopId)
    local shop = Config.ShopJobMapping[shopId]
    if not shop then return nil end

    return {
        id = shopId,
        label = shop.label,
        mechanicJob = shop.mechanicJob,
        towShop = shop.towShop,
        mechanicsOnDuty = GetMechanicOnDutyCount(shopId),
        waitTime = ShopWaitTimes[shopId] and (os.time() - ShopWaitTimes[shopId]) or 0
    }
end)
