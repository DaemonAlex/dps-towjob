--[[
    dps-towjob - Comprehensive Tow Job System
    Base: qb-towjob (QBCore Team)
    Enhanced: @daemonAlex
    Integration: JG Scripts (jg-mechanic)

    Features:
    - Queue-based dispatch system
    - Multi-location impound support
    - Shop integration with fair distribution
    - NPC "predatory" towing system
    - NUI Dispatch Dashboard
    - Framework-agnostic (QB/QBX/ESX)
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dps-towjob'
author 'DPS Development (Base: QBCore Team)'
description 'Queue-based tow job system with jg-mechanic integration'
version '2.8.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/shops.lua',
    'config/impound.lua',
    'config/vehicles.lua',
    'shared/functions.lua',
}

client_scripts {
    -- Bridge (load first)
    'bridge/init.lua',
    'bridge/client.lua',

    -- Core (order matters: main defines globals used by all others)
    'client/main.lua',
    'client/duty.lua',
    'client/towing.lua',
    'client/queue.lua',
    'client/roadside.lua',
    'client/nui.lua',
    'client/dispute.lua',

    -- Bridge integrations (client)
    'bridge/qs-billing_client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',

    -- Bridge (load first)
    'bridge/init.lua',
    'bridge/server.lua',

    -- Core (order matters: main defines globals used by all others)
    'server/main.lua',
    'server/duty.lua',
    'server/queue.lua',
    'server/pve.lua',
    'server/payment.lua',
    'server/dispatch.lua',

    -- Bridge integrations (server)
    'bridge/jg-mechanic.lua',
    'bridge/qs-billing.lua',
}

-- UI files
ui_page 'ui/index.html'

files {
    'locales/*.lua',
    'ui/index.html',
    'ui/styles/main.css',
    'ui/js/utils.js',
    'ui/js/app.js',
}

dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql',
}

provides {
    'dps-towjob',
}
