local api = require 'client.api'

api.addGlobalPlayer({
    {
        me = true,
        name = 'player:copy:id',
        icon = 'fa-solid fa-user',
        label = "Copier l'ID du joueur",
        distance = 3.0,
        onSelect = function(data)
            local playerId = NetworkGetPlayerIndexFromPed(data.entity)
            if playerId == -1 then return end
            local value = GetPlayerServerId(playerId)
            if value == -1 then return end
            lib.setClipboard(value)
        end
    }
})

api.addGlobalVehicle({
    {
        name = 'vehicle:menu',
        icon = 'fa-solid fa-car',
        label = "Menu véhicule",
        distance = 2.0,
        canInteract = function(entity)
            return cache.vehicle and entity == cache.vehicle
        end,
        onSelect = function(data)
            exports.bl_vehiclemenu:OpenMenu()
        end
    }
})
