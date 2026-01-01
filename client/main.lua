--[[
    dps-towjob Client Main
    Core client initialization and state management
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Client state
PlayerData = {}
IsOnDuty = false
CurrentShop = nil
CurrentJob = nil
CurrentVehicle = nil

-- Initialize
CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do
        Wait(100)
    end

    PlayerData = QBCore.Functions.GetPlayerData()
    TowJob.Debug('Client initialized')
end)

-- Player data updates
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerData.job = job

    if job.name ~= Config.JobName then
        -- No longer a tow driver
        IsOnDuty = false
        CurrentShop = nil
        CurrentJob = nil
    end
end)

-- Duty change from server
RegisterNetEvent('dps-towjob:client:dutyChanged', function(onDuty, shopId)
    IsOnDuty = onDuty
    CurrentShop = shopId

    if onDuty then
        -- Start duty effects
        CreateDutyBlips()
    else
        -- Remove duty effects
        RemoveDutyBlips()
        CurrentJob = nil
    end
end)

-- Job assigned
RegisterNetEvent('dps-towjob:client:jobAssigned', function(job)
    CurrentJob = job

    lib.notify({
        title = 'Tow Request',
        description = string.format('%s tow at %s', job.type:upper(), job.zone or 'Unknown'),
        type = 'inform',
        duration = 10000,
        icon = 'truck-ramp-box'
    })

    -- Show job blip
    CreateJobBlip(job)

    -- Open job UI
    OpenJobUI(job)
end)

-- Job state changed
RegisterNetEvent('dps-towjob:client:jobStateChanged', function(job)
    CurrentJob = job

    if job.state == TowJob.JobState.TOWING and job.destination then
        -- Update blip to destination
        RemoveJobBlip()
        CreateDestinationBlip(job.destination)

        lib.notify({
            title = 'Destination Set',
            description = string.format('Deliver to %s', job.destination.id),
            type = 'inform'
        })
    end
end)

-- Job completed
RegisterNetEvent('dps-towjob:client:jobCompleted', function(job)
    CurrentJob = nil

    RemoveJobBlip()
    RemoveDestinationBlip()

    lib.notify({
        title = 'Job Complete',
        description = string.format('Earned %s', TowJob.FormatMoney(job.payment.driver)),
        type = 'success',
        duration = 8000
    })
end)

-- Job cancelled
RegisterNetEvent('dps-towjob:client:jobCancelled', function(job)
    CurrentJob = nil

    RemoveJobBlip()
    RemoveDestinationBlip()
end)

-- Blip management
local DutyBlips = {}
local JobBlip = nil
local DestinationBlip = nil

function CreateDutyBlips()
    -- Create blips for tow shops
    for shopId, shop in pairs(Config.ShopJobMapping) do
        if shop.towShop and shop.depot then
            local blip = AddBlipForCoord(shop.depot.x, shop.depot.y, shop.depot.z)
            SetBlipSprite(blip, Config.Blips.depot.sprite)
            SetBlipColour(blip, Config.Blips.depot.color)
            SetBlipScale(blip, Config.Blips.depot.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(shop.label .. ' Depot')
            EndTextCommandSetBlipName(blip)
            table.insert(DutyBlips, blip)
        end
    end

    -- Create blips for impound lots
    for impoundId, impound in pairs(Config.ImpoundLots) do
        if impound.blip then
            local blip = AddBlipForCoord(impound.coords.x, impound.coords.y, impound.coords.z)
            SetBlipSprite(blip, Config.Blips.impound.sprite)
            SetBlipColour(blip, Config.Blips.impound.color)
            SetBlipScale(blip, Config.Blips.impound.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(impound.label)
            EndTextCommandSetBlipName(blip)
            table.insert(DutyBlips, blip)
        end
    end
end

function RemoveDutyBlips()
    for _, blip in ipairs(DutyBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    DutyBlips = {}
end

function CreateJobBlip(job)
    RemoveJobBlip()

    JobBlip = AddBlipForCoord(job.pickupCoords.x, job.pickupCoords.y, job.pickupCoords.z)
    SetBlipSprite(JobBlip, Config.Blips.job.sprite)
    SetBlipColour(JobBlip, Config.Blips.job.color)
    SetBlipScale(JobBlip, Config.Blips.job.scale)
    SetBlipRoute(JobBlip, true)
    SetBlipRouteColour(JobBlip, Config.Blips.job.color)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Tow Request')
    EndTextCommandSetBlipName(JobBlip)
end

function RemoveJobBlip()
    if JobBlip and DoesBlipExist(JobBlip) then
        RemoveBlip(JobBlip)
        JobBlip = nil
    end
end

function CreateDestinationBlip(destination)
    RemoveDestinationBlip()

    local coords = destination.coords
    DestinationBlip = AddBlipForCoord(coords.x, coords.y, coords.z)

    if destination.type == TowJob.DestinationType.IMPOUND then
        SetBlipSprite(DestinationBlip, Config.Blips.impound.sprite)
        SetBlipColour(DestinationBlip, Config.Blips.impound.color)
    else
        SetBlipSprite(DestinationBlip, Config.Blips.depot.sprite)
        SetBlipColour(DestinationBlip, 2) -- Green
    end

    SetBlipScale(DestinationBlip, 0.9)
    SetBlipRoute(DestinationBlip, true)
    SetBlipRouteColour(DestinationBlip, 2)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Dropoff Location')
    EndTextCommandSetBlipName(DestinationBlip)
end

function RemoveDestinationBlip()
    if DestinationBlip and DoesBlipExist(DestinationBlip) then
        RemoveBlip(DestinationBlip)
        DestinationBlip = nil
    end
end

-- Job UI
function OpenJobUI(job)
    local options = {
        {
            title = 'Accept Job',
            description = string.format('%s tow - %s', job.type:upper(), job.zone),
            icon = 'check',
            onSelect = function()
                TriggerServerEvent('dps-towjob:server:acceptJob', job.id)
            end
        },
        {
            title = 'View Details',
            description = 'See job information',
            icon = 'info',
            onSelect = function()
                ShowJobDetails(job)
            end
        },
        {
            title = 'Cancel Job',
            description = 'Return to queue',
            icon = 'xmark',
            onSelect = function()
                local input = lib.inputDialog('Cancel Reason', {
                    { type = 'input', label = 'Reason (optional)', placeholder = 'Enter reason...' }
                })
                if input then
                    TriggerServerEvent('dps-towjob:server:cancelJob', job.id, input[1])
                end
            end
        }
    }

    lib.registerContext({
        id = 'tow_job_menu',
        title = 'New Tow Request',
        options = options
    })

    lib.showContext('tow_job_menu')
end

function ShowJobDetails(job)
    local details = string.format([[
Type: %s
Location: %s
Priority: %s
Distance: %.1f miles
    ]],
        job.type:upper(),
        job.zone or 'Unknown',
        job.priority == TowJob.Priority.HIGH and 'HIGH' or (job.priority == TowJob.Priority.LOW and 'LOW' or 'NORMAL'),
        TowJob.CalculateDistance(GetEntityCoords(PlayerPedId()), job.pickupCoords)
    )

    lib.alertDialog({
        header = 'Job Details',
        content = details,
        centered = true
    })
end

-- Exports
exports('IsOnDuty', function()
    return IsOnDuty
end)

exports('GetCurrentShop', function()
    return CurrentShop
end)

exports('GetCurrentAssignment', function()
    return CurrentJob
end)

-- Key binding for tow menu
RegisterCommand('towmenu', function()
    if not IsOnDuty then
        lib.notify({
            title = 'Tow Job',
            description = 'You must be on duty',
            type = 'error'
        })
        return
    end

    OpenTowMenu()
end, false)

RegisterKeyMapping('towmenu', 'Open Tow Menu', 'keyboard', 'F7')

function OpenTowMenu()
    local options = {}

    if CurrentJob then
        table.insert(options, {
            title = 'Current Job',
            description = 'View active job details',
            icon = 'clipboard',
            onSelect = function()
                ShowJobDetails(CurrentJob)
            end
        })

        if CurrentJob.state == TowJob.JobState.ASSIGNED then
            table.insert(options, {
                title = 'Start Route',
                description = 'Begin en route to pickup',
                icon = 'route',
                onSelect = function()
                    TriggerServerEvent('dps-towjob:server:acceptJob', CurrentJob.id)
                end
            })
        end

        table.insert(options, {
            title = 'Cancel Job',
            description = 'Return job to queue',
            icon = 'xmark',
            onSelect = function()
                TriggerServerEvent('dps-towjob:server:cancelJob', CurrentJob.id, 'Driver cancelled')
            end
        })
    else
        table.insert(options, {
            title = 'Waiting for Job',
            description = 'You are in the queue',
            icon = 'clock',
            disabled = true
        })
    end

    table.insert(options, {
        title = 'View Earnings',
        description = 'Check uncollected pay',
        icon = 'dollar-sign',
        onSelect = function()
            lib.callback('dps-towjob:server:getEarnings', false, function(earnings)
                if earnings then
                    lib.alertDialog({
                        header = 'Your Earnings',
                        content = string.format([[
Total Earned: %s
Uncollected: %s
Total Jobs: %d
                        ]],
                            TowJob.FormatMoney(earnings.total),
                            TowJob.FormatMoney(earnings.uncollected),
                            earnings.jobs
                        ),
                        centered = true
                    })
                end
            end)
        end
    })

    table.insert(options, {
        title = 'Collect Earnings',
        description = 'Withdraw to bank',
        icon = 'money-bill-transfer',
        onSelect = function()
            TriggerServerEvent('dps-towjob:server:collectEarnings')
        end
    })

    table.insert(options, {
        title = 'Go Off Duty',
        description = 'End your shift',
        icon = 'power-off',
        onSelect = function()
            if CurrentJob then
                lib.notify({
                    title = 'Tow Job',
                    description = 'Complete your job first',
                    type = 'error'
                })
                return
            end
            TriggerServerEvent('dps-towjob:server:toggleDuty', CurrentShop)
        end
    })

    lib.registerContext({
        id = 'tow_main_menu',
        title = 'Tow Driver Menu',
        options = options
    })

    lib.showContext('tow_main_menu')
end
