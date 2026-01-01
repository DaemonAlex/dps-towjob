--[[
    dps-towjob Server Payment
    Payment processing and society fund management
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Get management export
local function GetManagement()
    return exports['qb-management']
end

-- Add to shop fund
function AddToShopFund(shopId, amount, reason)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.societyName then
        TowJob.Debug('Warning: No society for shop', shopId)
        return false
    end

    local Management = GetManagement()
    Management:AddMoney(shop.societyName, amount)

    -- Log transaction
    MySQL.insert.await([[
        INSERT INTO tow_shop_transactions (shop, amount, type, description)
        VALUES (?, ?, 'tow_payment', ?)
    ]], { shopId, amount, reason })

    TowJob.Debug('Added to shop fund:', shopId, amount)
    return true
end

-- Withdraw from shop fund
function WithdrawFromShopFund(shopId, citizenid, amount)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.societyName then
        return false, 'No society fund'
    end

    local Management = GetManagement()
    local balance = Management:GetAccount(shop.societyName)

    if balance < amount then
        return false, 'Insufficient funds'
    end

    Management:RemoveMoney(shop.societyName, amount)

    -- Log withdrawal
    MySQL.insert.await([[
        INSERT INTO tow_shop_transactions (shop, amount, type, description, citizenid)
        VALUES (?, ?, 'withdrawal', 'Driver earnings withdrawal', ?)
    ]], { shopId, amount, citizenid })

    return true
end

-- Get shop balance
function GetShopBalance(shopId)
    local shop = Config.ShopJobMapping[shopId]
    if not shop or not shop.societyName then
        return 0
    end

    local Management = GetManagement()
    return Management:GetAccount(shop.societyName) or 0
end

exports('GetShopBalance', GetShopBalance)

-- Add driver earning
function AddDriverEarning(source, shopId, amount)
    local Player = QBCore.Functions.GetPlayer(source)
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

-- Process payment for completed job
RegisterNetEvent('dps-towjob:server:processPayment', function(source, job)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    local shopId = GetDriverShop(source)
    if not shopId then
        TowJob.Debug('Error: No shop for driver', source)
        return
    end

    local payment = job.payment

    -- Add driver's cut to their earnings (stored in shop fund)
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
end)

-- Driver collects earnings
RegisterNetEvent('dps-towjob:server:collectEarnings', function()
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
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

    -- Withdraw from shop fund
    local success, error = WithdrawFromShopFund(shopId, citizenid, amount)

    if success then
        Player.Functions.AddMoney('bank', amount, 'tow-earnings')
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
    local Player = QBCore.Functions.GetPlayer(source)
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
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    local impound = Config.ImpoundLots[impoundId]
    if not impound then
        lib.notify(source, {
            title = 'Impound',
            description = 'Invalid impound lot',
            type = 'error'
        })
        return
    end

    -- Get vehicle from impound database
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

    -- Calculate fee based on days stored
    local storedAt = vehicle.impound_date or os.time()
    local daysStored = math.floor((os.time() - storedAt) / 86400)
    local fee = CalculateImpoundFee(impoundId, daysStored)

    -- Check if player has enough money
    if Player.PlayerData.money.cash < fee and Player.PlayerData.money.bank < fee then
        lib.notify(source, {
            title = 'Impound',
            description = 'Not enough money. Fee: ' .. TowJob.FormatMoney(fee),
            type = 'error'
        })
        return
    end

    -- Remove money
    local moneyType = Player.PlayerData.money.cash >= fee and 'cash' or 'bank'
    Player.Functions.RemoveMoney(moneyType, fee, 'impound-fee')

    -- Log transaction
    MySQL.insert.await([[
        INSERT INTO tow_shop_transactions (shop, amount, type, description, citizenid)
        VALUES ('impound', ?, 'impound_fee', ?, ?)
    ]], { fee, 'Impound fee for ' .. vehiclePlate, Player.PlayerData.citizenid })

    -- Release vehicle
    MySQL.update.await([[
        UPDATE player_vehicles SET state = 0 WHERE plate = ?
    ]], { vehiclePlate })

    lib.notify(source, {
        title = 'Impound',
        description = 'Vehicle released. Fee: ' .. TowJob.FormatMoney(fee),
        type = 'success'
    })

    -- Trigger vehicle spawn on client
    TriggerClientEvent('dps-towjob:client:spawnImpoundVehicle', source, vehicle, impound.spawn)
end)
