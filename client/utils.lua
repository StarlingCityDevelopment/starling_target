local utils = {}
local lastEntityType = {}

local TEXTURE_DICT, TEXTURE_NAME = 'shared', 'emptydot_32'

local GetControlNormal = GetControlNormal
local GetGameplayCamCoord = GetGameplayCamCoord
local GetGameplayCamRot = GetGameplayCamRot
local GetGameplayCamFov = GetGameplayCamFov
local StartShapeTestRay = StartShapeTestRay
local GetShapeTestResult = GetShapeTestResult
local sqrt, rad, sin, cos, tan = math.sqrt, math.rad, math.sin, math.cos, math.tan

function utils.getTexture()
    return lib.requestStreamedTextureDict(TEXTURE_DICT), TEXTURE_NAME
end

function utils.getCursorScreenPosition()
    return GetControlNormal(0, 239), GetControlNormal(0, 240)
end

function utils.crossProduct(a, b)
    return vector3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
end

function utils.normalizeVector(vec)
    local length = sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    return length > 0 and vector3(vec.x / length, vec.y / length, vec.z / length) or vector3(0, 0, 0)
end

function utils.rotationToDirection(rot)
    local radPitch, radYaw = rad(rot.x), rad(rot.z)
    local cosPitch = cos(radPitch)
    return vector3(
        -sin(radYaw) * cosPitch,
        cos(radYaw) * cosPitch,
        sin(radPitch)
    )
end

function utils.screenToWorld(cursorX, cursorY, screenX, screenY)
    local camPos = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)

    local fovRadians = rad(GetGameplayCamFov()) * 0.5
    local aspectRatio = screenX / screenY
    local tanFov = tan(fovRadians)

    local offsetX = (cursorX - 0.5) * 2.0 * aspectRatio * tanFov
    local offsetY = (0.5 - cursorY) * 2.0 * tanFov

    local forward = utils.rotationToDirection(camRot)
    local right = utils.normalizeVector(utils.crossProduct(forward, vector3(0, 0, 1)))
    local up = utils.normalizeVector(utils.crossProduct(right, forward))

    local direction = utils.normalizeVector(forward + right * offsetX + up * offsetY)
    return camPos, camPos + direction * 1000.0
end

function utils.raycastFromMouse(screenX, screenY)
    local cursorX, cursorY = utils.getCursorScreenPosition()
    local startPos, endPos = utils.screenToWorld(cursorX, cursorY, screenX, screenY)

    local rayHandle = StartShapeTestRay(startPos.x, startPos.y, startPos.z, endPos.x, endPos.y, endPos.z, -1, 0, 4)
    local _, hit, hitCoords, surfaceNormal, hitEntity = GetShapeTestResult(rayHandle)

    local entityType = 0
    if hitEntity ~= 0 then
        if not lastEntityType[hitEntity] then
            local success, result = pcall(GetEntityType, hitEntity)
            lastEntityType[hitEntity] = success and result or 0
        end
        entityType = lastEntityType[hitEntity]
    end

    return hit, hitEntity, hitCoords, surfaceNormal, startPos, endPos, entityType
end

-- SetDrawOrigin is limited to 32 calls per frame. Set as 0 to disable.
local drawZoneSprites = GetConvarInt('ox_target:drawSprite', 24)
local SetDrawOrigin = SetDrawOrigin
local DrawSprite = DrawSprite
local ClearDrawOrigin = ClearDrawOrigin
local colour = vector(155, 155, 155, 175)
local hover = vector(98, 135, 236, 255)
local currentZones = {}
local previousZones = {}
local drawZones = {}
local drawN = 0
local width = 0.02
local height = width * GetAspectRatio(false)

if drawZoneSprites == 0 then drawZoneSprites = -1 end

---@param coords vector3
---@return CZone[], boolean
function utils.getNearbyZones(coords)
    if not Zones then return currentZones, false end

    local n = 0
    local nearbyZones = lib.zones.getNearbyZones()
    drawN = 0
    previousZones, currentZones = currentZones, table.wipe(previousZones)

    for i = 1, #nearbyZones do
        local zone = nearbyZones[i]
        local contains = zone:contains(coords)

        if contains then
            n += 1
            currentZones[n] = zone
        end

        if drawN <= drawZoneSprites and zone.drawSprite ~= false and (contains or (zone.distance or 7) < 7) then
            drawN += 1
            drawZones[drawN] = zone
            zone.colour = contains and hover or nil
        end
    end

    local previousN = #previousZones

    if n ~= previousN then
        return currentZones, true
    end

    if n > 0 then
        for i = 1, n do
            local zoneA = currentZones[i]
            local found = false

            for j = 1, previousN do
                local zoneB = previousZones[j]

                if zoneA == zoneB then
                    found = true
                    break
                end
            end

            if not found then
                return currentZones, true
            end
        end
    end

    return currentZones, false
end

function utils.drawZoneSprites(dict, texture)
    if drawN == 0 then return end

    for i = 1, drawN do
        local zone = drawZones[i]
        local spriteColour = zone.colour or colour

        if zone.drawSprite ~= false then
            SetDrawOrigin(zone.coords.x, zone.coords.y, zone.coords.z)
            DrawSprite(dict, texture, 0, 0, width, height, 0, spriteColour.r, spriteColour.g, spriteColour.b,
                spriteColour.a)
        end
    end

    ClearDrawOrigin()
end

function utils.hasExport(export)
    local resource, exportName = string.strsplit('.', export)

    return pcall(function()
        return exports[resource][exportName]
    end)
end

local playerItems = {}

function utils.getItems()
    return playerItems
end

---@param filter string | string[] | table<string, number>
---@param hasAny boolean?
---@return boolean
function utils.hasPlayerGotItems(filter, hasAny)
    if not playerItems then return true end

    local _type = type(filter)

    if _type == 'string' then
        return (playerItems[filter] or 0) > 0
    elseif _type == 'table' then
        local tabletype = table.type(filter)

        if tabletype == 'hash' then
            for name, amount in pairs(filter) do
                local hasItem = (playerItems[name] or 0) >= amount

                if hasAny then
                    if hasItem then return true end
                elseif not hasItem then
                    return false
                end
            end
        elseif tabletype == 'array' then
            for i = 1, #filter do
                local hasItem = (playerItems[filter[i]] or 0) > 0

                if hasAny then
                    if hasItem then return true end
                elseif not hasItem then
                    return false
                end
            end
        end
    end

    return not hasAny
end

---stub
---@param filter string | string[] | table<string, number>
---@return boolean
function utils.hasPlayerGotGroup(filter)
    return true
end

SetTimeout(0, function()
    if utils.hasExport('ox_inventory.Items') then
        setmetatable(playerItems, {
            __index = function(self, index)
                self[index] = exports.ox_inventory:Search('count', index) or 0
                return self[index]
            end
        })

        AddEventHandler('ox_inventory:itemCount', function(name, count)
            playerItems[name] = count
        end)
    end

    if utils.hasExport('ox_core.GetPlayer') then
        require 'client.framework.ox'
    elseif utils.hasExport('es_extended.getSharedObject') then
        require 'client.framework.esx'
    elseif utils.hasExport('qbx_core.HasGroup') then
        require 'client.framework.qbx'
    elseif utils.hasExport('ND_Core.getPlayer') then
        require 'client.framework.nd'
    end
end)

function utils.warn(msg)
    local trace = Citizen.InvokeNative(`FORMAT_STACK_TRACE` & 0xFFFFFFFF, nil, 0, Citizen.ResultAsString())
    local _, _, src = string.strsplit('\n', trace, 4)

    warn(('%s ^0%s\n'):format(msg, src:gsub(".-%(", '(')))
end

return utils
