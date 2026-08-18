--[[
    dps-towjob Client Dispute
    NPC Owner Dispute System for Predatory Towing
    "Hey! That's my car!"
]]

local DisputeConfig = {
    -- NPC models for angry owners
    maleModels = {
        'a_m_y_business_01', 'a_m_y_downtown_01', 'a_m_y_hipster_01',
        'a_m_y_latino_01', 'a_m_y_vinewood_01', 'a_m_m_business_01',
        'a_m_y_smartcaspat_01', 'a_m_y_stwhi_02', 'a_m_y_golfer_01',
    },
    femaleModels = {
        'a_f_y_business_01', 'a_f_y_downtown_01', 'a_f_y_hipster_01',
        'a_f_y_vinewood_01', 'a_f_m_business_02', 'a_f_y_tourist_01',
        'a_f_y_fitness_01', 'a_f_y_smartcaspat_01',
    },

    -- Angry voice lines (played as speech)
    voiceLines = {
        'GENERIC_CURSE_HIGH', 'GENERIC_CURSE_MED', 'GENERIC_FUCK_YOU',
        'GENERIC_INSULT_HIGH', 'GENERIC_INSULT_MED', 'GENERIC_WAR_CRY',
    },

    -- Spawn distance from vehicle
    spawnDistance = 15.0,

    -- How long NPC stays before giving up
    giveUpTime = 60000, -- 1 minute

    -- Dynamic dialogue system
    dialogue = {
        -- Initial confrontation lines
        approaching = {
            "HEY! What do you think you're doing?!",
            "That's MY car! Get away from it!",
            "Are you serious right now?! That's my vehicle!",
            "Hey buddy, that's not your car to tow!",
            "STOP! I was only gone for a minute!",
            "What the hell?! I just parked here!",
            "Do you have any idea who I am?!",
            "This is PRIVATE PROPERTY! Back off!",
        },
        -- When player tries to talk them down
        talkDown = {
            angry = {
                "I don't care about the law! That's MY car!",
                "You tow truck vultures are all the same!",
                "I've been parking here for YEARS!",
                "This is harassment! I'm calling my lawyer!",
            },
            calming = {
                "...Fine. I guess I shouldn't have parked there.",
                "Alright, alright... Just let me move it myself.",
                "Okay, I get it. City regulations. Whatever.",
                "You're right, my bad. Bad day, you know?",
            }
        },
        -- When player offers bribe
        bribe = {
            accepting = {
                "*takes money* ...We never had this conversation.",
                "You know what? For that price, I didn't see anything.",
                "*pockets cash* Smart man. Get out of here.",
                "Deal. But next time, I'm calling the cops.",
            },
            rejecting = {
                "You think you can BUY me off?!",
                "That's not nearly enough for my inconvenience!",
                "Keep your money! I want my car!",
            }
        },
        -- NPC offers to pay release fee
        settlement = {
            offering = {
                "Look, how much to just... forget about this?",
                "What if I pay the fine right now? Cash.",
                "Can we work something out here? Name your price.",
                "I'll pay double the ticket, just leave my car!",
                "Come on man, I'll make it worth your while...",
            },
            playerAccepts = {
                "Thank god. Here, take it. We're done here.",
                "*hands over cash* Pleasure doing business.",
                "Fine, fine. Here's your money. Happy now?",
                "Alright, deal. *counts out bills*",
            },
            playerRefuses = {
                "Are you kidding me?! That's robbery!",
                "Forget it then! Take the damn car!",
                "Unbelievable... you people are vultures!",
                "Fine! But I'm reporting this!",
            },
            lowball = {
                "That's all I got, take it or leave it.",
                "I don't have that much on me...",
                "Best I can do. Times are tough.",
            }
        },
        -- When player ignores them
        ignored = {
            angry = {
                "Don't you DARE ignore me!",
                "Oh, so that's how it's gonna be?!",
                "You're making a BIG mistake, pal!",
            },
            defeated = {
                "Fine! Take it! See if I care!",
                "*mutters* Unbelievable... vultures...",
                "This city is going to hell...",
            }
        },
        -- Fight lines
        fight = {
            "You asked for this!",
            "I'm gonna make you regret that!",
            "Let's go then!",
            "You messed with the wrong person!",
        },
        -- Calling cops lines
        callingCops = {
            "That's it, I'm calling the cops!",
            "You're gonna regret this! *dials 911*",
            "Police?! Yes, I need help immediately!",
            "I'm reporting you right now!",
            "*on phone* There's a tow truck stealing my car!",
        },
        copsArriving = {
            "The cops are on their way, buddy!",
            "You're in trouble now!",
            "Let's see what the police have to say!",
            "Good luck explaining this to the cops!",
        }
    }
}

-- Show NPC dialogue as 3D text
local function ShowNPCDialogue(ped, text, duration)
    duration = duration or 4000

    CreateThread(function()
        local endTime = GetGameTimer() + duration

        while GetGameTimer() < endTime do
            local coords = GetEntityCoords(ped)
            coords = vector3(coords.x, coords.y, coords.z + 1.0)

            -- Draw 3D text above NPC head
            local onScreen, screenX, screenY = World3dToScreen2d(coords.x, coords.y, coords.z)
            if onScreen then
                SetTextScale(0.35, 0.35)
                SetTextFont(4)
                SetTextProportional(true)
                SetTextColour(255, 255, 255, 255)
                SetTextOutline()
                SetTextCentre(true)
                SetTextEntry("STRING")
                AddTextComponentString(text)
                DrawText(screenX, screenY)

                -- Speech bubble background
                DrawRect(screenX, screenY + 0.012, 0.15, 0.03, 0, 0, 0, 150)
            end

            Wait(0)
        end
    end)
end

-- Get random dialogue from category
local function GetDialogue(category, subcategory)
    local lines = DisputeConfig.dialogue[category]
    if subcategory and lines[subcategory] then
        lines = lines[subcategory]
    end
    if type(lines) == 'table' then
        return lines[math.random(#lines)]
    end
    return "..."
end

-- Active dispute tracking
local ActiveDispute = nil
local CopsCalledRecently = false

-- Call the cops (alert police players)
function CallCops(reason)
    if not ActiveDispute or CopsCalledRecently then return end

    CopsCalledRecently = true
    local ped = ActiveDispute.ped
    local coords = GetEntityCoords(ped)

    -- Show calling dialogue
    local callLine = GetDialogue('callingCops')
    ShowNPCDialogue(ped, callLine, 4000)

    -- Phone animation
    lib.requestAnimDict('cellphone@')
    TaskPlayAnim(ped, 'cellphone@', 'cellphone_call_listen_base', 8.0, -8.0, 5000, 49, 0, false, false, false)

    Wait(3000)

    -- Trigger police alert (server handles dispatch)
    TriggerServerEvent('dps-towjob:server:policeAlert', {
        type = 'dispute',
        reason = reason or 'Vehicle owner dispute',
        coords = coords,
        street = GetStreetName(coords),
        vehiclePlate = ActiveDispute.vehiclePlate or 'Unknown'
    })

    -- Clear animation
    ClearPedTasks(ped)

    -- Show cops arriving line
    Wait(2000)
    local arriveLine = GetDialogue('copsArriving')
    ShowNPCDialogue(ped, arriveLine, 3000)

    Bridge.Notify('🚔 Police Called!', 'Cops are on the way!', 'error', 5000)

    -- Reset after cooldown
    SetTimeout(60000, function()
        CopsCalledRecently = false
    end)
end

-- Get street name from coords
function GetStreetName(coords)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local streetName = GetStreetNameFromHashKey(streetHash)
    local crossing = GetStreetNameFromHashKey(crossingHash)
    if crossing and crossing ~= '' then
        return streetName .. ' / ' .. crossing
    end
    return streetName
end

-- Check for dispute when hooking predatory vehicle
function CheckForDispute(jobData)
    if not jobData or jobData.type ~= 'predatory' then return false end

    -- Server tells us if dispute triggered
    local disputeData = lib.callback.await('dps-towjob:server:checkDispute', false, jobData.id)

    if disputeData and disputeData.triggered then
        TriggerDispute(jobData, disputeData)
        return true
    end

    return false
end

-- Trigger the dispute event
function TriggerDispute(jobData, disputeData)
    if ActiveDispute then return end -- Already in a dispute

    local vehicleCoords = jobData.pickupCoords
    local isMale = math.random() > 0.5
    local models = isMale and DisputeConfig.maleModels or DisputeConfig.femaleModels
    local model = models[math.random(#models)]

    -- Load model
    lib.requestModel(model, 5000)

    -- Find spawn point (from nearby building/sidewalk direction)
    local spawnCoords = GetOffsetFromCoords(vehicleCoords, DisputeConfig.spawnDistance)

    -- Create the angry NPC
    local ped = CreatePed(4, GetHashKey(model), spawnCoords.x, spawnCoords.y, spawnCoords.z, 0.0, true, false)

    if not DoesEntityExist(ped) then
        SetModelAsNoLongerNeeded(GetHashKey(model))
        return
    end

    -- Setup NPC
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    SetPedKeepTask(ped, true)

    -- Store dispute data
    ActiveDispute = {
        ped = ped,
        jobId = jobData.id,
        phase = 'approaching', -- approaching, confronting, fighting, resolved
        isFight = disputeData.willFight,
        bribeAmount = disputeData.bribeAmount,
        startTime = GetGameTimer(),
        vehicleCoords = vehicleCoords,
    }

    -- Make NPC run toward the player
    local playerPed = PlayerPedId()
    TaskGoToEntity(ped, playerPed, -1, 2.0, 3.0, 0, 0)

    -- Play angry voice
    PlayAmbientSpeech1(ped, DisputeConfig.voiceLines[math.random(#DisputeConfig.voiceLines)], 'SPEECH_PARAMS_FORCE_SHOUTED')

    -- Show approaching dialogue
    local approachLine = GetDialogue('approaching')
    ShowNPCDialogue(ped, approachLine, 4000)

    -- Notify player
    Bridge.Notify('⚠️ Dispute!', 'The vehicle owner is approaching!', 'warning', 5000)

    -- Start dispute handler thread
    CreateThread(function()
        HandleDispute()
    end)
end

-- Get offset coords for NPC spawn
function GetOffsetFromCoords(coords, distance)
    local angle = math.random() * 2 * math.pi
    return vector3(
        coords.x + math.cos(angle) * distance,
        coords.y + math.sin(angle) * distance,
        coords.z
    )
end

-- Main dispute handler
function HandleDispute()
    if not ActiveDispute then return end

    local ped = ActiveDispute.ped
    local playerPed = PlayerPedId()

    while ActiveDispute do
        Wait(500)

        if not DoesEntityExist(ped) then
            ResolveDispute('npc_gone')
            break
        end

        local pedCoords = GetEntityCoords(ped)
        local playerCoords = GetEntityCoords(playerPed)
        local distance = #(pedCoords - playerCoords)

        -- Check timeout
        if GetGameTimer() - ActiveDispute.startTime > DisputeConfig.giveUpTime then
            -- NPC gives up and walks away
            Bridge.Notify('Dispute', 'The owner gave up and left', 'success')
            ResolveDispute('timeout')
            break
        end

        -- Phase handling
        if ActiveDispute.phase == 'approaching' then
            if distance < 3.0 then
                ActiveDispute.phase = 'confronting'
                StartConfrontation()
            end

        elseif ActiveDispute.phase == 'confronting' then
            -- Wait for player choice (menu is open)

        elseif ActiveDispute.phase == 'fighting' then
            -- Check if NPC is dead or fled
            if IsPedDeadOrDying(ped) then
                Bridge.Notify('Dispute', 'You knocked out the owner... Better finish quick!', 'warning')
                ResolveDispute('knocked_out')
                break
            end

            -- Check if player ran away
            if distance > 50.0 then
                Bridge.Notify('Dispute', 'You fled the scene', 'error')
                ResolveDispute('fled')
                break
            end
        end
    end
end

-- Start the confrontation (show menu)
function StartConfrontation()
    if not ActiveDispute then return end

    local ped = ActiveDispute.ped
    local playerPed = PlayerPedId()

    -- Make NPC face player
    TaskTurnPedToFaceEntity(ped, playerPed, 2000)

    -- Play confrontation animation
    PlayAmbientSpeech1(ped, 'GENERIC_INSULT_HIGH', 'SPEECH_PARAMS_FORCE_SHOUTED')

    Wait(1000)

    -- Calculate settlement fee (what NPC offers to pay)
    -- Higher than commission but lower than full tow value
    local baseCommission = ActiveDispute.commission or 75
    local settlementFee = math.floor(baseCommission * (1.5 + math.random() * 0.5)) -- 150-200% of commission
    ActiveDispute.settlementFee = settlementFee

    -- 40% chance NPC offers settlement first
    local npcOffersSettlement = math.random() < 0.40

    if npcOffersSettlement then
        -- NPC makes the first offer
        local offerLine = GetDialogue('settlement', 'offering')
        ShowNPCDialogue(ped, offerLine, 3500)
        Wait(3500)
    end

    -- Show options menu
    local options = {
        {
            title = '💬 Talk them down',
            description = 'Try to explain you\'re just doing your job',
            icon = 'comments',
            onSelect = function()
                AttemptTalkDown()
            end
        },
        {
            title = '💵 Accept settlement ($' .. settlementFee .. ')',
            description = 'Let them pay to keep their car',
            icon = 'hand-holding-dollar',
            onSelect = function()
                AcceptSettlement()
            end
        },
        {
            title = '💰 Counter-offer ($' .. math.floor(settlementFee * 1.5) .. ')',
            description = 'Demand more money',
            icon = 'money-bill-trend-up',
            onSelect = function()
                CounterOffer()
            end
        },
        {
            title = '🏃 Ignore and continue',
            description = 'Risk them getting violent',
            icon = 'person-running',
            onSelect = function()
                IgnoreOwner()
            end
        },
        {
            title = '❌ Abandon job',
            description = 'Leave the vehicle alone (no pay)',
            icon = 'ban',
            onSelect = function()
                AbandonJob()
            end
        }
    }

    lib.registerContext({
        id = 'tow_dispute_menu',
        title = '🚨 Angry Vehicle Owner',
        options = options
    })

    lib.showContext('tow_dispute_menu')
end

-- Accept the NPC's settlement offer
function AcceptSettlement()
    if not ActiveDispute then return end

    local ped = ActiveDispute.ped
    local fee = ActiveDispute.settlementFee

    -- NPC pays the settlement
    local acceptLine = GetDialogue('settlement', 'playerAccepts')
    ShowNPCDialogue(ped, acceptLine, 3000)
    PlayAmbientSpeech1(ped, 'GENERIC_THANKS', 'SPEECH_PARAMS_FORCE')

    -- Player receives payment
    TriggerServerEvent('dps-towjob:server:settlementPaid', ActiveDispute.jobId, fee)

    Bridge.Notify('Settlement Accepted', 'You received $' .. fee .. ' - Vehicle released', 'success')

    Wait(2000)
    ResolveDispute('settlement_accepted')
end

-- Counter-offer for more money
function CounterOffer()
    if not ActiveDispute then return end

    local ped = ActiveDispute.ped
    local counterAmount = math.floor(ActiveDispute.settlementFee * 1.5)

    Bridge.Notify('Negotiating', 'Demanding $' .. counterAmount .. '...', 'inform')

    -- 50% chance they accept, 30% lowball, 20% refuse
    local roll = math.random()

    Wait(2000)

    if roll < 0.50 then
        -- They accept the higher price (reluctantly)
        local grumbleLine = "*sighs heavily* Fine... highway robbery, but fine."
        ShowNPCDialogue(ped, grumbleLine, 3000)
        PlayAmbientSpeech1(ped, 'GENERIC_CURSE_MED', 'SPEECH_PARAMS_FORCE')

        TriggerServerEvent('dps-towjob:server:settlementPaid', ActiveDispute.jobId, counterAmount)

        Bridge.Notify('Counter Accepted!', 'You received $' .. counterAmount, 'success')

        Wait(2000)
        ResolveDispute('counter_accepted')

    elseif roll < 0.80 then
        -- They lowball - offer less
        local lowballAmount = math.floor(ActiveDispute.settlementFee * 0.75)
        local lowballLine = GetDialogue('settlement', 'lowball')
        ShowNPCDialogue(ped, lowballLine, 3000)

        Wait(2500)

        -- Show accept/refuse for lowball
        local options = {
            {
                title = '✅ Accept $' .. lowballAmount,
                description = 'Take the lower offer',
                icon = 'check',
                onSelect = function()
                    local acceptLine = GetDialogue('settlement', 'playerAccepts')
                    ShowNPCDialogue(ped, acceptLine, 2000)
                    TriggerServerEvent('dps-towjob:server:settlementPaid', ActiveDispute.jobId, lowballAmount)
                    Bridge.Notify('Deal', 'You received $' .. lowballAmount, 'success')
                    Wait(1500)
                    ResolveDispute('lowball_accepted')
                end
            },
            {
                title = '❌ Refuse and tow',
                description = 'Continue with the tow',
                icon = 'xmark',
                onSelect = function()
                    local refuseLine = GetDialogue('settlement', 'playerRefuses')
                    ShowNPCDialogue(ped, refuseLine, 2500)
                    PlayAmbientSpeech1(ped, 'GENERIC_CURSE_HIGH', 'SPEECH_PARAMS_FORCE_SHOUTED')
                    Bridge.Notify('Refused', 'Continuing with the tow...', 'inform')
                    Wait(2000)
                    if ActiveDispute.isFight and math.random() < 0.5 then
                        StartFight()
                    else
                        ResolveDispute('refused_lowball')
                    end
                end
            }
        }

        lib.registerContext({
            id = 'tow_lowball_menu',
            title = '💸 Counter Offer',
            options = options
        })

        lib.showContext('tow_lowball_menu')

    else
        -- They refuse entirely and get mad
        local refuseLine = GetDialogue('settlement', 'playerRefuses')
        ShowNPCDialogue(ped, refuseLine, 3000)
        PlayAmbientSpeech1(ped, 'GENERIC_CURSE_HIGH', 'SPEECH_PARAMS_FORCE_SHOUTED')

        Bridge.Notify('Refused!', 'They won\'t pay that much!', 'error')

        Wait(2000)

        if ActiveDispute.isFight then
            StartFight()
        else
            local defeatLine = GetDialogue('ignored', 'defeated')
            ShowNPCDialogue(ped, defeatLine, 2500)
            Wait(2500)
            ResolveDispute('counter_refused')
        end
    end
end

-- Attempt to talk down the owner
function AttemptTalkDown()
    if not ActiveDispute then return end

    Bridge.Notify('Dispute', 'Attempting to reason with them...', 'inform')

    -- 50% success rate for talking
    local success = math.random() > 0.5

    local ped = ActiveDispute.ped

    if success then
        -- Play calming dialogue
        local calmLine = GetDialogue('talkDown', 'calming')
        ShowNPCDialogue(ped, calmLine, 3000)
        PlayAmbientSpeech1(ped, 'GENERIC_THANKS', 'SPEECH_PARAMS_FORCE')

        Wait(3000)

        Bridge.Notify('Dispute Resolved', 'They understood. +$25 bonus!', 'success')

        -- Bonus pay
        TriggerServerEvent('dps-towjob:server:disputeBonus', ActiveDispute.jobId, 'talked_down')

        ResolveDispute('talked_down')
    else
        -- They stay angry
        local angryLine = GetDialogue('talkDown', 'angry')
        ShowNPCDialogue(ped, angryLine, 3000)
        PlayAmbientSpeech1(ped, 'GENERIC_CURSE_HIGH', 'SPEECH_PARAMS_FORCE_SHOUTED')

        Bridge.Notify('Dispute', 'They\'re not listening!', 'error')

        Wait(2000)

        if ActiveDispute.isFight then
            StartFight()
        else
            -- They just keep yelling but don't fight
            local defeatLine = GetDialogue('ignored', 'defeated')
            ShowNPCDialogue(ped, defeatLine, 3000)
            Bridge.Notify('Dispute', 'They\'re furious but walking away...', 'warning')
            Wait(3000)
            ResolveDispute('angry_left')
        end
    end
end

-- Attempt to bribe the owner
function AttemptBribe()
    if not ActiveDispute then return end

    local amount = ActiveDispute.bribeAmount
    local ped = ActiveDispute.ped

    -- Check if player has money
    local hasMoney = lib.callback.await('dps-towjob:server:checkMoney', false, amount)

    if not hasMoney then
        Bridge.Notify('Dispute', 'You don\'t have $' .. amount, 'error')
        StartConfrontation() -- Show menu again
        return
    end

    -- Take money and resolve
    TriggerServerEvent('dps-towjob:server:payBribe', ActiveDispute.jobId, amount)

    -- Show accepting dialogue
    local acceptLine = GetDialogue('bribe', 'accepting')
    ShowNPCDialogue(ped, acceptLine, 3000)
    PlayAmbientSpeech1(ped, 'GENERIC_THANKS', 'SPEECH_PARAMS_FORCE')

    Bridge.Notify('Dispute Resolved', 'They took the money and left', 'success')

    Wait(2000)
    ResolveDispute('bribed')
end

-- Ignore the owner (risk fight)
function IgnoreOwner()
    if not ActiveDispute then return end

    local ped = ActiveDispute.ped

    Bridge.Notify('Dispute', 'Continuing with the tow...', 'inform')

    if ActiveDispute.isFight then
        -- They get angrier
        local angryLine = GetDialogue('ignored', 'angry')
        ShowNPCDialogue(ped, angryLine, 2000)
        Wait(2000)
        StartFight()
    else
        -- They just yell but leave
        local defeatLine = GetDialogue('ignored', 'defeated')
        ShowNPCDialogue(ped, defeatLine, 3000)
        PlayAmbientSpeech1(ped, 'GENERIC_CURSE_HIGH', 'SPEECH_PARAMS_FORCE_SHOUTED')
        Bridge.Notify('Dispute', 'They gave up and stormed off', 'success')
        Wait(3000)
        ResolveDispute('ignored')
    end
end

-- Start a fight with the NPC
function StartFight()
    if not ActiveDispute then return end

    ActiveDispute.phase = 'fighting'

    local ped = ActiveDispute.ped
    local playerPed = PlayerPedId()

    -- 40% chance NPC calls cops before/during fight
    if math.random() < 0.40 then
        CreateThread(function()
            Wait(math.random(2000, 5000))
            CallCops('Assault during vehicle dispute')
        end)
    end

    -- Show fight dialogue
    local fightLine = GetDialogue('fight')
    ShowNPCDialogue(ped, fightLine, 2000)

    Bridge.Notify('⚠️ Fight!', 'The owner is attacking you!', 'error', 5000)

    -- Give NPC a weapon (fists or random melee)
    local weapons = { 'WEAPON_UNARMED', 'WEAPON_UNARMED', 'WEAPON_UNARMED', 'WEAPON_BAT', 'WEAPON_WRENCH' }
    local weapon = weapons[math.random(#weapons)]
    GiveWeaponToPed(ped, GetHashKey(weapon), 1, false, true)

    -- Make NPC arrestable by police via ox_target
    MakeNPCArrestable(ped)

    -- Make them fight
    SetPedCombatAttributes(ped, 46, true) -- Can fight armed peds
    SetPedCombatAttributes(ped, 5, true)  -- Can leave cover
    TaskCombatPed(ped, playerPed, 0, 16)

    -- Play war cry
    PlayAmbientSpeech1(ped, 'GENERIC_WAR_CRY', 'SPEECH_PARAMS_FORCE_SHOUTED')

    -- Tell server NPC is fighting (for police records)
    TriggerServerEvent('dps-towjob:server:npcFighting', {
        netId = NetworkGetNetworkIdFromEntity(ped),
        coords = GetEntityCoords(ped),
        jobId = ActiveDispute.jobId
    })
end

-- Make NPC targetable/arrestable by police
function MakeNPCArrestable(ped)
    if not DoesEntityExist(ped) then return end

    -- Set entity state for police to identify
    local netId = NetworkGetNetworkIdFromEntity(ped)
    if netId and netId > 0 then
        Entity(ped).state:set('isTowDispute', true, true)
        Entity(ped).state:set('canArrest', true, true)
    end

    -- Add ox_target options for police
    exports.ox_target:addLocalEntity(ped, {
        {
            name = 'arrest_dispute_npc',
            icon = 'fas fa-handcuffs',
            label = 'Arrest Suspect',
            distance = 2.5,
            groups = { 'police', 'bcso', 'sasp', 'sahp', 'lspd', 'sast' },
            onSelect = function()
                TriggerEvent('dps-towjob:client:policeArrest', ped)
            end
        },
        {
            name = 'detain_dispute_npc',
            icon = 'fas fa-user-lock',
            label = 'Detain Suspect',
            distance = 2.5,
            groups = { 'police', 'bcso', 'sasp', 'sahp', 'lspd', 'sast' },
            onSelect = function()
                TriggerEvent('dps-towjob:client:policeDetain', ped)
            end
        },
        {
            name = 'question_dispute_npc',
            icon = 'fas fa-comments',
            label = 'Question Suspect',
            distance = 3.0,
            groups = { 'police', 'bcso', 'sasp', 'sahp', 'lspd', 'sast' },
            onSelect = function()
                TriggerEvent('dps-towjob:client:policeQuestion', ped)
            end
        }
    })

    TowJob.Debug('NPC marked as arrestable, NetID:', netId)
end

-- Police arrest event
RegisterNetEvent('dps-towjob:client:policeArrest', function(ped)
    if not DoesEntityExist(ped) then return end

    -- Check if player is police
    if not Bridge.HasJob('police') and not Bridge.HasJob('bcso') and not Bridge.HasJob('sasp') and not Bridge.HasJob('sahp') and not Bridge.HasJob('lspd') and not Bridge.HasJob('sast') then
        Bridge.Notify('Error', 'You are not authorized', 'error')
        return
    end

    -- Make NPC surrender
    ClearPedTasks(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskSetBlockingOfNonTemporaryEvents(ped, true)

    -- Hands up animation
    lib.requestAnimDict('missminuteman_1ig_2')
    TaskPlayAnim(ped, 'missminuteman_1ig_2', 'handsup_base', 8.0, -8.0, -1, 49, 0, false, false, false)

    Bridge.Notify('Arrest', 'Suspect apprehended', 'success')

    -- Notify server
    TriggerServerEvent('dps-towjob:server:npcArrested', {
        netId = NetworkGetNetworkIdFromEntity(ped),
        jobId = ActiveDispute and ActiveDispute.jobId or nil
    })

    -- Resolve dispute if active
    if ActiveDispute and ActiveDispute.ped == ped then
        Wait(3000)
        Bridge.Notify('Dispute', 'Police handled the situation', 'success')
        ResolveDispute('police_arrest')
    end
end)

-- Police detain event
RegisterNetEvent('dps-towjob:client:policeDetain', function(ped)
    if not DoesEntityExist(ped) then return end

    -- Make NPC stop fighting and kneel
    ClearPedTasks(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)

    -- Kneel animation
    lib.requestAnimDict('random@arrests')
    TaskPlayAnim(ped, 'random@arrests', 'kneeling_arrest_idle', 8.0, -8.0, -1, 1, 0, false, false, false)

    Bridge.Notify('Detained', 'Suspect is detained', 'inform')
end)

-- Police question event
RegisterNetEvent('dps-towjob:client:policeQuestion', function(ped)
    if not DoesEntityExist(ped) then return end

    -- Play ambient speech
    local responses = {
        "It's MY car! That tow truck driver is stealing it!",
        "I only parked there for a second!",
        "This is harassment! I want a lawyer!",
        "He started it, officer! I was just protecting my property!",
        "I'll sue this whole city!",
    }

    local response = responses[math.random(#responses)]
    ShowNPCDialogue(ped, response, 4000)
    PlayAmbientSpeech1(ped, 'GENERIC_CURSE_MED', 'SPEECH_PARAMS_FORCE')

    Bridge.Notify('Response', response, 'inform', 4000)
end)

-- Abandon the job
function AbandonJob()
    if not ActiveDispute then return end

    Bridge.Notify('Job Abandoned', 'You left the vehicle', 'error')

    TriggerServerEvent('dps-towjob:server:cancelJob', ActiveDispute.jobId, 'Dispute - abandoned')

    ResolveDispute('abandoned')
end

-- Resolve the dispute and cleanup
function ResolveDispute(reason)
    if not ActiveDispute then return end

    local ped = ActiveDispute.ped

    -- Make NPC leave
    if DoesEntityExist(ped) then
        if reason ~= 'knocked_out' then
            -- Walk away
            ClearPedTasks(ped)
            TaskWanderStandard(ped, 10.0, 10)

            -- Delete after delay
            SetTimeout(10000, function()
                if DoesEntityExist(ped) then
                    DeleteEntity(ped)
                end
            end)
        else
            -- Leave knocked out NPC for a bit
            SetTimeout(30000, function()
                if DoesEntityExist(ped) then
                    DeleteEntity(ped)
                end
            end)
        end
    end

    ActiveDispute = nil

    TowJob.Debug('Dispute resolved:', reason)
end

-- Server callback to check for dispute
lib.callback.register('dps-towjob:client:triggerDispute', function(jobData, disputeData)
    TriggerDispute(jobData, disputeData)
end)

-- L3: on resource stop/restart, delete any active dispute NPC so it doesn't
-- orphan in the world.
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    if ActiveDispute and ActiveDispute.ped and DoesEntityExist(ActiveDispute.ped) then
        DeleteEntity(ActiveDispute.ped)
    end
    ActiveDispute = nil
end)

-- Export for towing.lua to check
exports('CheckForDispute', CheckForDispute)
exports('IsInDispute', function() return ActiveDispute ~= nil end)

-- ============================================
-- POLICE BLIP HANDLER
-- ============================================

-- Police receive blip for active disputes
RegisterNetEvent('dps-towjob:client:policeBlip', function(data)
    if not data or not data.coords then return end

    -- Create blip
    local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    SetBlipSprite(blip, data.sprite or 477)
    SetBlipColour(blip, data.color or 1)
    SetBlipScale(blip, 1.0)
    SetBlipFlashes(blip, true)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(data.label or 'Dispute in Progress')
    EndTextCommandSetBlipName(blip)

    -- Set waypoint automatically
    SetNewWaypoint(data.coords.x, data.coords.y)

    -- Remove after duration
    local duration = data.duration or 120000
    SetTimeout(duration, function()
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end)

    -- Stop flashing after 30 seconds
    SetTimeout(30000, function()
        if DoesBlipExist(blip) then
            SetBlipFlashes(blip, false)
        end
    end)
end)
