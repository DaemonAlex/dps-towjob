--[[
    dps-towjob Server Payment
    Payment processing and society fund management
]]

-- Framework access goes through Bridge (qbx has no GetCoreObject on this box)
--
-- MONEY MODEL (H1): qb-management is NOT installed on this box, so we do NOT
-- mint society money. Instead the "shop fund" is a server-side DB ledger in
-- tow_shop_transactions (credits = 'tow_payment', debits = 'withdrawal'), and
-- driver earnings are tracked authoritatively in tow_driver_earnings. Drivers
-- are paid to their bank directly on collection. All amounts are computed
-- server-side (see server/queue.lua completeJob) and never read from a client.

-- Record the shop's cut in the server ledger (no external management resource).
function AddToShopFund(shopId, amount, reason)
    local shop = Config.ShopJobMapping[shopId]
    if not shop then
        TowJob.Debug('Warning: unknown shop for fund credit', shopId)
        return false
    end

    MySQL.insert.await([[
        INSERT INTO tow_shop_transactions (shop, amount, type, description)
        VALUES (?, ?, 'tow_payment', ?)
    ]], { shopId, amount, reason })

    TowJob.Debug('Shop fund ledger credit:', shopId, amount)
    return true
end

-- Record a driver withdrawal in the ledger. The uncollected balance is the
-- authority (checked in collectEarnings), so this just logs the debit.
function WithdrawFromShopFund(shopId, citizenid, amount)
    MySQL.insert.await([[
        INSERT INTO tow_shop_transactions (shop, amount, type, description, citizenid)
        VALUES (?, ?, 'withdrawal', 'Driver earnings withdrawal', ?)
    ]], { shopId or 'unknown', amount, citizenid })

    return true
end

-- Shop balance is derived from the ledger (credits minus withdrawals).
function GetShopBalance(shopId)
    local result = MySQL.scalar.await([[
        SELECT COALESCE(SUM(CASE WHEN type = 'withdrawal' THEN -amount ELSE amount END), 0)
        FROM tow_shop_transactions WHERE shop = ?
    ]], { shopId })
    return result or 0
end

exports('GetShopBalance', GetShopBalance)

-- Add driver earning
function AddDriverEarning(source, shopId, amount)
    local Player = Bridge.GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    -- Load or initialize driver earnings
    if not DriverEarnings[citizenid] then
        local result = MySQL.single.await([[
            SELECT * FROM tow_driver_earnings WHERE citizenid = ?
        ]], { citizenid })

        if result then
            DriverEarnings[citizenid] = {
                total = result.total_earned,
                uncollected = result.uncollected,
                shop = result.shop,
                jobs = result.total_jobs
            }
        else
            DriverEarnings[citizenid] = {
                total = 0,
                uncollected = 0,
                shop = shopId,
                jobs = 0
            }
        end
    end

    DriverEarnings[citizenid].total = DriverEarnings[citizenid].total + amount
    DriverEarnings[citizenid].uncollected = DriverEarnings[citizenid].uncollected + amount
    DriverEarnings[citizenid].jobs = DriverEarnings[citizenid].jobs + 1
    DriverEarnings[citizenid].shop = shopId

    -- Save to database
    MySQL.insert.await([[
        INSERT INTO tow_driver_earnings (citizenid, shop, total_earned, uncollected, total_jobs)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            shop = VALUES(shop),
            total_earned = VALUES(total_earned),
            uncollected = VALUES(uncollected),
            total_jobs = VALUES(total_jobs)
    ]], {
        citizenid,
        shopId,
        DriverEarnings[citizenid].total,
        DriverEarnings[citizenid].uncollected,
        DriverEarnings[citizenid].jobs
    })

    -- Add to shop society fund
    AddToShopFund(shopId, amount, 'Tow payment - ' .. citizenid)

    TowJob.Debug('Driver earning added:', citizenid, amount)
end

-- Process payment for a completed job.
-- C2: this is an INTERNAL function called only from completeJob (server/queue.lua).
-- It is intentionally NOT a RegisterNetEvent — a client cannot invoke it, and
-- job.payment was computed server-side in completeJob from server-tracked state.
function ProcessPayment(source, job)
    local Player = Bridge.GetPlayer(source)
    if not Player then return end

    local shopId = GetDriverShop(source)
    if not shopId then
        TowJob.Debug('Error: No shop for driver', source)
        return
    end

    local payment = job.payment
    if not payment or type(payment.driver) ~= 'number' then
        TowJob.Debug('ProcessPayment: missing server-computed payment', source)
        return
    end

    -- Add driver's cut to their earnings (tracked in the DB ledger)
    AddDriverEarning(source, shopId, payment.driver)

    -- Notify driver
    lib.notify(source, {
        title = 'Tow Completed',
        description = string.format(
            'Earned %s (%.1f miles)\nShop cut: %s',
            TowJob.FormatMoney(payment.driver),
            payment.distance,
            TowJob.FormatMoney(payment.shop)
        ),
        type = 'success',
        duration = 8000
    })
end

-- Driver collects earnings
RegisterNetEvent('dps-towjob:server:collectEarnings', function()
    local source = source

    -- Anti-spam (also protects the read-modify-write below)
    if CheckCooldown(source, 'collectEarnings') then return end

    local Player = Bridge.GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    -- Reload from DB if the cache was evicted (e.g. after a reconnect), so
    -- earned money is not stranded until the driver opens 'View Earnings' first.
    if not DriverEarnings[citizenid] then
        local result = MySQL.single.await('SELECT * FROM tow_driver_earnings WHERE citizenid = ?', { citizenid })
        if result then
            DriverEarnings[citizenid] = {
                total = result.total_earned, uncollected = result.uncollected,
                shop = result.shop, jobs = result.total_jobs
            }
        end
    end

    local earnings = DriverEarnings[citizenid]

    if not earnings or earnings.uncollected <= 0 then
        lib.notify(source, {
            title = 'Earnings',
            description = 'No uncollected earnings',
            type = 'error'
        })
        return
    end

    local amount = earnings.uncollected
    local shopId = earnings.shop

    -- Record the withdrawal in the ledger and pay the driver directly.
    local success, error = WithdrawFromShopFund(shopId, citizenid, amount)

    if success then
        Bridge.AddMoney(source, 'bank', amount)
        DriverEarnings[citizenid].uncollected = 0

        -- Update database
        MySQL.update.await([[
            UPDATE tow_driver_earnings SET uncollected = 0 WHERE citizenid = ?
        ]], { citizenid })

        lib.notify(source, {
            title = 'Earnings Collected',
            description = TowJob.FormatMoney(amount) .. ' deposited to bank',
            type = 'success'
        })

        TowJob.Debug('Driver collected earnings:', citizenid, amount)
    else
        lib.notify(source, {
            title = 'Error',
            description = error or 'Failed to collect earnings',
            type = 'error'
        })
    end
end)

-- Get driver earnings
lib.callback.register('dps-towjob:server:getEarnings', function(source)
    local Player = Bridge.GetPlayer(source)
    if not Player then return nil end

    local citizenid = Player.PlayerData.citizenid

    -- Load from cache or database
    if not DriverEarnings[citizenid] then
        local result = MySQL.single.await([[
            SELECT * FROM tow_driver_earnings WHERE citizenid = ?
        ]], { citizenid })

        if result then
            DriverEarnings[citizenid] = {
                total = result.total_earned,
                uncollected = result.uncollected,
                shop = result.shop,
                jobs = result.total_jobs
            }
        else
            return {
                total = 0,
                uncollected = 0,
                shop = nil,
                jobs = 0
            }
        end
    end

    return DriverEarnings[citizenid]
end)

-- Impound fee handling
RegisterNetEvent('dps-towjob:server:payImpoundFee', function(impoundId, vehiclePlate)
    local source = source
    local Player = Bridge.GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    local impound = Config.ImpoundLots[impoundId]
    if not impound then
        lib.notify(source, {
            title = 'Impound',
            description = 'Invalid impound lot',
            type = 'error'
        })
        return
    end

    -- H3: ownership check. The payer must own this plate. This prevents
    -- releasing (and then spawning to themselves) any vehicle sitting in impound.
    local vehicle = MySQL.single.await([[
        SELECT * FROM player_vehicles WHERE plate = ? AND state = 2
    ]], { vehiclePlate })

    if not vehicle then
        lib.notify(source, {
            title = 'Impound',
            description = 'Vehicle not found in impound',
            type = 'error'
        })
        return
    end

    if vehicle.citizenid ~= citizenid then
        TowJob.Debug('Impound release denied (not owner):', citizenid, 'plate', vehiclePlate)
        lib.notify(source, {
            title = 'Impound',
            description = 'This is not your vehicle',
            type = 'error'
        })
        return
    end

    -- M4: compute days stored from the impound record's TIMESTAMP using SQL
    -- date math (player_vehicles has no impound_date column, which previously
    -- made daysStored always 0). Falls back to 0 days if no tracking row.
    local impoundRecord = MySQL.single.await([[
        SELECT impound_lot, TIMESTAMPDIFF(DAY, impounded_at, NOW()) AS days_stored
        FROM tow_impound_vehicles
        WHERE plate = ? AND released_at IS NULL
    ]], { vehiclePlate })

    local daysStored = math.max(0, (impoundRecord and impoundRecord.days_stored) or 0)
    local fee = CalculateImpoundFee(impoundId, daysStored)

    -- Check funds via Bridge (works on qbx)
    local cash = Bridge.GetMoney(source, 'cash')
    local bank = Bridge.GetMoney(source, 'bank')
    if cash < fee and bank < fee then
        lib.notify(source, {
            title = 'Impound',
            description = 'Not enough money. Fee: ' .. TowJob.FormatMoney(fee),
            type = 'error'
        })
        return
    end

    -- Remove money
    local moneyType = cash >= fee and 'cash' or 'bank'
    Bridge.RemoveMoney(source, moneyType, fee)

    -- Log transaction
    MySQL.insert.await([[
        INSERT INTO tow_shop_transactions (shop, amount, type, description, citizenid)
        VALUES ('impound', ?, 'impound_fee', ?, ?)
    ]], { fee, 'Impound fee for ' .. vehiclePlate, citizenid })

    -- Release vehicle in player_vehicles and mark the tracking row released
    MySQL.update.await([[
        UPDATE player_vehicles SET state = 0 WHERE plate = ?
    ]], { vehiclePlate })

    MySQL.update.await([[
        UPDATE tow_impound_vehicles SET released_at = NOW(), released_by = ?
        WHERE plate = ? AND released_at IS NULL
    ]], { citizenid, vehiclePlate })

    lib.notify(source, {
        title = 'Impound',
        description = 'Vehicle released. Fee: ' .. TowJob.FormatMoney(fee),
        type = 'success'
    })

    -- Trigger vehicle spawn on client
    TriggerClientEvent('dps-towjob:client:spawnImpoundVehicle', source, vehicle, impound.spawn)
end)
