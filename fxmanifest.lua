--[[
    dps-towjob - Comprehensive Tow Job System
    Base: qb-towjob (QBCore Team)
    Enhanced: @daemonAlex
    Integration: JG Scripts (jg-mechanic)
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dps-towjob'
author 'DPS Development (Base: QBCore Team)'
description 'Queue-based tow job system with jg-mechanic integration'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/shops.lua',
    'config/impound.lua',
    'config/vehicles.lua',
    'shared/functions.lua',
}

client_scripts {
    'client/main.lua',
    'client/duty.lua',
    'client/towing.lua',
    'client/queue.lua',
    'client/roadside.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/duty.lua',
    'server/queue.lua',
    'server/payment.lua',
    'server/dispatch.lua',
    'bridge/jg-mechanic.lua',
    'bridge/qs-billing.lua',
}

files {
    'locales/*.lua',
}

dependencies {
    'qb-core',
    'ox_lib',
    'ox_target',
    'oxmysql',
}

provides {
    'dps-towjob',
}
