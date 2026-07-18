local menuOpen = false
local inputBlockerRunning = false
local spawnedVehicle = nil
local spawnedModel = nil
local serverVehicles = {}
local validatedVehicles = {}
local validatedVehicleByModel = {}
local catalogueValidationToken = 0
local catalogueStats = { total = 0, base = 0, addon = 0, manual = 0 }
local confirmedTuning = {}
local savedSetup = nil
local stockVisualSetup = nil
local tuningPreviewBusy = false
local presetBusy = false
local cameraBusy = false
local extrasBusy = false
local tuningCamera = nil
local cameraFocusId = 'general'
local cameraOrbit = 0.0
local cameraHeight = 0.0
local cameraZoom = 0.0
local cameraGeneration = 0
local captureVehicleSetup

local modCategories = {
    spoiler = { label = 'Spoiler', modType = 0 },
    front_bumper = { label = 'Front Bumper', modType = 1 },
    rear_bumper = { label = 'Rear Bumper', modType = 2 },
    side_skirts = { label = 'Side Skirts', modType = 3 },
    exhaust = { label = 'Exhaust', modType = 4 },
    frame = { label = 'Frame', modType = 5 },
    grille = { label = 'Grille', modType = 6 },
    hood = { label = 'Hood', modType = 7 },
    fenders = { label = 'Fenders', modType = 8 },
    roof = { label = 'Roof', modType = 10 },
    engine = { label = 'Engine', modType = 11 },
    brakes = { label = 'Brakes', modType = 12 },
    transmission = { label = 'Transmission', modType = 13 },
    horn = { label = 'Horn', modType = 14 },
    suspension = { label = 'Suspension', modType = 15 },
    armour = { label = 'Armour', modType = 16 },
    wheels = { label = 'Wheels', modType = 23 }
}

local categoryOrder = {
    'spoiler', 'front_bumper', 'rear_bumper', 'side_skirts', 'exhaust',
    'frame', 'grille', 'hood', 'fenders', 'roof', 'engine', 'brakes',
    'transmission', 'suspension', 'armour', 'horn', 'wheels'
}

local performanceModTypes = { 11, 12, 13, 15, 16 }
local toggleModTypes = { 17, 18, 19, 20, 21, 22 }
local wheelTypeNames = {
    [0] = 'Sport', [1] = 'Muscle', [2] = 'Lowrider', [3] = 'SUV',
    [4] = 'Off-road', [5] = 'Tuner', [6] = 'Motorcycle', [7] = 'High End',
    [8] = "Benny's Original", [9] = "Benny's Bespoke", [10] = 'Open Wheel',
    [11] = 'Street', [12] = 'Track'
}

local cameraFocusAreas = {
    general = { target = { 0.0, 0.0, 0.65 }, angle = 35.0, distance = 5.8, height = 1.7 },
    spoiler = { target = { 0.0, -1.65, 1.05 }, angle = 180.0, distance = 3.5, height = 1.25 },
    front_bumper = { target = { 0.0, 1.75, 0.35 }, angle = 0.0, distance = 3.4, height = 0.65 },
    rear_bumper = { target = { 0.0, -1.75, 0.35 }, angle = 180.0, distance = 3.4, height = 0.65 },
    side_skirts = { target = { 1.0, 0.0, 0.2 }, angle = 90.0, distance = 3.7, height = 0.55 },
    exhaust = { target = { 0.45, -1.7, 0.18 }, angle = 180.0, distance = 3.0, height = 0.45 },
    grille = { target = { 0.0, 1.65, 0.55 }, angle = 0.0, distance = 3.1, height = 0.75 },
    hood = { target = { 0.0, 0.9, 0.8 }, angle = 20.0, distance = 3.8, height = 1.35 },
    fenders = { target = { 0.85, 0.9, 0.55 }, angle = 55.0, distance = 3.5, height = 0.9 },
    roof = { target = { 0.0, 0.0, 1.25 }, angle = 35.0, distance = 4.0, height = 2.05 },
    wheels = { target = { 0.9, 0.65, 0.25 }, angle = 75.0, distance = 3.3, height = 0.55 }
}

local function debugLog(message, ...)
    if Config.Debug ~= true then return end
    if select('#', ...) > 0 then
        message = message:format(...)
    end
    print(('[car_tester] %s'):format(message))
end

local function isInteger(value)
    return type(value) == 'number' and value == math.floor(value)
end

local function trim(value)
    if type(value) ~= 'string' then return '' end
    return value:match('^%s*(.-)%s*$') or ''
end

local function validModelName(model)
    return type(model) == 'string' and #model > 0 and #model <= 64
        and model:match('^[%w_%-]+$') ~= nil
end

local function resolveTextLabel(label)
    label = trim(label)
    if label == '' or label == 'NULL' then return nil end
    local translated = GetLabelText(label)
    if translated and translated ~= '' and translated ~= 'NULL' and translated ~= label then
        return translated
    end
    return nil
end

local function formatModelName(model)
    local formatted = model:gsub('[_%-]+', ' ')
    return (formatted:gsub('(%a)([%w]*)', function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

local function success(message, state)
    local response = { success = true }
    if message then response.message = message end
    if state then response.state = state end
    return response
end

local function failure(message, state)
    local response = { success = false, error = message }
    if state then response.state = state end
    return response
end

local function getVehicle()
    if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
        return spawnedVehicle
    end

    spawnedVehicle = nil
    spawnedModel = nil
    return nil
end

local function destroyTuningCamera()
    cameraGeneration = cameraGeneration + 1
    local camera = tuningCamera
    tuningCamera = nil
    if camera and DoesCamExist(camera) then
        RenderScriptCams(false, true, 300, true, true)
        if DoesCamExist(camera) then DestroyCam(camera, false) end
    end
    cameraBusy = false
end

local function cameraAreaForCategory(category)
    if category == 'wheel_type' then return cameraFocusAreas.wheels, 'wheels' end
    if category == 'window_tint' or category == 'turbo' then return cameraFocusAreas.general, 'general' end
    if category == 'engine' or category == 'brakes' or category == 'transmission'
        or category == 'suspension' or category == 'armour' or category == 'horn'
        or category == 'frame' then
        return cameraFocusAreas.general, 'general'
    end
    return cameraFocusAreas[category] or cameraFocusAreas.general,
        cameraFocusAreas[category] and category or 'general'
end

local function focusTuningCamera(category, resetControls)
    if Config.AutoTuningCamera ~= true then return false, 'Automatic tuning camera is disabled.' end
    if cameraBusy then return false, 'The tuning camera is busy.' end

    local vehicle = getVehicle()
    if not vehicle or not DoesEntityExist(vehicle) then return false, 'No test vehicle exists.' end
    if type(category) ~= 'string' or #category > 32 then return false, 'Invalid camera focus area.' end

    cameraBusy = true
    if resetControls == true then
        cameraOrbit, cameraHeight, cameraZoom = 0.0, 0.0, 0.0
    end
    local area, resolvedId = cameraAreaForCategory(category)
    cameraFocusId = resolvedId
    if not DoesEntityExist(vehicle) then cameraBusy = false return false, 'No test vehicle exists.' end
    local target = GetOffsetFromEntityInWorldCoords(vehicle, area.target[1], area.target[2], area.target[3])
    if not target or not DoesEntityExist(vehicle) then cameraBusy = false return false, 'The camera target is unavailable.' end

    local heading = GetEntityHeading(vehicle)
    local angle = math.rad(heading + area.angle + cameraOrbit)
    local distance = math.max(2.2, math.min(8.0, area.distance + cameraZoom))
    local x = target.x + math.sin(angle) * distance
    local y = target.y + math.cos(angle) * distance
    local z = target.z + area.height + cameraHeight
    local newCamera = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', x, y, z, 0.0, 0.0, 0.0, 48.0, true, 2)
    if not newCamera or not DoesCamExist(newCamera) then
        cameraBusy = false
        return false, 'The tuning camera could not be created.'
    end
    if not DoesEntityExist(vehicle) or not DoesCamExist(newCamera) then
        if DoesCamExist(newCamera) then DestroyCam(newCamera, false) end
        cameraBusy = false
        return false, 'The camera target is no longer available.'
    end
    PointCamAtCoord(newCamera, target.x, target.y, target.z)

    local oldCamera = tuningCamera
    tuningCamera = newCamera
    cameraGeneration = cameraGeneration + 1
    local generation = cameraGeneration
    if oldCamera and DoesCamExist(oldCamera) then
        SetCamActiveWithInterp(newCamera, oldCamera, 350, 1, 1)
    else
        RenderScriptCams(true, true, 350, true, true)
    end

    CreateThread(function()
        Wait(400)
        if oldCamera and oldCamera ~= tuningCamera and DoesCamExist(oldCamera) then
            DestroyCam(oldCamera, false)
        end
        if generation == cameraGeneration then cameraBusy = false end
    end)
    debugLog('Camera focused on %s', resolvedId)
    return true
end

local function getConfiguredVehicle(model)
    if type(model) ~= 'string' or #model == 0 or #model > 64 then
        return nil
    end
    return validatedVehicleByModel[string.lower(model)]
end

local function nuiVehicles()
    local vehicles = {}
    for _, entry in ipairs(validatedVehicles) do
        vehicles[#vehicles + 1] = {
            model = entry.model,
            label = entry.label,
            manufacturer = entry.manufacturer,
            category = entry.category,
            resource = entry.resource,
            sourceType = entry.sourceType
        }
    end
    return vehicles
end

local function resolveVehicleLabel(entry, hash)
    local displayKey = GetDisplayNameFromVehicleModel(hash)
    local displayName = resolveTextLabel(displayKey)
    if displayName then return displayName end

    local metadataName = resolveTextLabel(entry.gameName)
    if metadataName then return metadataName end
    if trim(entry.gameName) ~= '' and entry.gameName ~= 'NULL' then return entry.gameName end
    if trim(entry.label) ~= '' and entry.sourceType ~= 'addon' then return entry.label end

    local formatted = formatModelName(entry.model)
    return formatted ~= '' and formatted or entry.model
end

local function resolveManufacturer(entry, hash)
    local ok, makeLabel = pcall(GetMakeNameFromVehicleModel, hash)
    if ok then
        local makeName = resolveTextLabel(makeLabel)
        if makeName then return makeName end
    end

    local metadataMake = resolveTextLabel(entry.manufacturer)
    if metadataMake then return metadataMake end
    local rawMake = trim(entry.manufacturer)
    return rawMake ~= '' and rawMake or nil
end

local function addCatalogueCandidate(candidates, seen, entry, sourceType)
    if type(entry) ~= 'table' then return end
    local model = trim(entry.model):lower()
    if not validModelName(model) then return end

    local existing = seen[model]
    if existing then
        -- Base-game replacements retain their normal GTA entry, but detected
        -- metadata may still improve a missing make/game label.
        if not existing.gameName and type(entry.gameName) == 'string' then existing.gameName = entry.gameName end
        if not existing.manufacturer and type(entry.manufacturer) == 'string' then
            existing.manufacturer = entry.manufacturer
        end
        return
    end

    local candidate = {
        model = model,
        label = trim(entry.label),
        gameName = trim(entry.gameName),
        manufacturer = trim(entry.manufacturer),
        handlingId = trim(entry.handlingId),
        category = trim(entry.category),
        resource = trim(entry.resource),
        sourceType = sourceType,
        supported = entry.supported ~= false
    }
    if candidate.category == '' then candidate.category = sourceType == 'base' and 'Base Game' or 'Add-on' end
    if candidate.resource == '' then candidate.resource = sourceType == 'base' and 'Base Game' or 'manual' end
    seen[model] = candidate
    candidates[#candidates + 1] = candidate
end

local function rebuildValidatedCatalogue()
    catalogueValidationToken = catalogueValidationToken + 1
    local token = catalogueValidationToken

    CreateThread(function()
        local candidates, seen = {}, {}
        if Config.IncludeBaseVehicles ~= false and type(BaseVehicles) == 'table' then
            for _, entry in ipairs(BaseVehicles) do addCatalogueCandidate(candidates, seen, entry, 'base') end
        end
        for _, entry in ipairs(serverVehicles) do addCatalogueCandidate(candidates, seen, entry, 'addon') end
        if type(Config.ManualVehicles) == 'table' then
            for _, entry in ipairs(Config.ManualVehicles) do addCatalogueCandidate(candidates, seen, entry, 'manual') end
        end

        local vehicles, byModel = {}, {}
        local stats = { total = 0, base = 0, addon = 0, manual = 0 }
        for index, entry in ipairs(candidates) do
            if token ~= catalogueValidationToken then return end
            if entry.supported then
                local hash = joaat(entry.model)
                if IsModelInCdimage(hash) and IsModelValid(hash) and IsModelAVehicle(hash) then
                    local vehicle = {
                        model = entry.model,
                        label = resolveVehicleLabel(entry, hash),
                        manufacturer = resolveManufacturer(entry, hash),
                        category = entry.category,
                        resource = entry.resource,
                        sourceType = entry.sourceType,
                        handlingId = entry.handlingId ~= '' and entry.handlingId or nil
                    }
                    vehicles[#vehicles + 1] = vehicle
                    byModel[entry.model] = vehicle
                    stats.total = stats.total + 1
                    stats[entry.sourceType] = (stats[entry.sourceType] or 0) + 1
                end
            end
            if index % 40 == 0 then Wait(0) end
        end

        table.sort(vehicles, function(left, right)
            local leftName = (left.label or left.model):lower()
            local rightName = (right.label or right.model):lower()
            return leftName == rightName and left.model < right.model or leftName < rightName
        end)
        if token ~= catalogueValidationToken then return end

        validatedVehicles = vehicles
        validatedVehicleByModel = byModel
        catalogueStats = stats
        debugLog(
            'client catalogue validated: total=%d base=%d addon=%d manual=%d',
            stats.total, stats.base, stats.addon, stats.manual
        )
        SendNUIMessage({ action = 'catalogue', vehicles = nuiVehicles(), stats = catalogueStats })
    end)
end

local function readableModName(vehicle, modType, modIndex)
    local label = GetModTextLabel(vehicle, modType, modIndex)
    if label and label ~= '' then
        local translated = GetLabelText(label)
        if translated and translated ~= '' and translated ~= 'NULL' then
            return translated
        end
    end

    return ('Option %d'):format(modIndex + 1)
end

local function buildTuningState(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return {} end
    SetVehicleModKit(vehicle, 0)
    local categories = {}

    for _, id in ipairs(categoryOrder) do
        local definition = modCategories[id]
        local count = GetNumVehicleMods(vehicle, definition.modType)
        if count and count > 0 then
            if id == 'wheels' then
                local wheelTypes = {}
                for index = 0, 12 do
                    wheelTypes[#wheelTypes + 1] = { index = index, label = wheelTypeNames[index] }
                end
                categories[#categories + 1] = {
                    id = 'wheel_type',
                    label = 'Wheel Type',
                    kind = 'select',
                    value = GetVehicleWheelType(vehicle),
                    confirmed = confirmedTuning.wheel_type,
                    options = wheelTypes
                }
            end

            local options = { { index = -1, label = 'Stock' } }
            for index = 0, count - 1 do
                options[#options + 1] = {
                    index = index,
                    label = readableModName(vehicle, definition.modType, index)
                }
            end

            categories[#categories + 1] = {
                id = id,
                label = definition.label,
                kind = 'select',
                value = GetVehicleMod(vehicle, definition.modType),
                confirmed = confirmedTuning[id],
                options = options
            }
        end
    end

    local tintCount = tonumber(GetNumVehicleWindowTints()) or 0
    if tintCount and tintCount > 0 then
        local tintNames = {
            [0] = 'None', [1] = 'Pure Black', [2] = 'Dark Smoke',
            [3] = 'Light Smoke', [4] = 'Stock', [5] = 'Limo', [6] = 'Green'
        }
        local options = { { index = -1, label = 'Stock' } }
        for index = 0, tintCount - 1 do
            options[#options + 1] = {
                index = index,
                label = tintNames[index] or ('Option %d'):format(index + 1)
            }
        end
        categories[#categories + 1] = {
            id = 'window_tint',
            label = 'Window Tint',
            kind = 'select',
            value = GetVehicleWindowTint(vehicle),
            confirmed = confirmedTuning.window_tint,
            options = options
        }
    end

    if GetNumVehicleMods(vehicle, 18) > 0 then
        categories[#categories + 1] = {
            id = 'turbo',
            label = 'Turbo',
            kind = 'select',
            value = IsToggleModOn(vehicle, 18) and 0 or -1,
            confirmed = confirmedTuning.turbo,
            options = {
                { index = -1, label = 'Stock' },
                { index = 0, label = 'Enabled' }
            }
        }
    end

    for _, category in ipairs(categories) do
        if category.confirmed == nil then
            category.confirmed = category.value
            confirmedTuning[category.id] = category.value
        end
    end

    return categories
end

local function buildExtrasState(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return {} end
    local extras = {}
    -- Extras are sparse on many add-on vehicles, so scan and expose only IDs that exist.
    for extraId = 0, 50 do
        if DoesEntityExist(vehicle) and DoesExtraExist(vehicle, extraId) then
            if not DoesEntityExist(vehicle) then return extras end
            extras[#extras + 1] = {
                id = extraId,
                enabled = IsVehicleExtraTurnedOn(vehicle, extraId)
            }
        end
    end
    return extras
end

local function buildLiveryState(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then
        return { available = false, implementation = 'none', count = 0, index = -1 }
    end
    SetVehicleModKit(vehicle, 0)
    local nativeCount = GetVehicleLiveryCount(vehicle)
    local modCount = GetNumVehicleMods(vehicle, 48)

    if nativeCount and nativeCount > 0 then
        return {
            available = true,
            implementation = 'native',
            count = nativeCount,
            index = GetVehicleLivery(vehicle)
        }
    end

    if modCount and modCount > 0 then
        return {
            available = true,
            implementation = 'mod-slot 48',
            count = modCount,
            index = GetVehicleMod(vehicle, 48)
        }
    end

    return { available = false, implementation = 'none', count = 0, index = -1 }
end

local function buildVehicleState()
    local vehicle = getVehicle()
    if not vehicle then
        return {
            hasVehicle = false,
            model = nil,
            liveries = { available = false, implementation = 'none', count = 0, index = -1 },
            tuning = {},
            extras = {},
            cameraEnabled = Config.AutoTuningCamera == true
        }
    end

    local primaryRed, primaryGreen, primaryBlue = GetVehicleCustomPrimaryColour(vehicle)
    local secondaryRed, secondaryGreen, secondaryBlue = GetVehicleCustomSecondaryColour(vehicle)

    return {
        hasVehicle = true,
        model = spawnedModel,
        paint = {
            primary = { r = primaryRed, g = primaryGreen, b = primaryBlue },
            secondary = { r = secondaryRed, g = secondaryGreen, b = secondaryBlue },
            primaryCustom = GetIsVehiclePrimaryColourCustom(vehicle),
            secondaryCustom = GetIsVehicleSecondaryColourCustom(vehicle)
        },
        liveries = buildLiveryState(vehicle),
        tuning = buildTuningState(vehicle),
        extras = buildExtrasState(vehicle),
        cameraEnabled = Config.AutoTuningCamera == true
    }
end

local function sendState()
    SendNUIMessage({ action = 'vehicleState', state = buildVehicleState() })
end

local function startInputBlocker()
    if inputBlockerRunning then return end
    inputBlockerRunning = true
    CreateThread(function()
        while menuOpen do
            -- Prevent accidental combat/vehicle actions while the development UI has focus.
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 75, true)
            Wait(0)
        end
        inputBlockerRunning = false
    end)
end

local function setMenuOpen(open)
    open = open == true
    if open == menuOpen then return end

    menuOpen = open
    SetNuiFocus(open, open)
    if open then
        SendNUIMessage({
            action = 'open',
            vehicles = nuiVehicles(),
            stats = catalogueStats,
            state = buildVehicleState()
        })
        startInputBlocker()
        debugLog('menu opened')
    else
        destroyTuningCamera()
        SendNUIMessage({ action = 'close', clear = false })
        debugLog('menu closed')
    end
end

local function forceCloseMenu(clearState)
    menuOpen = false
    destroyTuningCamera()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close', clear = clearState == true })
    debugLog('menu force-closed')
end

local function deleteTrackedVehicle()
    local vehicle = getVehicle()
    if not vehicle then
        return false, 'No test vehicle exists.'
    end

    destroyTuningCamera()
    if NetworkGetEntityIsNetworked(vehicle) and not NetworkHasControlOfEntity(vehicle) then
        NetworkRequestControlOfEntity(vehicle)
        local deadline = GetGameTimer() + 750
        while DoesEntityExist(vehicle) and not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < deadline do
            Wait(0)
            NetworkRequestControlOfEntity(vehicle)
        end
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)
    if DoesEntityExist(vehicle) then
        DeleteEntity(vehicle)
    end

    if DoesEntityExist(vehicle) then
        debugLog('vehicle deletion failed for entity %s', vehicle)
        return false, 'The test vehicle could not be deleted.'
    end

    spawnedVehicle = nil
    spawnedModel = nil
    confirmedTuning = {}
    stockVisualSetup = nil
    debugLog('vehicle entity %s deleted', vehicle)
    return true, 'Test vehicle deleted.'
end

local function loadVehicleModel(model)
    local hash = joaat(model)
    local inCdImage = IsModelInCdimage(hash)
    local valid = IsModelValid(hash)
    local isVehicle = IsModelAVehicle(hash)
    debugLog('model validation %s: cdimage=%s valid=%s vehicle=%s', model, inCdImage, valid, isVehicle)
    if not inCdImage or not valid or not isVehicle then
        return nil, ('Model "%s" is invalid or is not streamed.'):format(model)
    end

    RequestModel(hash)
    local deadline = GetGameTimer() + math.max(1000, tonumber(Config.ModelLoadTimeout) or 10000)
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do
        Wait(0)
    end

    if not HasModelLoaded(hash) then
        SetModelAsNoLongerNeeded(hash)
        debugLog('model loading timed out for %s', model)
        return nil, ('Model "%s" could not be loaded.'):format(model)
    end

    return hash
end

local function spawnConfiguredVehicle(entry)
    if not NetworkIsSessionStarted() then
        return false, 'The network session is not ready yet. Try again after spawning into the world.'
    end

    local playerPed = PlayerPedId()
    if not playerPed or playerPed == 0 or not DoesEntityExist(playerPed) then
        return false, 'The player entity is not ready yet.'
    end

    debugLog('requested model %s', entry.model)
    local hash, loadError = loadVehicleModel(entry.model)
    if not hash then
        return false, loadError
    end

    if getVehicle() then
        local deleted, deleteError = deleteTrackedVehicle()
        if not deleted then
            SetModelAsNoLongerNeeded(hash)
            return false, deleteError
        end
    end

    local distance = tonumber(Config.SpawnDistance) or 5.0
    local coords = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, distance, 0.5)
    local heading = GetEntityHeading(playerPed)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, false)
    SetModelAsNoLongerNeeded(hash)

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false, ('Model "%s" loaded, but the vehicle could not be created.'):format(entry.model)
    end

    spawnedVehicle = vehicle
    spawnedModel = entry.model
    confirmedTuning = {}
    stockVisualSetup = nil
    SetEntityAsMissionEntity(vehicle, true, true)
    Wait(0)
    if not DoesEntityExist(vehicle) then
        spawnedVehicle = nil
        spawnedModel = nil
        return false, ('Vehicle "%s" disappeared while it was being created.'):format(entry.model)
    end

    SetVehicleModKit(vehicle, 0)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetPedIntoVehicle(playerPed, vehicle, -1)
    buildTuningState(vehicle)
    if captureVehicleSetup then stockVisualSetup = captureVehicleSetup(vehicle) end
    debugLog('created vehicle entity %s for model %s', vehicle, entry.model)

    return true, ('Spawned %s.'):format(entry.model)
end

local function withVehicle(respond, action)
    local vehicle = getVehicle()
    if not vehicle then
        respond(failure('No test vehicle exists.', buildVehicleState()))
        return
    end

    action(vehicle)
end

-- Wrap callbacks so every browser request receives a response, including Lua errors.
local function registerSafeCallback(name, handler)
    RegisterNUICallback(name, function(data, cb)
        local responded = false
        local function respond(payload)
            if responded then return end
            responded = true
            cb(payload or success())
        end

        local ok, err = xpcall(function()
            handler(type(data) == 'table' and data or {}, respond)
        end, debug.traceback)

        if not ok then
            tuningPreviewBusy = false
            presetBusy = false
            extrasBusy = false
            cameraBusy = false
            print(('[car_tester] NUI callback "%s" failed: %s'):format(name, err))
            respond(failure('The requested action failed. Check the client console.'))
        elseif not responded then
            respond(failure('The requested action returned no result.'))
        end
    end)
end

local function findTuningCategory(vehicle, categoryId)
    if not vehicle or not DoesEntityExist(vehicle) then return nil end
    for _, category in ipairs(buildTuningState(vehicle)) do
        if category.id == categoryId then return category end
    end
    return nil
end

local function categoryHasIndex(category, index)
    if not category or not isInteger(index) or type(category.options) ~= 'table' then return false end
    for _, option in ipairs(category.options) do
        if option.index == index then return true end
    end
    return false
end

local function applyTuningValue(vehicle, categoryId, index)
    if not vehicle or not DoesEntityExist(vehicle) then return false, 'No test vehicle exists.' end
    if type(categoryId) ~= 'string' or #categoryId > 32 or not isInteger(index) then
        return false, 'Invalid modification request.'
    end
    if not DoesEntityExist(vehicle) then return false, 'No test vehicle exists.' end
    SetVehicleModKit(vehicle, 0)
    local category = findTuningCategory(vehicle, categoryId)
    if not category or not categoryHasIndex(category, index) then
        return false, 'The selected modification is unavailable.'
    end
    if not DoesEntityExist(vehicle) then return false, 'No test vehicle exists.' end

    if categoryId == 'turbo' then
        ToggleVehicleMod(vehicle, 18, index == 0)
    elseif categoryId == 'wheel_type' then
        SetVehicleWheelType(vehicle, index)
    elseif categoryId == 'window_tint' then
        SetVehicleWindowTint(vehicle, index)
    else
        local definition = modCategories[categoryId]
        if not definition then return false, 'Invalid modification category.' end
        if not DoesEntityExist(vehicle) then return false, 'No test vehicle exists.' end
        local count = GetNumVehicleMods(vehicle, definition.modType)
        if index < -1 or index >= count then return false, 'The selected modification is unavailable.' end
        if not DoesEntityExist(vehicle) then return false, 'No test vehicle exists.' end
        SetVehicleMod(vehicle, definition.modType, index, false)
    end
    return true
end

local function refreshConfirmedTuning(vehicle)
    confirmedTuning = {}
    if not vehicle or not DoesEntityExist(vehicle) then return end
    for _, category in ipairs(buildTuningState(vehicle)) do
        confirmedTuning[category.id] = category.value
    end
end

captureVehicleSetup = function(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return nil end
    SetVehicleModKit(vehicle, 0)
    if not DoesEntityExist(vehicle) then return nil end
    local pr, pg, pb = GetVehicleCustomPrimaryColour(vehicle)
    if not DoesEntityExist(vehicle) then return nil end
    local sr, sg, sb = GetVehicleCustomSecondaryColour(vehicle)
    if not DoesEntityExist(vehicle) then return nil end
    local pearl, wheelColour = GetVehicleExtraColours(vehicle)
    local setup = {
        version = 1,
        model = spawnedModel,
        primary = { r = pr, g = pg, b = pb, custom = GetIsVehiclePrimaryColourCustom(vehicle) },
        secondary = { r = sr, g = sg, b = sb, custom = GetIsVehicleSecondaryColourCustom(vehicle) },
        pearlescent = pearl,
        wheelColour = wheelColour,
        wheelType = GetVehicleWheelType(vehicle),
        wheelMod = GetVehicleMod(vehicle, 23),
        windowTint = GetVehicleWindowTint(vehicle),
        mods = {},
        toggles = {},
        extras = {}
    }

    for modType = 0, 49 do
        if not DoesEntityExist(vehicle) then return nil end
        if modType < 17 or modType > 22 then
            local count = GetNumVehicleMods(vehicle, modType)
            if count and count > 0 then
                setup.mods[#setup.mods + 1] = { type = modType, index = GetVehicleMod(vehicle, modType) }
            end
        end
    end
    for _, modType in ipairs(toggleModTypes) do
        if not DoesEntityExist(vehicle) then return nil end
        if GetNumVehicleMods(vehicle, modType) > 0 then
            setup.toggles[#setup.toggles + 1] = { type = modType, enabled = IsToggleModOn(vehicle, modType) }
        end
    end

    if not DoesEntityExist(vehicle) then return nil end
    local nativeCount = GetVehicleLiveryCount(vehicle)
    if nativeCount and nativeCount > 0 then setup.nativeLivery = GetVehicleLivery(vehicle) end
    if not DoesEntityExist(vehicle) then return nil end
    local modLiveryCount = GetNumVehicleMods(vehicle, 48)
    if modLiveryCount and modLiveryCount > 0 then setup.modSlot48Livery = GetVehicleMod(vehicle, 48) end
    setup.extras = buildExtrasState(vehicle)
    return setup
end

local function validColourChannel(value)
    return isInteger(value) and value >= 0 and value <= 255
end

local function applySetup(vehicle, setup, visualsOnly)
    if not vehicle or not DoesEntityExist(vehicle) or type(setup) ~= 'table' then
        return false, 'The saved setup is invalid.'
    end
    if setup.model ~= spawnedModel then return false, 'The saved setup belongs to a different vehicle model.' end
    if not DoesEntityExist(vehicle) then return false, 'No test vehicle exists.' end
    SetVehicleModKit(vehicle, 0)

    local visualModTypes = {
        [0] = true, [1] = true, [2] = true, [3] = true, [4] = true,
        [5] = true, [6] = true, [7] = true, [8] = true, [9] = true,
        [10] = true, [23] = true
    }
    if type(setup.mods) == 'table' then
        for _, item in ipairs(setup.mods) do
            if not DoesEntityExist(vehicle) then return false, 'No test vehicle exists.' end
            if type(item) == 'table' and isInteger(item.type) and item.type >= 0 and item.type <= 49
                and item.type ~= 48 and (not visualsOnly or visualModTypes[item.type]) then
                local count = GetNumVehicleMods(vehicle, item.type)
                if isInteger(item.index) and item.index >= -1 and item.index < count then
                    if DoesEntityExist(vehicle) then SetVehicleMod(vehicle, item.type, item.index, false) end
                end
            end
        end
    end

    if not visualsOnly and type(setup.toggles) == 'table' then
        for _, item in ipairs(setup.toggles) do
            if not DoesEntityExist(vehicle) then return false, 'No test vehicle exists.' end
            if type(item) == 'table' and isInteger(item.type) and item.type >= 17 and item.type <= 22
                and type(item.enabled) == 'boolean' and GetNumVehicleMods(vehicle, item.type) > 0 then
                if DoesEntityExist(vehicle) then ToggleVehicleMod(vehicle, item.type, item.enabled) end
            end
        end
    end

    if isInteger(setup.wheelType) and setup.wheelType >= 0 and setup.wheelType <= 12
        and DoesEntityExist(vehicle) and GetNumVehicleMods(vehicle, 23) > 0 then
        SetVehicleWheelType(vehicle, setup.wheelType)
        if isInteger(setup.wheelMod) then
            local wheelCount = GetNumVehicleMods(vehicle, 23)
            if setup.wheelMod >= -1 and setup.wheelMod < wheelCount and DoesEntityExist(vehicle) then
                SetVehicleMod(vehicle, 23, setup.wheelMod, false)
            end
        end
    end

    if type(setup.primary) == 'table' and validColourChannel(setup.primary.r)
        and validColourChannel(setup.primary.g) and validColourChannel(setup.primary.b) and DoesEntityExist(vehicle) then
        if setup.primary.custom == false then ClearVehicleCustomPrimaryColour(vehicle)
        else SetVehicleCustomPrimaryColour(vehicle, setup.primary.r, setup.primary.g, setup.primary.b) end
    end
    if type(setup.secondary) == 'table' and validColourChannel(setup.secondary.r)
        and validColourChannel(setup.secondary.g) and validColourChannel(setup.secondary.b) and DoesEntityExist(vehicle) then
        if setup.secondary.custom == false then ClearVehicleCustomSecondaryColour(vehicle)
        else SetVehicleCustomSecondaryColour(vehicle, setup.secondary.r, setup.secondary.g, setup.secondary.b) end
    end
    if isInteger(setup.pearlescent) and setup.pearlescent >= 0 and setup.pearlescent <= 255
        and isInteger(setup.wheelColour) and setup.wheelColour >= 0 and setup.wheelColour <= 255
        and DoesEntityExist(vehicle) then
        SetVehicleExtraColours(vehicle, setup.pearlescent, setup.wheelColour)
    end

    if not visualsOnly and isInteger(setup.windowTint) and setup.windowTint >= -1
        and setup.windowTint < (tonumber(GetNumVehicleWindowTints()) or 0) and DoesEntityExist(vehicle) then
        SetVehicleWindowTint(vehicle, setup.windowTint)
    end

    if DoesEntityExist(vehicle) then
        local nativeCount = GetVehicleLiveryCount(vehicle)
        if nativeCount and nativeCount > 0 and isInteger(setup.nativeLivery)
            and setup.nativeLivery >= 0 and setup.nativeLivery < nativeCount then
            SetVehicleLivery(vehicle, setup.nativeLivery)
        elseif nativeCount <= 0 and isInteger(setup.modSlot48Livery) then
            local modCount = GetNumVehicleMods(vehicle, 48)
            if setup.modSlot48Livery >= -1 and setup.modSlot48Livery < modCount and DoesEntityExist(vehicle) then
                SetVehicleMod(vehicle, 48, setup.modSlot48Livery, false)
            end
        end
    end

    if not visualsOnly and type(setup.extras) == 'table' then
        for _, extra in ipairs(setup.extras) do
            if not DoesEntityExist(vehicle) then return false, 'No test vehicle exists.' end
            if type(extra) == 'table' and isInteger(extra.id) and extra.id >= 0 and extra.id <= 50
                and type(extra.enabled) == 'boolean' and DoesExtraExist(vehicle, extra.id) then
                if DoesEntityExist(vehicle) then SetVehicleExtra(vehicle, extra.id, not extra.enabled) end
            end
        end
    end
    return true
end

registerSafeCallback('ready', function(_, respond)
    respond({
        success = true,
        vehicles = nuiVehicles(),
        stats = catalogueStats,
        state = buildVehicleState()
    })
end)

registerSafeCallback('refreshCatalogue', function(_, respond)
    TriggerServerEvent('car_tester:server:requestCatalogue')
    respond(success('Vehicle catalogue refresh requested.'))
end)

registerSafeCallback('close', function(_, respond)
    setMenuOpen(false)
    respond(success())
end)

registerSafeCallback('spawnVehicle', function(data, respond)
    local entry = getConfiguredVehicle(data.model)
    if not entry then
        debugLog('rejected unconfigured model request: %s', tostring(data.model))
        respond(failure('The selected vehicle is not available in the current validated catalogue.'))
        return
    end

    local ok, message = spawnConfiguredVehicle(entry)
    local state = buildVehicleState()
    sendState()
    respond(ok and success(message, state) or failure(message, state))
end)

registerSafeCallback('deleteVehicle', function(_, respond)
    local ok, message = deleteTrackedVehicle()
    local state = buildVehicleState()
    sendState()
    respond(ok and success(message, state) or failure(message, state))
end)

registerSafeCallback('repairVehicle', function(_, respond)
    withVehicle(respond, function(vehicle)
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        respond(success('Vehicle repaired.', buildVehicleState()))
    end)
end)

registerSafeCallback('cleanVehicle', function(_, respond)
    local vehicle = getVehicle()
    local function isTrackedVehicleValid()
        return vehicle ~= nil and vehicle ~= 0
            and spawnedVehicle == vehicle and DoesEntityExist(vehicle)
    end

    if not isTrackedVehicleValid() then
        respond(failure('No test vehicle exists.'))
        return
    end

    WashDecalsFromVehicle(vehicle, 1.0)

    if not isTrackedVehicleValid() then
        respond(failure('No test vehicle exists.'))
        return
    end
    RemoveDecalsFromVehicle(vehicle)

    if not isTrackedVehicleValid() then
        respond(failure('No test vehicle exists.'))
        return
    end
    SetVehicleDirtLevel(vehicle, 0.0)

    debugLog('Vehicle cleaned')
    respond(success('Vehicle cleaned.'))
end)

registerSafeCallback('resetVehicle', function(_, respond)
    if not getVehicle() or type(spawnedModel) ~= 'string' then
        respond(failure('No test vehicle exists.', buildVehicleState()))
        return
    end

    local entry = getConfiguredVehicle(spawnedModel)
    if not entry then
        respond(failure('The current model is no longer configured.'))
        return
    end

    local ok, message = spawnConfiguredVehicle(entry)
    local state = buildVehicleState()
    sendState()
    respond(ok and success('Vehicle reset to a fresh spawn.', state) or failure(message, state))
end)

registerSafeCallback('setColour', function(data, respond)
    if data.target ~= 'primary' and data.target ~= 'secondary' then
        respond(failure('Invalid paint target.'))
        return
    end
    if not isInteger(data.r) or not isInteger(data.g) or not isInteger(data.b)
        or data.r < 0 or data.r > 255 or data.g < 0 or data.g > 255 or data.b < 0 or data.b > 255 then
        respond(failure('Paint values must be RGB integers from 0 to 255.'))
        return
    end

    withVehicle(respond, function(vehicle)
        if data.target == 'primary' then
            SetVehicleCustomPrimaryColour(vehicle, data.r, data.g, data.b)
        else
            SetVehicleCustomSecondaryColour(vehicle, data.r, data.g, data.b)
        end
        respond(success('Paint updated.'))
    end)
end)

registerSafeCallback('changeLivery', function(data, respond)
    if data.direction ~= -1 and data.direction ~= 1 then
        respond(failure('Invalid livery direction.'))
        return
    end

    withVehicle(respond, function(vehicle)
        local livery = buildLiveryState(vehicle)
        if not livery.available or livery.count < 1 then
            respond(failure('No liveries are available for this vehicle.', buildVehicleState()))
            return
        end

        local index = livery.index
        if index < 0 then
            -- From stock/unset, Next starts at 0 and Previous wraps to the last livery.
            index = data.direction == 1 and -1 or 0
        end
        index = (index + data.direction) % livery.count
        SetVehicleModKit(vehicle, 0)
        if livery.implementation == 'native' then
            if index < 0 or index >= GetVehicleLiveryCount(vehicle) then
                respond(failure('The selected native livery index is unavailable.'))
                return
            end
            SetVehicleLivery(vehicle, index)
        else
            local modCount = GetNumVehicleMods(vehicle, 48)
            if index < 0 or index >= modCount then
                respond(failure('The selected mod-slot livery index is unavailable.'))
                return
            end
            SetVehicleMod(vehicle, 48, index, false)
        end
        debugLog('livery %s index %s applied', livery.implementation, index)

        local state = buildVehicleState()
        respond(success(('Livery index %d applied.'):format(index), state))
    end)
end)

registerSafeCallback('setModification', function(data, respond)
    withVehicle(respond, function(vehicle)
        local index = data.index
        if data.category == 'turbo' and type(data.enabled) == 'boolean' then index = data.enabled and 0 or -1 end
        local ok, message = applyTuningValue(vehicle, data.category, index)
        if not ok then respond(failure(message, buildVehicleState())) return end
        confirmedTuning[data.category] = index
        debugLog('Confirmed mod %s index %s', data.category, index)
        respond(success('Modification applied.', buildVehicleState()))
    end)
end)

registerSafeCallback('previewModification', function(data, respond)
    if tuningPreviewBusy then respond(failure('A tuning preview is already being processed.')) return end
    tuningPreviewBusy = true
    local vehicle = getVehicle()
    if not vehicle then tuningPreviewBusy = false respond(failure('No test vehicle exists.')) return end
    local ok, message = applyTuningValue(vehicle, data.category, data.index)
    tuningPreviewBusy = false
    if not ok then respond(failure(message, buildVehicleState())) return end
    local definition = modCategories[data.category]
    debugLog('Preview mod type %s index %s', definition and definition.modType or data.category, data.index)
    respond(success(nil, buildVehicleState()))
end)

registerSafeCallback('confirmModification', function(data, respond)
    local vehicle = getVehicle()
    if not vehicle then respond(failure('No test vehicle exists.')) return end
    local category = findTuningCategory(vehicle, data.category)
    if not category or not categoryHasIndex(category, data.index) or category.value ~= data.index then
        respond(failure('The selected preview is unavailable.', buildVehicleState()))
        return
    end
    confirmedTuning[data.category] = data.index
    local definition = modCategories[data.category]
    debugLog('Confirmed mod type %s index %s', definition and definition.modType or data.category, data.index)
    respond(success('Modification confirmed.', buildVehicleState()))
end)

registerSafeCallback('revertModification', function(data, respond)
    local vehicle = getVehicle()
    if not vehicle then respond(failure('No test vehicle exists.')) return end
    local confirmed = confirmedTuning[data.category]
    if not isInteger(confirmed) then respond(failure('There is no confirmed option to restore.')) return end
    local ok, message = applyTuningValue(vehicle, data.category, confirmed)
    if not ok then respond(failure(message, buildVehicleState())) return end
    local definition = modCategories[data.category]
    debugLog('Reverted mod type %s', definition and definition.modType or data.category)
    respond(success('Preview reverted.', buildVehicleState()))
end)

registerSafeCallback('focusTuningCamera', function(data, respond)
    local ok, message = focusTuningCamera(data.category or 'general', data.reset == true)
    respond(ok and success() or failure(message))
end)

registerSafeCallback('closeTuningCamera', function(_, respond)
    destroyTuningCamera()
    respond(success())
end)

registerSafeCallback('cameraControl', function(data, respond)
    if not tuningCamera or not DoesCamExist(tuningCamera) then respond(failure('The tuning camera is not active.')) return end
    if data.control == 'rotate' and type(data.amount) == 'number' and math.abs(data.amount) <= 15.0 then
        cameraOrbit = cameraOrbit + data.amount
    elseif data.control == 'height' and type(data.amount) == 'number' and math.abs(data.amount) <= 0.25 then
        cameraHeight = math.max(-1.0, math.min(2.0, cameraHeight + data.amount))
    elseif data.control == 'zoom' and type(data.amount) == 'number' and math.abs(data.amount) <= 0.5 then
        cameraZoom = math.max(-1.5, math.min(2.0, cameraZoom + data.amount))
    else
        respond(failure('Invalid camera control.'))
        return
    end
    local ok, message = focusTuningCamera(cameraFocusId, false)
    respond(ok and success() or failure(message))
end)

registerSafeCallback('setExtra', function(data, respond)
    if extrasBusy then respond(failure('An extra is already being changed.')) return end
    extrasBusy = true
    local vehicle = getVehicle()
    if not vehicle or not DoesEntityExist(vehicle) then extrasBusy = false respond(failure('No test vehicle exists.')) return end
    if not isInteger(data.id) or data.id < 0 or data.id > 50 or type(data.enabled) ~= 'boolean' then
        extrasBusy = false respond(failure('Invalid vehicle extra.')) return
    end
    if not DoesEntityExist(vehicle) or not DoesExtraExist(vehicle, data.id) then
        extrasBusy = false respond(failure('The selected vehicle extra is unavailable.')) return
    end
    if not DoesEntityExist(vehicle) then extrasBusy = false respond(failure('No test vehicle exists.')) return end
    SetVehicleExtra(vehicle, data.id, not data.enabled)
    extrasBusy = false
    debugLog('Extra %d %s', data.id, data.enabled and 'enabled' or 'disabled')
    respond(success(('Extra %d %s.'):format(data.id, data.enabled and 'enabled' or 'disabled'), buildVehicleState()))
end)

registerSafeCallback('saveSetup', function(_, respond)
    local vehicle = getVehicle()
    if not vehicle then respond(failure('No test vehicle exists.')) return end
    local setup = captureVehicleSetup(vehicle)
    if not setup then respond(failure('The current setup could not be read.')) return end
    savedSetup = setup
    debugLog('current setup saved for %s', spawnedModel)
    respond({ success = true, message = 'Current setup saved.', setup = setup, state = buildVehicleState() })
end)

registerSafeCallback('getSetupJson', function(_, respond)
    local vehicle = getVehicle()
    if not vehicle then respond(failure('No test vehicle exists.')) return end
    local setup = captureVehicleSetup(vehicle)
    if not setup then respond(failure('The current setup could not be read.')) return end
    respond({ success = true, setup = setup })
end)

registerSafeCallback('loadSetup', function(_, respond)
    if presetBusy then respond(failure('A preset is already being loaded.')) return end
    if type(savedSetup) ~= 'table' then respond(failure('No setup has been saved in this client session.')) return end
    presetBusy = true
    local vehicle = getVehicle()
    if not vehicle then presetBusy = false respond(failure('No test vehicle exists.')) return end
    local ok, message = applySetup(vehicle, savedSetup, false)
    presetBusy = false
    if not ok then respond(failure(message, buildVehicleState())) return end
    refreshConfirmedTuning(vehicle)
    debugLog('saved setup loaded for %s', spawnedModel)
    respond(success('Saved setup loaded.', buildVehicleState()))
end)

registerSafeCallback('maxPerformance', function(_, respond)
    withVehicle(respond, function(vehicle)
        SetVehicleModKit(vehicle, 0)
        for _, modType in ipairs(performanceModTypes) do
            local count = GetNumVehicleMods(vehicle, modType)
            if count > 0 then
                SetVehicleMod(vehicle, modType, count - 1, false)
            end
        end
        if GetNumVehicleMods(vehicle, 18) > 0 then
            ToggleVehicleMod(vehicle, 18, true)
        end
        refreshConfirmedTuning(vehicle)
        debugLog('maximum performance upgrades applied')
        respond(success('Maximum performance upgrades applied.', buildVehicleState()))
    end)
end)

registerSafeCallback('resetModifications', function(_, respond)
    withVehicle(respond, function(vehicle)
        SetVehicleModKit(vehicle, 0)
        for modType = 0, 49 do
            local isToggle = modType >= 17 and modType <= 22
            if not isToggle and modType ~= 48 and GetNumVehicleMods(vehicle, modType) > 0 then
                SetVehicleMod(vehicle, modType, -1, false)
            end
        end
        for _, modType in ipairs(toggleModTypes) do
            if GetNumVehicleMods(vehicle, modType) > 0 then
                ToggleVehicleMod(vehicle, modType, false)
            end
        end
        if (tonumber(GetNumVehicleWindowTints()) or 0) > 0 then
            SetVehicleWindowTint(vehicle, -1)
        end

        -- Reset only the livery implementation this vehicle actually exposes.
        local livery = buildLiveryState(vehicle)
        if livery.implementation == 'native' and livery.count > 0 then
            SetVehicleLivery(vehicle, 0)
        elseif livery.implementation == 'mod-slot 48' and livery.count > 0 then
            SetVehicleMod(vehicle, 48, -1, false)
        end
        refreshConfirmedTuning(vehicle)
        debugLog('all available modifications reset to stock')
        respond(success('All modifications reset to stock.', buildVehicleState()))
    end)
end)

registerSafeCallback('randomVisualBuild', function(_, respond)
    withVehicle(respond, function(vehicle)
        if not DoesEntityExist(vehicle) then respond(failure('No test vehicle exists.')) return end
        SetVehicleModKit(vehicle, 0)
        for modType = 0, 10 do
            if not DoesEntityExist(vehicle) then respond(failure('No test vehicle exists.')) return end
            local count = GetNumVehicleMods(vehicle, modType)
            if count > 0 then SetVehicleMod(vehicle, modType, math.random(-1, count - 1), false) end
        end
        if DoesEntityExist(vehicle) and GetNumVehicleMods(vehicle, 23) > 0 then
            SetVehicleWheelType(vehicle, math.random(0, 12))
            local wheelCount = GetNumVehicleMods(vehicle, 23)
            if wheelCount > 0 and DoesEntityExist(vehicle) then
                SetVehicleMod(vehicle, 23, math.random(-1, wheelCount - 1), false)
            end
        end
        if DoesEntityExist(vehicle) then
            SetVehicleCustomPrimaryColour(vehicle, math.random(0, 255), math.random(0, 255), math.random(0, 255))
        end
        if DoesEntityExist(vehicle) then
            SetVehicleCustomSecondaryColour(vehicle, math.random(0, 255), math.random(0, 255), math.random(0, 255))
        end
        if DoesEntityExist(vehicle) then
            local livery = buildLiveryState(vehicle)
            if livery.implementation == 'native' and livery.count > 0 then
                SetVehicleLivery(vehicle, math.random(0, livery.count - 1))
            elseif livery.implementation == 'mod-slot 48' and livery.count > 0 then
                SetVehicleMod(vehicle, 48, math.random(0, livery.count - 1), false)
            end
        end
        refreshConfirmedTuning(vehicle)
        debugLog('random visual build applied')
        respond(success('Random visual build applied.', buildVehicleState()))
    end)
end)

registerSafeCallback('resetVisuals', function(_, respond)
    withVehicle(respond, function(vehicle)
        if type(stockVisualSetup) ~= 'table' then
            respond(failure('The stock visual setup is unavailable.'))
            return
        end
        local ok, message = applySetup(vehicle, stockVisualSetup, true)
        if not ok then respond(failure(message, buildVehicleState())) return end
        refreshConfirmedTuning(vehicle)
        debugLog('visual modifications reset to initial stock setup')
        respond(success('Visual modifications reset to stock.', buildVehicleState()))
    end)
end)

RegisterNetEvent('car_tester:client:catalogue', function(payload)
    if type(payload) ~= 'table' or type(payload.vehicles) ~= 'table' then return end

    local sanitized = {}
    for index = 1, math.min(#payload.vehicles, 5000) do
        local entry = payload.vehicles[index]
        if type(entry) == 'table' and validModelName(trim(entry.model):lower()) then
            sanitized[#sanitized + 1] = {
                model = trim(entry.model):lower(),
                label = trim(entry.label),
                gameName = trim(entry.gameName),
                manufacturer = trim(entry.manufacturer),
                handlingId = trim(entry.handlingId),
                category = 'Add-on',
                resource = trim(entry.resource),
                sourceType = 'addon'
            }
        end
    end

    serverVehicles = sanitized
    rebuildValidatedCatalogue()
end)

RegisterCommand(Config.Command, function()
    setMenuOpen(not menuOpen)
end, false)

RegisterKeyMapping(Config.Command, 'Open Skrifhub GTAV Tester', 'keyboard', Config.DefaultKey)

RegisterCommand('cartestreset', function()
    forceCloseMenu(true)
    if getVehicle() then
        deleteTrackedVehicle()
    else
        spawnedVehicle = nil
        spawnedModel = nil
    end
    debugLog('resource state reset with /cartestreset')
end, false)

AddEventHandler('playerSpawned', function()
    forceCloseMenu(false)
end)

CreateThread(function()
    Wait(0)
    -- Never inherit focus or visible UI state from a resource restart.
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close', clear = true })
    rebuildValidatedCatalogue()
    TriggerServerEvent('car_tester:server:requestCatalogue')
    debugLog('resource initialized')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    forceCloseMenu(true)
    if getVehicle() then
        deleteTrackedVehicle()
    else
        spawnedVehicle = nil
        spawnedModel = nil
    end
    debugLog('resource stopped')
end)
