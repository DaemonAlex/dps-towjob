--[[
    dps-towjob Framework Bridge
    Supports: QBCore, QBX, ESX
]]

Bridge = {}

-- Detect framework
local function DetectFramework()
    if GetResourceState('qbx_core') == 'started' then
        return 'qbx'
    elseif GetResourceState('qb-core') == 'started' then
        return 'qb'
    elseif GetResourceState('es_extended') == 'started' then
        return 'esx'
    end
    return nil
end

Bridge.Framework = DetectFramework()

if not Bridge.Framework then
    print('^1[dps-towjob] ERROR: No supported framework detected!^0')
    print('^3[dps-towjob] Supported: qb-core, qbx_core, es_extended^0')
end

-- Framework object cache
Bridge._fw = nil

-- IMPORTANT: This target build of qbx_core does NOT expose GetCoreObject()
-- (calling it throws). QBX is handled entirely via discrete exports
-- (exports.qbx_core:GetPlayer / :GetQBPlayers / :GetPlayerByCitizenId) in
-- bridge/server.lua and bridge/client.lua, so GetFramework() must NEVER call
-- GetCoreObject for qbx. Only real qb-core and ESX return a shared object here.
function Bridge.GetFramework()
    if Bridge._fw then return Bridge._fw end

    if Bridge.Framework == 'qb' then
        Bridge._fw = exports['qb-core']:GetCoreObject()
    elseif Bridge.Framework == 'esx' then
        Bridge._fw = exports['es_extended']:getSharedObject()
    end
    -- qbx intentionally returns nil (uses discrete exports instead)

    return Bridge._fw
end

-- Framework checks
function Bridge.IsQB()
    return Bridge.Framework == 'qb' or Bridge.Framework == 'qbx'
end

function Bridge.IsQBX()
    return Bridge.Framework == 'qbx'
end

function Bridge.IsESX()
    return Bridge.Framework == 'esx'
end

-- Resource detection
Bridge.Resources = {
    target = GetResourceState('ox_target') == 'started' and 'ox_target' or
             GetResourceState('qb-target') == 'started' and 'qb-target' or nil,

    inventory = GetResourceState('ox_inventory') == 'started' and 'ox_inventory' or
                GetResourceState('qs-inventory') == 'started' and 'qs-inventory' or
                GetResourceState('qb-inventory') == 'started' and 'qb-inventory' or nil,

    dispatch = GetResourceState('qs-dispatch') == 'started' and 'qs-dispatch' or
               GetResourceState('ps-dispatch') == 'started' and 'ps-dispatch' or
               GetResourceState('cd_dispatch') == 'started' and 'cd_dispatch' or nil,

    billing = GetResourceState('qs-billing') == 'started' and 'qs-billing' or
              GetResourceState('qb-billing') == 'started' and 'qb-billing' or nil,

    management = GetResourceState('qbx_management') == 'started' and 'qbx_management' or
                 GetResourceState('qb-management') == 'started' and 'qb-management' or
                 GetResourceState('esx_society') == 'started' and 'esx_society' or nil,

    jgMechanic = GetResourceState('jg-mechanic') == 'started'
}

-- Debug output
if Config and Config.Debug then
    print('^2[dps-towjob] Framework: ' .. (Bridge.Framework or 'none') .. '^0')
    print('^2[dps-towjob] Target: ' .. (Bridge.Resources.target or 'none') .. '^0')
    print('^2[dps-towjob] Dispatch: ' .. (Bridge.Resources.dispatch or 'none') .. '^0')
    print('^2[dps-towjob] jg-mechanic: ' .. tostring(Bridge.Resources.jgMechanic) .. '^0')
end

-- Make Bridge globally available
_G.Bridge = Bridge
