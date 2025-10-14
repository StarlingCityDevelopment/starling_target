if not lib.checkDependency('ox_lib', '3.30.0', true) then return end

lib.locale()

local utils = require 'client.utils'
local state = require 'client.state'
local options = require 'client.api'.getTargetOptions()

require 'client.debug'
require 'client.defaults'
require 'client.compat.qtarget'

local SendNuiMessage = SendNuiMessage
local GetEntityCoords = GetEntityCoords
local GetEntityType = GetEntityType
local HasEntityClearLosToEntity = HasEntityClearLosToEntity
local GetEntityBoneIndexByName = GetEntityBoneIndexByName
local GetEntityBonePosition_2 = GetEntityBonePosition_2
local GetEntityModel = GetEntityModel
local IsDisabledControlJustPressed = IsDisabledControlJustPressed
local DisableControlAction = DisableControlAction
local DisablePlayerFiring = DisablePlayerFiring
local GetModelDimensions = GetModelDimensions
local GetOffsetFromEntityInWorldCoords = GetOffsetFromEntityInWorldCoords
local currentTarget = {}
local currentMenu
local menuChanged
local menuHistory = {}
local nearbyZones
local zones = {}
local frozenEntity
local frozenEntityType
local frozenEntityModel

-- Toggle ox_target, instead of holding the hotkey
local toggleHotkey = GetConvarInt('ox_target:toggleHotkey', 0) == 1
local mouseButton = GetConvarInt('ox_target:leftClick', 1) == 1 and 24 or 25
local debug = GetConvarInt('ox_target:debug', 0) == 1
local vec0 = vec3(0, 0, 0)

---@param option OxTargetOption
---@param distance number
---@param endCoords vector3
---@param entityHit? number
---@param entityType? number
---@param entityModel? number | false
local function shouldHide(option, distance, endCoords, entityHit, entityType, entityModel)
    if option.menuName ~= currentMenu then
        return true
    end

    if distance > (option.distance or 7) then
        return true
    end

    if option.groups and not utils.hasPlayerGotGroup(option.groups) then
        return true
    end

    if option.items and not utils.hasPlayerGotItems(option.items, option.anyItem) then
        return true
    end

    if not option.me and entityHit == cache.ped then
        return true
    end

    local bone = entityModel and option.bones or nil

    if bone then
        ---@cast entityHit number
        ---@cast entityType number
        ---@cast entityModel number

        local _type = type(bone)

        if _type == 'string' then
            local boneId = GetEntityBoneIndexByName(entityHit, bone)

            if boneId ~= -1 and #(endCoords - GetEntityBonePosition_2(entityHit, boneId)) <= 2 then
                bone = boneId
            else
                return true
            end
        elseif _type == 'table' then
            local closestBone, boneDistance

            for j = 1, #bone do
                local boneId = GetEntityBoneIndexByName(entityHit, bone[j])

                if boneId ~= -1 then
                    local dist = #(endCoords - GetEntityBonePosition_2(entityHit, boneId))

                    if dist <= (boneDistance or 1) then
                        closestBone = boneId
                        boneDistance = dist
                    end
                end
            end

            if closestBone then
                bone = closestBone
            else
                return true
            end
        end
    end

    local offset = entityModel and option.offset or nil

    if offset then
        ---@cast entityHit number
        ---@cast entityType number
        ---@cast entityModel number

        if not option.absoluteOffset then
            local min, max = GetModelDimensions(entityModel)
            offset = (max - min) * offset + min
        end

        offset = GetOffsetFromEntityInWorldCoords(entityHit, offset.x, offset.y, offset.z)

        if #(endCoords - offset) > (option.offsetSize or 1) then
            return true
        end
    end

    if option.canInteract then
        local success, resp = pcall(option.canInteract, entityHit, distance, endCoords, option.name, bone)
        return not success or not resp
    end
end

local function startTargeting()
    if state.isDisabled() or state.isActive() or IsNuiFocused() or IsPauseMenuActive() then return end

    state.setActive(true)

    local flag = 511
    local hit, entityHit, endCoords, distance, lastEntity, entityType, entityModel, hasTarget, zonesChanged
    table.wipe(zones)

    CreateThread(function()
        local dict, texture = utils.getTexture()
        local lastCoords

        while state.isActive() or state.isNuiFocused() do
            lastCoords = endCoords == vec0 and lastCoords or endCoords or vec0

            if debug and not state.isNuiFocused() then
                DrawSphere(lastCoords.x, lastCoords.y, lastCoords.z, 0.05, 255, 0, 0, 0.5)
            end

            if hasTarget and not state.isNuiFocused() then
                local cursorX, cursorY = utils.getCursorScreenPosition()
                SetTextScale(0.35, 0.35)
                SetTextFont(4)
                SetTextProportional(true)
                SetTextColour(255, 255, 255, 215)
                SetTextEntry("STRING")
                SetTextCentre(true)
                AddTextComponentString("intéragir")
                EndTextCommandDisplayText(cursorX + 0.004, cursorY + 0.025)

                if options.size ~= 0 and entityType ~= 0 then
                    SetMouseCursorStyle(5)
                    SetEntityAlpha(entityHit, 150, false)
                end
            else
                SetMouseCursorStyle(1)
            end

            utils.drawZoneSprites(dict, texture)
            DisablePlayerFiring(cache.playerId, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)

            if state.isNuiFocused() then
                DisableControlAction(0, 1, true)
                DisableControlAction(0, 2, true)

                if not hasTarget or (options and IsDisabledControlJustPressed(0, 25)) then
                    state.setNuiFocus(false, false)
                    frozenEntity = nil
                    frozenEntityType = nil
                    frozenEntityModel = nil
                end
            elseif hasTarget and IsDisabledControlJustPressed(0, mouseButton) then
                if options or zones then
                    frozenEntity = entityHit
                    frozenEntityType = entityType
                    frozenEntityModel = entityModel
                    local cursorX, cursorY = utils.getCursorScreenPosition()
                    SendNuiMessage('{"event": "visible", "state": true}')
                    SendNuiMessage(json.encode({
                        event = 'setTarget',
                        options = options,
                        zones = zones,
                        cursorX = cursorX,
                        cursorY = cursorY,
                    }, { sort_keys = true }))
                    state.setNuiFocus(true, true)
                    state.setActive(false)
                    if lastEntity > 0 then
                        ResetEntityAlpha(lastEntity)
                    end
                end
            end

            Wait(0)
        end

        if lastEntity > 0 then
            ResetEntityAlpha(lastEntity)
        end

        SetStreamedTextureDictAsNoLongerNeeded(dict)

        state.setNuiFocus(false)
        SendNuiMessage('{"event": "visible", "state": false}')
        table.wipe(currentTarget)
        options:wipe()

        if nearbyZones then table.wipe(nearbyZones) end
    end)

    local screenX, screenY = GetActiveScreenResolution()

    while state.isActive() do
        if not state.isNuiFocused() and lib.progressActive() then
            state.setActive(false)
            break
        end

        if not state.isNuiFocused() then
            SetMouseCursorThisFrame()
        end

        local playerCoords = GetEntityCoords(cache.ped)
        hit, entityHit, endCoords, _, _, _, entityType = utils.raycastFromMouse(screenX, screenY)
        distance = #(playerCoords - endCoords)

        nearbyZones, zonesChanged = utils.getNearbyZones(endCoords)

        local entityChanged = entityHit ~= lastEntity
        local newOptions = (not state.isNuiFocused() or menuChanged) and (zonesChanged or entityChanged or menuChanged) and
            true

        if entityHit > 0 and entityChanged then
            currentMenu = nil

            if flag ~= 511 then
                entityHit = HasEntityClearLosToEntity(entityHit, cache.ped, 7) and entityHit or 0
            end

            if lastEntity ~= entityHit and debug then
                if lastEntity then
                    SetEntityDrawOutline(lastEntity, false)
                end

                if entityType ~= 1 then
                    SetEntityDrawOutline(entityHit, true)
                end
            end

            if entityHit > 0 then
                local success, result = pcall(GetEntityModel, entityHit)
                entityModel = success and result
            end
        end

        if not state.isNuiFocused() or menuChanged then
            if not state.isNuiFocused() then
                if hasTarget and (zonesChanged or (entityChanged and hasTarget > 1)) then
                    SendNuiMessage('{"event": "leftTarget"}')

                    if entityChanged then options:wipe() end

                    if debug and lastEntity > 0 then SetEntityDrawOutline(lastEntity, false) end

                    hasTarget = false
                end
            end

            if menuChanged and not currentMenu then
                local targetEntity = frozenEntity or (entityHit > 0 and entityHit or lastEntity)
                local targetEntityType = frozenEntityType or entityType
                local targetEntityModel = frozenEntityModel or entityModel
                if targetEntity and targetEntity > 0 and targetEntityModel then
                    options:set(targetEntity, targetEntityType, targetEntityModel)
                end
            elseif not menuChanged and newOptions and entityModel and entityHit > 0 then
                options:set(entityHit, entityType, entityModel)
            end
        end

        if lastEntity ~= entityHit then
            ResetEntityAlpha(lastEntity)
        end

        lastEntity = entityHit
        currentTarget.entity = entityHit
        currentTarget.coords = endCoords
        currentTarget.distance = distance
        local hidden = 0
        local totalOptions = 0

        if not state.isNuiFocused() or menuChanged then
            local checkEntity = state.isNuiFocused() and frozenEntity or entityHit
            local checkEntityType = state.isNuiFocused() and frozenEntityType or entityType
            local checkEntityModel = state.isNuiFocused() and frozenEntityModel or entityModel

            for k, v in pairs(options) do
                local optionCount = #v
                local dist = k == '__global' and 0 or distance
                totalOptions += optionCount

                for i = 1, optionCount do
                    local option = v[i]
                    local hide = shouldHide(option, dist, endCoords, checkEntity, checkEntityType, checkEntityModel)

                    if option.hide ~= hide then
                        option.hide = hide
                        newOptions = true
                    end

                    if hide then hidden += 1 end
                end
            end

            if zonesChanged then table.wipe(zones) end

            for i = 1, #nearbyZones do
                local zoneOptions = nearbyZones[i].options
                local optionCount = #zoneOptions
                totalOptions += optionCount
                zones[i] = zoneOptions

                for j = 1, optionCount do
                    local option = zoneOptions[j]
                    local hide = shouldHide(option, distance, endCoords, checkEntity)

                    if option.hide ~= hide then
                        option.hide = hide
                        newOptions = true
                    end

                    if hide then hidden += 1 end
                end
            end
        end

        if newOptions then
            if hasTarget == 1 and (totalOptions - hidden) > 1 then
                hasTarget = true
            end

            if not menuChanged and hasTarget and hidden == totalOptions then
                if hasTarget ~= 1 then
                    hasTarget = false
                    SendNuiMessage('{"event": "leftTarget"}')
                end
            elseif menuChanged or (hasTarget ~= 1 and hidden ~= totalOptions) then
                hasTarget = options.size

                if currentMenu and options.__global[1]?.name ~= 'builtin:goback' then
                    table.insert(options.__global, 1, {
                        icon = 'fa-solid fa-circle-chevron-left',
                        label = locale('go_back'),
                        name = 'builtin:goback',
                        menuName = currentMenu,
                        openMenu = 'home',
                        me = true
                    })
                end

                if state.isNuiFocused() then
                    SendNuiMessage(json.encode({
                        event = 'setTarget',
                        options = options,
                        zones = zones,
                    }, { sort_keys = true }))
                end
            end

            menuChanged = false
        end

        if toggleHotkey and IsPauseMenuActive() then
            state.setActive(false)
        end

        if not hasTarget or hasTarget == 1 then
            flag = flag == 511 and 26 or 511
        end

        Wait(0)
    end

    if lastEntity and debug then
        SetEntityDrawOutline(lastEntity, false)
    end

    if not state.isNuiFocused() then
        state.setNuiFocus(false)
        SendNuiMessage('{"event": "visible", "state": false}')
    end
end

do
    ---@type KeybindProps
    local keybind = {
        name = 'ox_target',
        defaultKey = GetConvar('ox_target:defaultHotkey', 'LMENU'),
        defaultMapper = 'keyboard',
        description = locale('toggle_targeting'),
    }

    if toggleHotkey then
        function keybind:onPressed()
            if state.isActive() then
                return state.setActive(false)
            end

            return startTargeting()
        end
    else
        keybind.onPressed = startTargeting

        function keybind:onReleased()
            state.setActive(false)
        end
    end

    lib.addKeybind(keybind)
end

---@generic T
---@param option T
---@param server? boolean
---@return T
local function getResponse(option, server)
    local response = table.clone(option)
    response.entity = currentTarget.entity
    response.zone = currentTarget.zone
    response.coords = currentTarget.coords
    response.distance = currentTarget.distance

    if server then
        response.entity = response.entity ~= 0 and NetworkGetEntityIsNetworked(response.entity) and
            NetworkGetNetworkIdFromEntity(response.entity) or 0
    end

    response.icon = nil
    response.groups = nil
    response.items = nil
    response.canInteract = nil
    response.onSelect = nil
    response.export = nil
    response.event = nil
    response.serverEvent = nil
    response.command = nil

    return response
end

RegisterNUICallback('select', function(data, cb)
    cb(1)

    if data[1] == 'builtin' and data[2] == 'close' then
        state.setNuiFocus(false)
        state.setActive(false)
        return
    end

    local zone = data[3] and nearbyZones[data[3]]

    ---@type OxTargetOption?
    local option = zone and zone.options[data[2]] or options[data[1]][data[2]]

    if option then
        if option.openMenu then
            local menuDepth = #menuHistory

            if option.name == 'builtin:goback' then
                option.menuName = option.openMenu
                option.openMenu = menuHistory[menuDepth]

                if menuDepth > 0 then
                    menuHistory[menuDepth] = nil
                end
            else
                menuHistory[menuDepth + 1] = currentMenu
            end

            menuChanged = true
            currentMenu = option.openMenu ~= 'home' and option.openMenu or nil

            options:wipe()

            if frozenEntity and frozenEntity > 0 and frozenEntityModel then
                options:set(frozenEntity, frozenEntityType, frozenEntityModel)
            end

            if currentMenu and options.__global[1]?.name ~= 'builtin:goback' then
                table.insert(options.__global, 1, {
                    icon = 'fa-solid fa-circle-chevron-left',
                    label = locale('go_back'),
                    name = 'builtin:goback',
                    menuName = currentMenu,
                    openMenu = 'home',
                    me = true
                })
            end

            for k, v in pairs(options) do
                for i = 1, #v do
                    local opt = v[i]
                    opt.hide = shouldHide(opt, 0, currentTarget.coords, frozenEntity, frozenEntityType, frozenEntityModel)
                end
            end

            SendNuiMessage(json.encode({
                event = 'setTarget',
                options = options,
                zones = zones,
            }, { sort_keys = true }))

            return
        else
            state.setNuiFocus(false)
        end

        currentTarget.zone = zone?.id

        if option.onSelect then
            option.onSelect(option.qtarget and currentTarget.entity or getResponse(option))
        elseif option.export then
            exports[option.resource or zone.resource][option.export](nil, getResponse(option))
        elseif option.event then
            TriggerEvent(option.event, getResponse(option))
        elseif option.serverEvent then
            TriggerServerEvent(option.serverEvent, getResponse(option, true))
        elseif option.command then
            ExecuteCommand(option.command)
        end

        if option.menuName == 'home' then return end

        state.setActive(false)
    end

    if not option?.openMenu and IsNuiFocused() then
        state.setActive(false)
    end
end)
