VehicleLab = VehicleLab or { locks = {} }
VehicleLab.locks = type(VehicleLab.locks) == 'table' and VehicleLab.locks or {}
VehicleLab.State = type(VehicleLab.State) == 'table' and VehicleLab.State or {}
VehicleLab.State.revision = tonumber(VehicleLab.State.revision) or 0
VehicleLab.State.spawnSessionId = tonumber(VehicleLab.State.spawnSessionId) or 0
VehicleLab.State.isInitializingVehicle = false

local menuOpen = false
local inputBlockerRunning = false
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
local activeSpawnTransaction
local recoverRuntimeState
local cleanupSpawnTransaction
local finalizeSpawnTransaction
local activateVehicleForVehicleLab
local clearActiveVehicleState
local refreshActiveVehicleCapabilities
local publishActiveVehicleState

local function errorTrace(errorValue)
    local debugLibrary = type(debug) == 'table' and debug or nil
    local traceback = debugLibrary and debugLibrary.traceback or nil
    if Config.Debug == true and type(traceback) == 'function' then
        return traceback(tostring(errorValue), 2)
    end
    return tostring(errorValue)
end

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
    print(('[vehiclelab] %s'):format(message))
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

local function nativeBoolean(value)
    return value == true or value == 1
end

local function optionalVehicleNativeResult(vehicle)
    if type(IsEntityAVehicle) ~= 'function' then return nil, 'unavailable' end
    local ok, value = pcall(IsEntityAVehicle, vehicle)
    if not ok then return nil, 'error' end
    return nativeBoolean(value), value
end

local function validEntityHandle(entity)
    return type(entity) == 'number' and entity ~= 0 and entity == entity
        and entity ~= math.huge and entity ~= -math.huge
end

local function validActiveVehicle(vehicle)
    if not validEntityHandle(vehicle) then return false end
    local existsOk, exists = pcall(DoesEntityExist, vehicle)
    if not existsOk or not nativeBoolean(exists) then return false end

    local typeOk, entityType = pcall(GetEntityType, vehicle)
    if typeOk and tonumber(entityType) == 2 then return true end

    local fallback = optionalVehicleNativeResult(vehicle)
    return fallback == true
end

local function waitForVehicleEntity(vehicle, expectedModelHash, timeoutMs)
    local diagnostics = {
        entity = vehicle,
        exists = false,
        entityType = nil,
        entityModel = nil,
        expectedModel = tonumber(expectedModelHash),
        isEntityAVehicle = 'unavailable'
    }
    if not validEntityHandle(vehicle) then return false, diagnostics end

    local timeout = math.max(1500, math.min(3000, tonumber(timeoutMs) or 2000))
    local timerOk, startedAt = pcall(GetGameTimer)
    if not timerOk or type(startedAt) ~= 'number' then return false, diagnostics end
    local deadline = startedAt + timeout
    debugLog('Waiting for vehicle entity: entity=%s expectedModel=%s timeoutMs=%d',
        tostring(vehicle), tostring(diagnostics.expectedModel), timeout)

    while true do
        local nowOk, now = pcall(GetGameTimer)
        if not nowOk or type(now) ~= 'number' or now > deadline then break end

        local existsOk, exists = pcall(DoesEntityExist, vehicle)
        diagnostics.exists = existsOk and nativeBoolean(exists)
        if diagnostics.exists then
            local typeOk, entityType = pcall(GetEntityType, vehicle)
            local modelOk, entityModel = pcall(GetEntityModel, vehicle)
            diagnostics.entityType = typeOk and tonumber(entityType) or nil
            diagnostics.entityModel = modelOk and tonumber(entityModel) or nil
            if diagnostics.entityType == 2
                and (diagnostics.expectedModel == nil or diagnostics.entityModel == diagnostics.expectedModel) then
                local _, rawFallback = optionalVehicleNativeResult(vehicle)
                diagnostics.isEntityAVehicle = rawFallback
                debugLog('Entity ready: exists=%s type=%s actualModel=%s expectedModel=%s',
                    tostring(diagnostics.exists), tostring(diagnostics.entityType),
                    tostring(diagnostics.entityModel), tostring(diagnostics.expectedModel))
                return true, diagnostics
            end
        end
        Wait(0)
    end

    local _, rawFallback = optionalVehicleNativeResult(vehicle)
    diagnostics.isEntityAVehicle = rawFallback
    debugLog('Vehicle entity validation timed out: entity=%s exists=%s type=%s actualModel=%s expectedModel=%s isEntityAVehicle=%s',
        tostring(vehicle), tostring(diagnostics.exists), tostring(diagnostics.entityType),
        tostring(diagnostics.entityModel), tostring(diagnostics.expectedModel),
        tostring(diagnostics.isEntityAVehicle))
    return false, diagnostics
end

local function setActiveVehicle(vehicle, model, modelHash)
    if vehicle ~= nil and (not validActiveVehicle(vehicle) or not validModelName(model)) then return false end
    if vehicle ~= nil then
        local hashOk, entityHash = pcall(GetEntityModel, vehicle)
        modelHash = tonumber(modelHash) or (hashOk and entityHash or nil)
        if not modelHash then return false end
    end
    local changed = VehicleLab.State.vehicle ~= vehicle or VehicleLab.State.model ~= model
        or VehicleLab.State.modelHash ~= modelHash
    VehicleLab.State.vehicle = vehicle
    VehicleLab.State.model = vehicle and model or nil
    VehicleLab.State.modelHash = vehicle and modelHash or nil
    if changed then VehicleLab.State.synchronized = false end
    spawnedModel = VehicleLab.State.model
    if changed then VehicleLab.State.revision = VehicleLab.State.revision + 1 end
    return true
end

local function clearActiveVehicle(expectedVehicle)
    if expectedVehicle ~= nil and VehicleLab.State.vehicle ~= expectedVehicle then return false end
    return setActiveVehicle(nil, nil, nil)
end

local function getActiveVehicle()
    local vehicle = VehicleLab.State.vehicle
    local model = VehicleLab.State.model
    local modelHash = tonumber(VehicleLab.State.modelHash)
    local modelMatches = validModelName(model) and modelHash ~= nil
    if modelMatches then
        local entityModelOk, entityModel = pcall(GetEntityModel, vehicle)
        modelMatches = entityModelOk and entityModel == modelHash
    end
    if not validActiveVehicle(vehicle) or not modelMatches then
        if vehicle ~= nil or VehicleLab.State.model ~= nil then
            if clearActiveVehicleState then clearActiveVehicleState('entity-invalid', true)
            else clearActiveVehicle(vehicle) end
        end
        return nil
    end
    spawnedModel = VehicleLab.State.model
    return vehicle
end

-- Backward-compatible internal name; all code resolves through the authoritative state getter.
local function getVehicle()
    return getActiveVehicle()
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
    if not vehicle or not DoesEntityExist(vehicle) then return false, 'No active VehicleLab vehicle exists.' end
    if type(category) ~= 'string' or #category > 32 then return false, 'Invalid camera focus area.' end

    cameraBusy = true
    if resetControls == true then
        cameraOrbit, cameraHeight, cameraZoom = 0.0, 0.0, 0.0
    end
    local area, resolvedId = cameraAreaForCategory(category)
    cameraFocusId = resolvedId
    if not DoesEntityExist(vehicle) then cameraBusy = false return false, 'No active VehicleLab vehicle exists.' end
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
        if recoverRuntimeState then recoverRuntimeState(true, false) end
        return false, 'The tuning camera could not be created.'
    end
    if not DoesEntityExist(vehicle) or not DoesCamExist(newCamera) then
        if DoesCamExist(newCamera) then DestroyCam(newCamera, false) end
        cameraBusy = false
        if recoverRuntimeState then recoverRuntimeState(true, false) end
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

local function getConfiguredVehicleByHash(modelHash)
    modelHash = tonumber(modelHash)
    if not modelHash then return nil end
    for _, entry in ipairs(validatedVehicles) do
        local ok, hash = pcall(joaat, entry.model)
        if ok and hash == modelHash then return entry end
    end
    return nil
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
            sourceType = entry.sourceType,
            vehicleClass = entry.vehicleClass
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
                        handlingId = entry.handlingId ~= '' and entry.handlingId or nil,
                        vehicleClass = type(GetVehicleClassFromName) == 'function' and GetVehicleClassFromName(hash) or nil
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
            revision = VehicleLab.State.revision,
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
        revision = VehicleLab.State.revision,
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

local function sendState(state)
    state = type(state) == 'table' and state or buildVehicleState()
    SendNUIMessage({ action = 'vehicleState', state = state })
    return state
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
        return false, 'No active VehicleLab vehicle exists.'
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
        return false, 'The active vehicle could not be deleted.'
    end

    clearActiveVehicle(vehicle)
    confirmedTuning = {}
    stockVisualSetup = nil
    debugLog('vehicle entity %s deleted', vehicle)
    return true, 'Active vehicle deleted.'
end

local function loadVehicleModel(model, knownHash)
    local hash = tonumber(knownHash) or joaat(model)
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

    if activeSpawnTransaction then
        activeSpawnTransaction.modelHash = hash
        activeSpawnTransaction.modelLoaded = true
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
    local hash, loadError = loadVehicleModel(entry.model, entry.modelHash)
    if not hash then
        return false, loadError
    end

    if getVehicle() then
        if VehicleLab.State.ownership == 'adopted' and entry.deleteAdoptedOnReplace ~= true and clearActiveVehicleState then
            clearActiveVehicleState('replaced-by-spawn', false)
        else
            local deleted, deleteError = deleteTrackedVehicle(false)
            if not deleted then
                SetModelAsNoLongerNeeded(hash)
                return false, deleteError
            end
            if activeSpawnTransaction then activeSpawnTransaction.previousVehicleRemoved = true end
        end
    end

    local distance = tonumber(Config.SpawnDistance) or 5.0
    local coords = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, distance, 0.5)
    local heading = GetEntityHeading(playerPed)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    if activeSpawnTransaction then activeSpawnTransaction.vehicleCreationAttempted = true end
    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, false)
    debugLog('CreateVehicle returned entity=%s', tostring(vehicle))

    if not validEntityHandle(vehicle) then
        SetModelAsNoLongerNeeded(hash)
        if activeSpawnTransaction then activeSpawnTransaction.modelReleased = true end
        return false, ('Model "%s" loaded, but the vehicle could not be created.'):format(entry.model)
    end

    if activeSpawnTransaction then activeSpawnTransaction.createdVehicle = vehicle end
    SetEntityAsMissionEntity(vehicle, true, true)
    local entityReady, entityDiagnostics = waitForVehicleEntity(vehicle, hash, 2000)
    SetModelAsNoLongerNeeded(hash)
    if activeSpawnTransaction then activeSpawnTransaction.modelReleased = true end
    if not entityReady then
        if Config.Debug == true then
            print(('[vehiclelab] Vehicle entity validation timed out:\nentity=%s\nexists=%s\ntype=%s\nactualModel=%s\nexpectedModel=%s\nisEntityAVehicle=%s'):format(
                tostring(vehicle), tostring(entityDiagnostics.exists), tostring(entityDiagnostics.entityType),
                tostring(entityDiagnostics.entityModel), tostring(entityDiagnostics.expectedModel),
                tostring(entityDiagnostics.isEntityAVehicle)))
        end
        return false, 'Vehicle was created but did not become a usable vehicle entity before the timeout.'
    end

    SetVehicleModKit(vehicle, 0)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)
    if activeSpawnTransaction then activeSpawnTransaction.playerPlacementAttempted = true end
    SetPedIntoVehicle(playerPed, vehicle, -1)
    if activeSpawnTransaction then activeSpawnTransaction.playerPlaced = GetPedInVehicleSeat(vehicle, -1) == playerPed end
    buildTuningState(vehicle)
    debugLog('created vehicle entity %s for model %s', vehicle, entry.model)

    return true, ('Spawned %s.'):format(entry.model)
end

local function withVehicle(respond, action)
    local vehicle = getVehicle()
    if not vehicle then
        respond(failure('No active VehicleLab vehicle exists.', buildVehicleState()))
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
        end, errorTrace)

        if not ok then
            tuningPreviewBusy = false
            presetBusy = false
            extrasBusy = false
            cameraBusy = false
            if VehicleLab and type(VehicleLab.locks) == 'table' then
                for key in pairs(VehicleLab.locks) do VehicleLab.locks[key] = nil end
            end
            if activeSpawnTransaction and cleanupSpawnTransaction then cleanupSpawnTransaction(activeSpawnTransaction, err)
            elseif recoverRuntimeState then recoverRuntimeState(true, false) end
            SendNUIMessage({ action = 'spawnLoading', loading = false })
            print(('[vehiclelab] NUI callback "%s" failed%s'):format(name,
                Config.Debug == true and (': ' .. tostring(err)) or '. Enable Config.Debug for details.'))
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
    if not vehicle or not DoesEntityExist(vehicle) then return false, 'No active VehicleLab vehicle exists.' end
    if type(categoryId) ~= 'string' or #categoryId > 32 or not isInteger(index) then
        return false, 'Invalid modification request.'
    end
    if not DoesEntityExist(vehicle) then return false, 'No active VehicleLab vehicle exists.' end
    SetVehicleModKit(vehicle, 0)
    local category = findTuningCategory(vehicle, categoryId)
    if not category or not categoryHasIndex(category, index) then
        return false, 'The selected modification is unavailable.'
    end
    if not DoesEntityExist(vehicle) then return false, 'No active VehicleLab vehicle exists.' end

    if categoryId == 'turbo' then
        ToggleVehicleMod(vehicle, 18, index == 0)
    elseif categoryId == 'wheel_type' then
        SetVehicleWheelType(vehicle, index)
    elseif categoryId == 'window_tint' then
        SetVehicleWindowTint(vehicle, index)
    else
        local definition = modCategories[categoryId]
        if not definition then return false, 'Invalid modification category.' end
        if not DoesEntityExist(vehicle) then return false, 'No active VehicleLab vehicle exists.' end
        local count = GetNumVehicleMods(vehicle, definition.modType)
        if index < -1 or index >= count then return false, 'The selected modification is unavailable.' end
        if not DoesEntityExist(vehicle) then return false, 'No active VehicleLab vehicle exists.' end
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
    if not DoesEntityExist(vehicle) then return false, 'No active VehicleLab vehicle exists.' end
    SetVehicleModKit(vehicle, 0)

    local visualModTypes = {
        [0] = true, [1] = true, [2] = true, [3] = true, [4] = true,
        [5] = true, [6] = true, [7] = true, [8] = true, [9] = true,
        [10] = true, [23] = true
    }
    if type(setup.mods) == 'table' then
        for _, item in ipairs(setup.mods) do
            if not DoesEntityExist(vehicle) then return false, 'No active VehicleLab vehicle exists.' end
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
            if not DoesEntityExist(vehicle) then return false, 'No active VehicleLab vehicle exists.' end
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
            if not DoesEntityExist(vehicle) then return false, 'No active VehicleLab vehicle exists.' end
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
    TriggerServerEvent('vehiclelab:server:requestCatalogue')
    respond(success('Vehicle catalogue refresh requested.'))
end)

registerSafeCallback('close', function(_, respond)
    setMenuOpen(false)
    respond(success())
end)

registerSafeCallback('spawnVehicle', function(data, respond)
    if VehicleLab.locks.spawning then
        respond(failure('Vehicle spawning is already in progress.'))
        return
    end
    local entry = getConfiguredVehicle(data.model)
    if not entry then
        debugLog('rejected unconfigured model request: %s', tostring(data.model))
        respond(failure('The selected vehicle is not available in the current validated catalogue.'))
        return
    end

    VehicleLab.locks.spawning = true
    SendNUIMessage({ action = 'spawnLoading', loading = true })
    local callOk, ok, message, state, activationData = xpcall(function()
        local spawnOk, spawnMessage, spawnResult = spawnConfiguredVehicle(entry)
        local nextState = spawnResult and spawnResult.state or buildVehicleState()
        if not spawnOk then sendState(nextState) end
        if spawnOk and finalizeSpawnTransaction then finalizeSpawnTransaction() end
        return spawnOk, spawnMessage, nextState, spawnResult
    end, errorTrace)
    VehicleLab.locks.spawning = nil
    pcall(SendNUIMessage, { action = 'spawnLoading', loading = false })

    if not callOk then
        if activeSpawnTransaction and cleanupSpawnTransaction then cleanupSpawnTransaction(activeSpawnTransaction, message)
        elseif recoverRuntimeState then recoverRuntimeState(true, false) end
        print(('[vehiclelab] spawn failed%s'):format(
            Config.Debug == true and (': ' .. tostring(message)) or '. Enable Config.Debug for details.'))
        respond(failure('Vehicle spawning failed. The partial spawn was cleaned up.', buildVehicleState()))
        return
    end

    if ok then
        local payload = success(message, state)
        local warnings = activationData and activationData.warnings or {}
        payload.data = { model = entry.model, active = true, activeVehicle = state and state.activeVehicle, warnings = warnings }
        payload.warnings = warnings
        respond(payload)
    else
        respond(failure(message, state))
    end
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
            and getActiveVehicle() == vehicle and DoesEntityExist(vehicle)
    end

    if not isTrackedVehicleValid() then
        respond(failure('No active VehicleLab vehicle exists.'))
        return
    end

    WashDecalsFromVehicle(vehicle, 1.0)

    if not isTrackedVehicleValid() then
        respond(failure('No active VehicleLab vehicle exists.'))
        return
    end
    RemoveDecalsFromVehicle(vehicle)

    if not isTrackedVehicleValid() then
        respond(failure('No active VehicleLab vehicle exists.'))
        return
    end
    SetVehicleDirtLevel(vehicle, 0.0)

    debugLog('Vehicle cleaned')
    respond(success('Vehicle cleaned.'))
end)

registerSafeCallback('resetVehicle', function(_, respond)
    if not getVehicle() or type(spawnedModel) ~= 'string' then
        respond(failure('No active VehicleLab vehicle exists.', buildVehicleState()))
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
    if not vehicle then tuningPreviewBusy = false respond(failure('No active VehicleLab vehicle exists.')) return end
    local ok, message = applyTuningValue(vehicle, data.category, data.index)
    tuningPreviewBusy = false
    if not ok then respond(failure(message, buildVehicleState())) return end
    local definition = modCategories[data.category]
    debugLog('Preview mod type %s index %s', definition and definition.modType or data.category, data.index)
    respond(success(nil, buildVehicleState()))
end)

registerSafeCallback('confirmModification', function(data, respond)
    local vehicle = getVehicle()
    if not vehicle then respond(failure('No active VehicleLab vehicle exists.')) return end
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
    if not vehicle then respond(failure('No active VehicleLab vehicle exists.')) return end
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
    if not vehicle or not DoesEntityExist(vehicle) then extrasBusy = false respond(failure('No active VehicleLab vehicle exists.')) return end
    if not isInteger(data.id) or data.id < 0 or data.id > 50 or type(data.enabled) ~= 'boolean' then
        extrasBusy = false respond(failure('Invalid vehicle extra.')) return
    end
    if not DoesEntityExist(vehicle) or not DoesExtraExist(vehicle, data.id) then
        extrasBusy = false respond(failure('The selected vehicle extra is unavailable.')) return
    end
    if not DoesEntityExist(vehicle) then extrasBusy = false respond(failure('No active VehicleLab vehicle exists.')) return end
    SetVehicleExtra(vehicle, data.id, not data.enabled)
    extrasBusy = false
    debugLog('Extra %d %s', data.id, data.enabled and 'enabled' or 'disabled')
    respond(success(('Extra %d %s.'):format(data.id, data.enabled and 'enabled' or 'disabled'), buildVehicleState()))
end)

registerSafeCallback('saveSetup', function(_, respond)
    local vehicle = getVehicle()
    if not vehicle then respond(failure('No active VehicleLab vehicle exists.')) return end
    local setup = captureVehicleSetup(vehicle)
    if not setup then respond(failure('The current setup could not be read.')) return end
    savedSetup = setup
    debugLog('current setup saved for %s', spawnedModel)
    respond({ success = true, message = 'Current setup saved.', setup = setup, state = buildVehicleState() })
end)

registerSafeCallback('getSetupJson', function(_, respond)
    local vehicle = getVehicle()
    if not vehicle then respond(failure('No active VehicleLab vehicle exists.')) return end
    local setup = captureVehicleSetup(vehicle)
    if not setup then respond(failure('The current setup could not be read.')) return end
    respond({ success = true, setup = setup })
end)

registerSafeCallback('loadSetup', function(_, respond)
    if presetBusy then respond(failure('A preset is already being loaded.')) return end
    if type(savedSetup) ~= 'table' then respond(failure('No setup has been saved in this client session.')) return end
    presetBusy = true
    local vehicle = getVehicle()
    if not vehicle then presetBusy = false respond(failure('No active VehicleLab vehicle exists.')) return end
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
        if not DoesEntityExist(vehicle) then respond(failure('No active VehicleLab vehicle exists.')) return end
        SetVehicleModKit(vehicle, 0)
        for modType = 0, 10 do
            if not DoesEntityExist(vehicle) then respond(failure('No active VehicleLab vehicle exists.')) return end
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

RegisterNetEvent('vehiclelab:client:catalogue', function(payload)
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

RegisterCommand('cartest', function()
    setMenuOpen(not menuOpen)
end, false)

RegisterKeyMapping(Config.Command, 'Open VehicleLab', 'keyboard', Config.DefaultKey)

local function resetVehicleLab()
    forceCloseMenu(true)
    if getVehicle() then
        if VehicleLab.State.ownership == 'spawned' then deleteTrackedVehicle()
        elseif clearActiveVehicleState then clearActiveVehicleState('reset', false)
        else clearActiveVehicle() end
    else
        clearActiveVehicle()
    end
    debugLog('resource state reset')
end

RegisterCommand(Config.ResetCommand, resetVehicleLab, false)
RegisterCommand('cartestreset', resetVehicleLab, false)

AddEventHandler('playerSpawned', function()
    forceCloseMenu(false)
end)

CreateThread(function()
    Wait(0)
    -- Never inherit focus or visible UI state from a resource restart.
    if recoverRuntimeState then
        recoverRuntimeState(true, true)
    else
        menuOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'close', clear = true })
    end
    rebuildValidatedCatalogue()
    TriggerServerEvent('vehiclelab:server:requestCatalogue')
    TriggerServerEvent('vehiclelab:server:requestTimestamp')
    debugLog('resource initialized')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    forceCloseMenu(true)
    if getVehicle() then
        local targeting = Config.VehicleTargeting or {}
        local deleteOnStop = (VehicleLab.State.ownership == 'spawned'
            and targeting.DeleteSpawnedVehicleOnResourceStop ~= false)
            or (VehicleLab.State.ownership == 'adopted'
            and targeting.DeleteAdoptedVehicleOnResourceStop == true)
        if deleteOnStop then deleteTrackedVehicle()
        elseif clearActiveVehicleState then clearActiveVehicleState('resource-stop', false)
        else clearActiveVehicle() end
    else
        clearActiveVehicle()
    end
    debugLog('resource stopped')
end)

-- VehicleLab 2.0 advanced capability/state layer. It intentionally extends the
-- proven 1.x lifecycle above so legacy NUI callbacks and command aliases remain
-- available to existing users.
local Constants = VehicleLabConstants
local advancedCapabilities, spawnBaseline = nil, nil
local historyUndo, historyRedo, historyReplaying = {}, {}, false
local sessionUnsafe = {}
local screenshotMode, hideHudForScreenshot = false, false
local advancedLocks = VehicleLab.locks
local advancedPermission = Config.Permissions.RequireAce ~= true
local bodyPreviewOriginal = {}
local stancePreviewSessions = {}
local stancePreviewSequences = {}
local stancePreviewBarrier = -1

local MOD_FALLBACKS = {
    [0] = 'Spoiler', [1] = 'Front Bumper', [2] = 'Rear Bumper', [3] = 'Side Skirts',
    [4] = 'Exhaust', [5] = 'Frame', [6] = 'Grille', [7] = 'Hood',
    [8] = 'Left Fender', [9] = 'Right Fender', [10] = 'Roof', [11] = 'Engine',
    [12] = 'Brakes', [13] = 'Transmission', [14] = 'Horns', [15] = 'Suspension',
    [16] = 'Armour', [23] = 'Front Wheels', [24] = 'Rear Wheels', [25] = 'Plate Holder',
    [26] = 'Vanity Plates', [27] = 'Trim', [28] = 'Ornaments', [29] = 'Dashboard',
    [30] = 'Dials', [31] = 'Door Speakers', [32] = 'Seats', [33] = 'Steering Wheel',
    [34] = 'Shifter', [35] = 'Plaques', [36] = 'Speakers', [37] = 'Trunk',
    [38] = 'Hydraulics', [39] = 'Engine Block', [40] = 'Air Filter', [41] = 'Struts',
    [42] = 'Arch Cover', [43] = 'Aerials', [44] = 'Trim 2', [45] = 'Tank',
    [46] = 'Windows', [47] = 'Other', [48] = 'Livery', [49] = 'Lightbar'
}

local function finiteNumber(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function nativeCall(native, ...)
    if type(native) ~= 'function' then return false end
    local result = table.pack(pcall(native, ...))
    if not result[1] then return false end
    return true, table.unpack(result, 2, result.n)
end

local serverUnixTime, serverUnixReceivedAt = 0, 0

local function monotonicMilliseconds()
    local ok, value = nativeCall(GetGameTimer)
    value = ok and tonumber(value) or 0
    return finiteNumber(value) and math.max(0, math.floor(value)) or 0
end

local function monotonicSeconds()
    return math.floor(monotonicMilliseconds() / 1000)
end

local function cachedUnixTimestamp()
    if serverUnixTime <= 0 then return 0 end
    local elapsed = monotonicMilliseconds() - serverUnixReceivedAt
    if elapsed < 0 then elapsed = 0 end
    return serverUnixTime + math.floor(elapsed / 1000)
end

local function requestUnixTimestamp(waitForReply)
    TriggerServerEvent(Constants.Events.requestTimestamp)
    if waitForReply ~= true or serverUnixTime > 0 then return cachedUnixTimestamp() end
    local deadline = monotonicMilliseconds() + 1000
    local attempts = 0
    while serverUnixTime <= 0 and monotonicMilliseconds() < deadline and attempts < 120 do
        attempts = attempts + 1
        Wait(0)
    end
    return cachedUnixTimestamp()
end

RegisterNetEvent(Constants.Events.timestamp, function(value)
    value = tonumber(value)
    if not finiteNumber(value) or value <= 0 then return end
    serverUnixTime = math.floor(value)
    serverUnixReceivedAt = monotonicMilliseconds()
end)

recoverRuntimeState = function(closeMenu, clearState)
    cameraGeneration = cameraGeneration + 1
    pcall(destroyTuningCamera)
    pcall(RenderScriptCams, false, false, 0, true, true)

    if VehicleLab.runtimeTimecycleApplied == true then
        pcall(ClearTimecycleModifier)
        VehicleLab.runtimeTimecycleApplied = false
    end
    if type(VehicleLab.runtimeScreenEffect) == 'string' and VehicleLab.runtimeScreenEffect ~= '' then
        pcall(StopScreenEffect, VehicleLab.runtimeScreenEffect)
        VehicleLab.runtimeScreenEffect = nil
    end

    local fadedOutOk, fadedOut = pcall(IsScreenFadedOut)
    local fadingOutOk, fadingOut = pcall(IsScreenFadingOut)
    if (fadedOutOk and fadedOut) or (fadingOutOk and fadingOut) then pcall(DoScreenFadeIn, 0) end

    pcall(SetNuiFocusKeepInput, false)
    pcall(SendNUIMessage, { action = 'spawnLoading', loading = false })
    if closeMenu == true then
        menuOpen = false
        pcall(SetNuiFocus, false, false)
        pcall(SendNUIMessage, { action = 'close', clear = clearState == true })
    end
    cameraBusy = false
end

local function clone(value)
    if type(value) ~= 'table' then return value end
    local ok, encoded = pcall(json.encode, value)
    if not ok then return nil end
    local decodedOk, decoded = pcall(json.decode, encoded)
    return decodedOk and decoded or nil
end

local function kvpRead(key, fallback)
    local raw = GetResourceKvpString(key)
    if not raw or raw == '' then return clone(fallback) or fallback end
    local ok, value = pcall(json.decode, raw)
    return ok and type(value) == type(fallback) and value or (clone(fallback) or fallback)
end

local function kvpWrite(key, value)
    local ok, encoded = pcall(json.encode, value)
    if ok then SetResourceKvp(key, encoded) end
    return ok
end

local function overrideForModel(model)
    local overrides = Config.VehicleOverrides
    return type(overrides) == 'table' and type(overrides[(model or ''):lower()]) == 'table'
        and overrides[(model or ''):lower()] or {}
end

local function modDisabled(override, modType, index)
    local group = type(override.disabledMods) == 'table' and override.disabledMods[modType]
    return type(group) == 'table' and group[index] == true
end

local function resolvedLabel(key, fallback)
    key = trim(key)
    if key ~= '' and key ~= 'NULL' then
        local translated = GetLabelText(key)
        if translated and translated ~= '' and translated ~= 'NULL' and translated ~= key then return translated end
    end
    return fallback
end

local function wheelResolver(vehicle, model)
    local count = tonumber(GetVehicleNumberOfWheels(vehicle)) or 0
    local override = overrideForModel(model)
    local map, confident, source
    if type(override.wheelMap) == 'table' then
        map, confident, source = clone(override.wheelMap), true, 'configuration override'
    elseif count == 4 then
        map = { frontLeft = 0, frontRight = 1, rearLeft = 2, rearRight = 3 }
        confident, source = true, 'standard four-wheel layout'
    elseif count == 6 then
        map = { frontLeft = 0, frontRight = 1, middleLeft = 2, middleRight = 3, rearLeft = 4, rearRight = 5 }
        confident, source = true, 'standard six-wheel layout'
    elseif count == 2 then
        map = { front = 0, rear = 1 }
        confident, source = false, 'two-wheel layout; paired axle controls hidden'
    else
        map, confident, source = {}, false, 'unrecognized wheel layout'
    end
    local mapped = 0
    for _, index in pairs(map) do if isInteger(index) and index >= 0 then mapped = mapped + 1 end end
    return { count = count, map = map, mappedCount = mapped, axleSafe = confident, source = source }
end

local function stanceSupport()
    return {
        wheelSize = type(GetVehicleWheelSize) == 'function' and type(SetVehicleWheelSize) == 'function',
        wheelWidth = type(GetVehicleWheelWidth) == 'function' and type(SetVehicleWheelWidth) == 'function',
        wheelOffset = type(GetVehicleWheelXOffset) == 'function' and type(SetVehicleWheelXOffset) == 'function',
        wheelRotation = type(GetVehicleWheelYRotation) == 'function' and type(SetVehicleWheelYRotation) == 'function',
        suspensionHeight = type(GetVehicleSuspensionHeight) == 'function' and type(SetVehicleSuspensionHeight) == 'function'
    }
end

local function optionList(vehicle, modType, count, override)
    local options = { { index = -1, label = 'Stock' } }
    for index = 0, count - 1 do
        if not modDisabled(override, modType, index)
            and not (sessionUnsafe[modType] and sessionUnsafe[modType][index]) then
            local key = GetModTextLabel(vehicle, modType, index)
            options[#options + 1] = {
                index = index,
                labelKey = trim(key) ~= '' and key or nil,
                label = resolvedLabel(key, ('Option %d'):format(index + 1))
            }
        end
    end
    return options
end

local function scanAdvancedCapabilities(vehicle)
    if not validActiveVehicle(vehicle) then return nil, { 'entity: unavailable' } end

    local warnings = {}
    local function section(name, action)
        local ok, result = xpcall(action, errorTrace)
        if not ok then warnings[#warnings + 1] = ('%s: %s'):format(name, tostring(result)) end
        return ok, result
    end

    nativeCall(SetVehicleModKit, vehicle, 0)
    local entry = getConfiguredVehicle(spawnedModel) or {}
    local override = overrideForModel(spawnedModel)
    local wheelMap = { count = 0, mappedCount = 0, map = {}, axleSafe = false }
    section('wheel mapping', function() wheelMap = wheelResolver(vehicle, spawnedModel) end)
    local classOk, vehicleClass = nativeCall(GetVehicleClass, vehicle)
    local capability = {
        model = spawnedModel,
        displayName = VehicleLab.State.displayName or entry.label or spawnedModel,
        manufacturer = VehicleLab.State.manufacturer or entry.manufacturer,
        sourceResource = VehicleLab.State.sourceResource or entry.resource or 'External',
        sourceType = VehicleLab.State.sourceType or entry.sourceType or 'external',
        vehicleClass = classOk and vehicleClass or nil,
        vehicleType = 'automobile', wheelCount = wheelMap.count, wheelMap = wheelMap,
        mods = {}, bodyMods = {}, performanceMods = {}, toggleMods = {},
        wheelTypes = {}, liveries = {}, extras = {}, stance = stanceSupport(),
        sections = {
            general = { supported = true },
            paint = { supported = type(SetVehicleColours) == 'function' or type(SetVehicleCustomPrimaryColour) == 'function' },
            lighting = { supported = type(SetVehicleNeonLightEnabled) == 'function' or type(ToggleVehicleMod) == 'function' },
            diagnostics = { supported = true }
        }, warnings = warnings,
        support = {
            neon = type(SetVehicleNeonLightEnabled) == 'function',
            xenon = type(ToggleVehicleMod) == 'function',
            windowTint = type(GetNumVehicleWindowTints) == 'function',
            customPaint = type(SetVehicleCustomPrimaryColour) == 'function',
            driftTyres = type(SetDriftTyresEnabled) == 'function' and type(GetDriftTyresEnabled) == 'function'
        }
    }
    local okType, valueType = nativeCall(GetVehicleType, vehicle)
    if okType and type(valueType) == 'string' then capability.vehicleType = valueType end

    capability.sections.body = { supported = section('body/performance mods', function()
        for modType = 0, 49 do
            if modType < 17 or modType > 22 then
                local itemOk, item = pcall(function()
                    local countOk, rawCount = nativeCall(GetNumVehicleMods, vehicle, modType)
                    local count = countOk and (tonumber(rawCount) or 0) or 0
                    if count <= 0 or (type(override.disabledSlots) == 'table' and override.disabledSlots[modType]) then return nil end
                    local slotOk, slotKey = nativeCall(GetModSlotName, vehicle, modType)
                    if not slotOk then slotKey = nil end
                    local currentOk, current = nativeCall(GetVehicleMod, vehicle, modType)
                    return {
                        id = tostring(modType), modType = modType, count = count,
                        labelKey = trim(slotKey) ~= '' and slotKey or nil,
                        label = resolvedLabel(slotKey, MOD_FALLBACKS[modType] or ('Modification %d'):format(modType)),
                        current = currentOk and current or -1,
                        options = optionList(vehicle, modType, count, override)
                    }
                end)
                if itemOk and item then
                    capability.mods[#capability.mods + 1] = item
                    if modType == 11 or modType == 12 or modType == 13 or modType == 15 or modType == 16 then
                        capability.performanceMods[#capability.performanceMods + 1] = item
                    elseif modType ~= 14 and modType ~= 23 and modType ~= 24 and modType ~= 48 then
                        capability.bodyMods[#capability.bodyMods + 1] = item
                    end
                elseif not itemOk then warnings[#warnings + 1] = ('mod slot %d: unavailable'):format(modType) end
            end
        end
    end) }

    capability.sections.performance = { supported = section('toggle mods', function()
        for _, modType in ipairs(Constants.ToggleTypes) do
            local countOk, rawCount = nativeCall(GetNumVehicleMods, vehicle, modType)
            local count = countOk and (tonumber(rawCount) or 0) or 0
            if count > 0 then
                local enabledOk, enabled = nativeCall(IsToggleModOn, vehicle, modType)
                capability.toggleMods[#capability.toggleMods + 1] = {
                    modType = modType, label = ({ [18] = 'Turbo', [20] = 'Tyre Smoke', [22] = 'Xenon' })[modType]
                        or ('Toggle %d'):format(modType), enabled = enabledOk and enabled == true
                }
            end
        end
    end) }

    capability.sections.wheels = { supported = section('wheels', function()
        local _, originalType = nativeCall(GetVehicleWheelType, vehicle)
        local _, originalFront = nativeCall(GetVehicleMod, vehicle, 23)
        local _, originalRear = nativeCall(GetVehicleMod, vehicle, 24)
        local _, originalFrontCustom = nativeCall(GetVehicleModVariation, vehicle, 23)
        local _, originalRearCustom = nativeCall(GetVehicleModVariation, vehicle, 24)
        for _, definition in ipairs((Config.Wheels and Config.Wheels.Types) or {}) do
            if isInteger(definition.id) and definition.id >= 0 and definition.id <= 64 then
                nativeCall(SetVehicleWheelType, vehicle, definition.id)
                local countOk, rawCount = nativeCall(GetNumVehicleMods, vehicle, 23)
                local count = countOk and (tonumber(rawCount) or 0) or 0
                if count > 0 then capability.wheelTypes[#capability.wheelTypes + 1] = { id = definition.id, label = definition.label, count = count } end
            end
        end
        if finiteNumber(originalType) then nativeCall(SetVehicleWheelType, vehicle, originalType) end
        local frontOk, frontCount = nativeCall(GetNumVehicleMods, vehicle, 23)
        local rearOk, rearCount = nativeCall(GetNumVehicleMods, vehicle, 24)
        frontCount, rearCount = frontOk and (tonumber(frontCount) or 0) or 0, rearOk and (tonumber(rearCount) or 0) or 0
        if finiteNumber(originalFront) and originalFront >= -1 and originalFront < frontCount then nativeCall(SetVehicleMod, vehicle, 23, originalFront, originalFrontCustom == true) end
        if rearCount > 0 and finiteNumber(originalRear) and originalRear >= -1 and originalRear < rearCount then nativeCall(SetVehicleMod, vehicle, 24, originalRear, originalRearCustom == true) end
        capability.frontWheelCount, capability.rearWheelCount = frontCount, rearCount
    end) }

    capability.sections.liveries = { supported = section('liveries', function()
        local nativeOk, nativeCount = nativeCall(GetVehicleLiveryCount, vehicle)
        local slotOk, slotCount = nativeCall(GetNumVehicleMods, vehicle, 48)
        nativeCount, slotCount = nativeOk and (tonumber(nativeCount) or 0) or 0, slotOk and (tonumber(slotCount) or 0) or 0
        if nativeCount > 0 and override.disableNativeLivery ~= true then
            local currentOk, current = nativeCall(GetVehicleLivery, vehicle)
            capability.liveries.native = { count = nativeCount, current = currentOk and current or -1 }
        end
        if slotCount > 0 and override.disableModLivery ~= true then
            local currentOk, current = nativeCall(GetVehicleMod, vehicle, 48)
            capability.liveries.mod = { count = slotCount, current = currentOk and current or -1, options = optionList(vehicle, 48, slotCount, override) }
        end
        local roofOk, roofCount = nativeCall(GetVehicleRoofLiveryCount, vehicle)
        if roofOk and tonumber(roofCount) and roofCount > 0 and override.disableRoofLivery ~= true then
            local currentOk, current = nativeCall(GetVehicleRoofLivery, vehicle)
            capability.liveries.roof = { count = roofCount, current = currentOk and current or 0 }
        end
    end) }

    capability.sections.extras = { supported = section('extras', function() capability.extras = buildExtrasState(vehicle) end) }
    capability.stance.axleControls = Config.Stance.Enabled ~= false and override.stanceEnabled ~= false
        and wheelMap.axleSafe and capability.stance.wheelOffset and capability.stance.wheelRotation
    capability.sections.stance = {
        supported = capability.stance.axleControls == true or capability.stance.wheelSize == true
            or capability.stance.wheelWidth == true or capability.stance.suspensionHeight == true
    }
    if not capability.stance.axleControls then
        capability.sections.stance.reason = 'Axle-specific wheel natives or mapping are unavailable.'
    end
    capability.body = { supported = capability.sections.body.supported == true, categories = capability.bodyMods }
    capability.performance = { supported = capability.sections.performance.supported == true, slots = capability.performanceMods, toggles = capability.toggleMods }
    debugLog('capability scan %s: mods=%d body=%d wheels=%d extras=%d warnings=%d', spawnedModel,
        #capability.mods, #capability.bodyMods, #capability.wheelTypes, #capability.extras, #warnings)
    return capability, warnings
end

local function captureStance(vehicle, mapping)
    local support, stance = stanceSupport(), { wheels = {} }
    local ok, value
    if support.wheelSize then
        ok, value = nativeCall(GetVehicleWheelSize, vehicle)
        if ok and finiteNumber(value) then stance.wheelSize = value end
    end
    if support.wheelWidth then
        ok, value = nativeCall(GetVehicleWheelWidth, vehicle)
        if ok and finiteNumber(value) then stance.wheelWidth = value end
    end
    if support.suspensionHeight then
        ok, value = nativeCall(GetVehicleSuspensionHeight, vehicle)
        if ok and finiteNumber(value) then stance.suspensionHeight = value end
    end
    for name, index in pairs((mapping and mapping.map) or {}) do
        if type(name) == 'string' and isInteger(index) and index >= 0 then
            local wheel = { index = index }
            if support.wheelOffset then
                ok, value = nativeCall(GetVehicleWheelXOffset, vehicle, index)
                if ok and finiteNumber(value) then wheel.offset = value end
            end
            if support.wheelRotation then
                ok, value = nativeCall(GetVehicleWheelYRotation, vehicle, index)
                if ok and finiteNumber(value) then wheel.rotation = value end
            end
            stance.wheels[name] = wheel
        end
    end
    return stance
end

local function captureAdvancedSetup(vehicle, capabilities)
    if not validActiveVehicle(vehicle) then return nil, 'invalid_vehicle_entity' end
    nativeCall(SetVehicleModKit, vehicle, 0)

    local setup = {
        schemaVersion = tonumber(Config.Presets.SchemaVersion) or 1,
        vehicleModel = spawnedModel,
        capturedAtMs = monotonicMilliseconds(),
        bodyMods = {}, toggleMods = {}, performance = {}, extras = {},
        wheels = {}, paint = {},
        lighting = { neon = {} },
        liveries = {}, details = {}
    }
    local wheelMap = (capabilities or advancedCapabilities) and (capabilities or advancedCapabilities).wheelMap
    if not wheelMap then
        local mappingOk, mapping = pcall(wheelResolver, vehicle, spawnedModel)
        wheelMap = mappingOk and mapping or { map = {} }
    end
    setup.wheels.stance = captureStance(vehicle, wheelMap)

    local ok, first, second, third
    ok, first, second = nativeCall(GetVehicleColours, vehicle)
    if ok then setup.paint.primaryIndex, setup.paint.secondaryIndex = first, second end
    ok, first, second, third = nativeCall(GetVehicleCustomPrimaryColour, vehicle)
    if ok and validColourChannel(first) and validColourChannel(second) and validColourChannel(third) then
        setup.paint.primaryRgb = { r = first, g = second, b = third }
    end
    ok, first, second, third = nativeCall(GetVehicleCustomSecondaryColour, vehicle)
    if ok and validColourChannel(first) and validColourChannel(second) and validColourChannel(third) then
        setup.paint.secondaryRgb = { r = first, g = second, b = third }
    end
    ok, first, second = nativeCall(GetVehicleExtraColours, vehicle)
    if ok then setup.paint.pearlescent, setup.paint.wheelColour = first, second end
    ok, first, second, third = nativeCall(GetVehicleModColor_1, vehicle)
    if ok then setup.paint.primaryType, setup.paint.primaryModColour, setup.paint.primaryPearl = first, second, third end
    ok, first, second = nativeCall(GetVehicleModColor_2, vehicle)
    if ok then setup.paint.secondaryType, setup.paint.secondaryModColour = first, second end
    ok, first = nativeCall(GetIsVehiclePrimaryColourCustom, vehicle)
    if ok and type(first) == 'boolean' then setup.paint.primaryCustom = first end
    ok, first = nativeCall(GetIsVehicleSecondaryColourCustom, vehicle)
    if ok and type(first) == 'boolean' then setup.paint.secondaryCustom = first end

    for key, getterArgs in pairs({
        type = { GetVehicleWheelType }, front = { GetVehicleMod, 23 }, rear = { GetVehicleMod, 24 },
        frontCustomTyres = { GetVehicleModVariation, 23 }, rearCustomTyres = { GetVehicleModVariation, 24 }
    }) do
        local getter = getterArgs[1]
        if getterArgs[2] == nil then ok, first = nativeCall(getter, vehicle)
        else ok, first = nativeCall(getter, vehicle, getterArgs[2]) end
        if ok and (finiteNumber(first) or type(first) == 'boolean') then setup.wheels[key] = first end
    end
    ok, first = nativeCall(GetVehicleTyresCanBurst, vehicle)
    if ok and type(first) == 'boolean' then setup.wheels.bulletproof = not first end
    ok, first = nativeCall(GetDriftTyresEnabled, vehicle)
    if ok and type(first) == 'boolean' then setup.wheels.driftTyres = first end

    local neonEnabled, completeNeon = {}, true
    for index = 0, 3 do
        ok, first = nativeCall(IsVehicleNeonLightEnabled, vehicle, index)
        if not ok or type(first) ~= 'boolean' then completeNeon = false break end
        neonEnabled[index + 1] = first
    end
    if completeNeon then setup.lighting.neon.enabled = neonEnabled end
    ok, first, second, third = nativeCall(GetVehicleNeonLightsColour, vehicle)
    if ok and validColourChannel(first) and validColourChannel(second) and validColourChannel(third) then
        setup.lighting.neon.colour = { r = first, g = second, b = third }
    end
    ok, first = nativeCall(IsToggleModOn, vehicle, Constants.Toggle.XENON)
    if ok and type(first) == 'boolean' then setup.lighting.xenon = first end
    ok, first = nativeCall(GetVehicleXenonLightsColor, vehicle)
    if ok and finiteNumber(first) then setup.lighting.xenonColour = first end
    ok, first = nativeCall(IsToggleModOn, vehicle, Constants.Toggle.TYRE_SMOKE)
    if ok and type(first) == 'boolean' then setup.lighting.tyreSmoke = first end
    ok, first, second, third = nativeCall(GetVehicleTyreSmokeColor, vehicle)
    if ok and validColourChannel(first) and validColourChannel(second) and validColourChannel(third) then
        setup.lighting.tyreSmokeColour = { r = first, g = second, b = third }
    end
    ok, first = nativeCall(GetVehicleWindowTint, vehicle)
    if ok and finiteNumber(first) then setup.lighting.windowTint = first end

    ok, first = nativeCall(GetVehicleLiveryCount, vehicle)
    first = ok and tonumber(first) or 0
    if first > 0 then
        local currentOk, current = nativeCall(GetVehicleLivery, vehicle)
        if currentOk then setup.liveries.native = current end
    end
    ok, first = nativeCall(GetNumVehicleMods, vehicle, 48)
    first = ok and tonumber(first) or 0
    if first > 0 then
        local currentOk, current = nativeCall(GetVehicleMod, vehicle, 48)
        if currentOk then setup.liveries.mod = current end
    end
    ok, first = nativeCall(GetVehicleRoofLivery, vehicle)
    if ok then setup.liveries.roof = first end
    ok, first = nativeCall(GetVehicleInteriorColour, vehicle)
    if ok then setup.paint.interior = first end
    ok, first = nativeCall(GetVehicleDashboardColour, vehicle)
    if ok then setup.paint.dashboard = first end

    ok, first = nativeCall(GetVehicleNumberPlateTextIndex, vehicle)
    if ok and finiteNumber(first) then setup.details.plateStyle = first end
    ok, first = nativeCall(GetVehicleNumberPlateText, vehicle)
    if ok and type(first) == 'string' then setup.details.plateText = first end
    ok, first = nativeCall(GetVehicleDirtLevel, vehicle)
    if ok and finiteNumber(first) then setup.details.dirtLevel = first end

    for modType = 0, 49 do
        if modType < 17 or modType > 22 then
            local countOk, count = nativeCall(GetNumVehicleMods, vehicle, modType)
            count = countOk and tonumber(count) or 0
            if count > 0 and modType ~= 23 and modType ~= 24 and modType ~= 48 then
                local currentOk, current = nativeCall(GetVehicleMod, vehicle, modType)
                if currentOk and finiteNumber(current) then
                    local target = (modType == 11 or modType == 12 or modType == 13 or modType == 15 or modType == 16)
                        and setup.performance or setup.bodyMods
                    target[tostring(modType)] = current
                end
            end
        end
    end
    for _, modType in ipairs(Constants.ToggleTypes) do
        local countOk, count = nativeCall(GetNumVehicleMods, vehicle, modType)
        count = countOk and tonumber(count) or 0
        if count > 0 then
            local toggleOk, enabled = nativeCall(IsToggleModOn, vehicle, modType)
            if toggleOk and type(enabled) == 'boolean' then setup.toggleMods[tostring(modType)] = enabled end
        end
    end
    local extrasOk, extras = pcall(buildExtrasState, vehicle)
    if extrasOk and type(extras) == 'table' then
        for _, item in ipairs(extras) do
            if type(item) == 'table' and isInteger(item.id) and type(item.enabled) == 'boolean' then
                setup.extras[tostring(item.id)] = item.enabled
            end
        end
    end

    local serializable, encoded = pcall(json.encode, setup)
    return serializable and type(encoded) == 'string' and setup or nil
end

local function validRgb(rgb)
    return type(rgb) == 'table' and validColourChannel(rgb.r) and validColourChannel(rgb.g) and validColourChannel(rgb.b)
end

local function safeSetMod(vehicle, modType, index, custom)
    if not isInteger(modType) or not isInteger(index) or modType < 0 or modType > 49 then return false end
    local count = tonumber(GetNumVehicleMods(vehicle, modType)) or 0
    if index < -1 or index >= count or modDisabled(overrideForModel(spawnedModel), modType, index) then return false end
    SetVehicleModKit(vehicle, 0)
    SetVehicleMod(vehicle, modType, index, custom == true)
    return true
end

local function applyStanceSnapshot(vehicle, stance, summary)
    if type(stance) ~= 'table' then return end
    local support = stanceSupport()
    if support.wheelSize and finiteNumber(stance.wheelSize) then nativeCall(SetVehicleWheelSize, vehicle, stance.wheelSize) summary.applied = summary.applied + 1 end
    if support.wheelWidth and finiteNumber(stance.wheelWidth) then nativeCall(SetVehicleWheelWidth, vehicle, stance.wheelWidth) summary.applied = summary.applied + 1 end
    if support.suspensionHeight and finiteNumber(stance.suspensionHeight) then nativeCall(SetVehicleSuspensionHeight, vehicle, stance.suspensionHeight) summary.applied = summary.applied + 1 end
    for _, wheel in pairs(type(stance.wheels) == 'table' and stance.wheels or {}) do
        if isInteger(wheel.index) and wheel.index >= 0 then
            if support.wheelOffset and finiteNumber(wheel.offset) then nativeCall(SetVehicleWheelXOffset, vehicle, wheel.index, wheel.offset) summary.applied = summary.applied + 1 end
            if support.wheelRotation and finiteNumber(wheel.rotation) then nativeCall(SetVehicleWheelYRotation, vehicle, wheel.index, wheel.rotation) summary.applied = summary.applied + 1 end
        end
    end
end

local function applyAdvancedSetup(vehicle, setup, allowCrossModel)
    local summary = { applied = 0, skipped = 0, unsupported = 0, invalid = 0 }
    if not vehicle or not DoesEntityExist(vehicle) or type(setup) ~= 'table' then return false, summary, 'Invalid setup.' end
    local model = setup.vehicleModel or setup.model
    if model ~= spawnedModel and allowCrossModel ~= true then return false, summary, 'This preset belongs to another model.' end
    SetVehicleModKit(vehicle, 0)
    local wheels = type(setup.wheels) == 'table' and setup.wheels or nil
    if wheels then
        if isInteger(wheels.type) and wheels.type >= 0 and wheels.type <= 64 then SetVehicleWheelType(vehicle, wheels.type) summary.applied = summary.applied + 1 end
        if isInteger(wheels.front) then
            if safeSetMod(vehicle, 23, wheels.front, wheels.frontCustomTyres) then summary.applied = summary.applied + 1 else summary.skipped = summary.skipped + 1 end
        end
        if GetNumVehicleMods(vehicle, 24) > 0 and isInteger(wheels.rear) then
            if safeSetMod(vehicle, 24, wheels.rear, wheels.rearCustomTyres) then summary.applied = summary.applied + 1 else summary.skipped = summary.skipped + 1 end
        end
        if type(wheels.bulletproof) == 'boolean' then SetVehicleTyresCanBurst(vehicle, not wheels.bulletproof) summary.applied = summary.applied + 1 end
        if type(wheels.driftTyres) == 'boolean' and type(SetDriftTyresEnabled) == 'function' then nativeCall(SetDriftTyresEnabled, vehicle, wheels.driftTyres) summary.applied = summary.applied + 1 end
    end

    for _, group in ipairs({ setup.bodyMods, setup.performance }) do
        if type(group) == 'table' then
            for key, index in pairs(group) do
                local modType = tonumber(key)
                if isInteger(modType) and isInteger(index) and safeSetMod(vehicle, modType, index, false) then summary.applied = summary.applied + 1
                else summary.skipped = summary.skipped + 1 end
            end
        end
    end
    if type(setup.toggleMods) == 'table' then
        for key, enabled in pairs(setup.toggleMods) do
            local modType = tonumber(key)
            if isInteger(modType) and type(enabled) == 'boolean' and GetNumVehicleMods(vehicle, modType) > 0 then
                ToggleVehicleMod(vehicle, modType, enabled) summary.applied = summary.applied + 1
            else summary.skipped = summary.skipped + 1 end
        end
    end

    local paint = type(setup.paint) == 'table' and setup.paint or {}
    if isInteger(paint.primaryIndex) and isInteger(paint.secondaryIndex) then
        SetVehicleColours(vehicle, clamp(paint.primaryIndex, 0, 255), clamp(paint.secondaryIndex, 0, 255)); summary.applied = summary.applied + 2
    end
    if isInteger(paint.pearlescent) and isInteger(paint.wheelColour) then SetVehicleExtraColours(vehicle, clamp(paint.pearlescent, 0, 255), clamp(paint.wheelColour, 0, 255)) end
    if isInteger(paint.primaryType) and isInteger(paint.primaryModColour) then SetVehicleModColor_1(vehicle, paint.primaryType, paint.primaryModColour, paint.primaryPearl or 0) end
    if isInteger(paint.secondaryType) and isInteger(paint.secondaryModColour) then SetVehicleModColor_2(vehicle, paint.secondaryType, paint.secondaryModColour) end
    if paint.primaryCustom == true and validRgb(paint.primaryRgb) then SetVehicleCustomPrimaryColour(vehicle, paint.primaryRgb.r, paint.primaryRgb.g, paint.primaryRgb.b)
    elseif paint.primaryCustom == false then ClearVehicleCustomPrimaryColour(vehicle) end
    if paint.secondaryCustom == true and validRgb(paint.secondaryRgb) then SetVehicleCustomSecondaryColour(vehicle, paint.secondaryRgb.r, paint.secondaryRgb.g, paint.secondaryRgb.b)
    elseif paint.secondaryCustom == false then ClearVehicleCustomSecondaryColour(vehicle) end
    if isInteger(paint.interior) then nativeCall(SetVehicleInteriorColour, vehicle, clamp(paint.interior, 0, 255)) end
    if isInteger(paint.dashboard) then nativeCall(SetVehicleDashboardColour, vehicle, clamp(paint.dashboard, 0, 255)) end

    local liveries = type(setup.liveries) == 'table' and setup.liveries or {}
    if isInteger(liveries.native) and liveries.native >= 0 and liveries.native < GetVehicleLiveryCount(vehicle) then SetVehicleLivery(vehicle, liveries.native) summary.applied = summary.applied + 1 end
    if isInteger(liveries.mod) and safeSetMod(vehicle, 48, liveries.mod, false) then summary.applied = summary.applied + 1 end
    local roofOk, roofCount = nativeCall(GetVehicleRoofLiveryCount, vehicle)
    if roofOk and isInteger(liveries.roof) and liveries.roof >= 0 and liveries.roof < roofCount then nativeCall(SetVehicleRoofLivery, vehicle, liveries.roof) summary.applied = summary.applied + 1 end
    if type(setup.extras) == 'table' then
        for key, enabled in pairs(setup.extras) do
            local id = tonumber(key)
            if isInteger(id) and type(enabled) == 'boolean' and DoesExtraExist(vehicle, id) then SetVehicleExtra(vehicle, id, not enabled) summary.applied = summary.applied + 1
            else summary.skipped = summary.skipped + 1 end
        end
    end
    if wheels then applyStanceSnapshot(vehicle, wheels.stance, summary) end

    local lighting = type(setup.lighting) == 'table' and setup.lighting or {}
    if type(lighting.neon) == 'table' then
        for index, enabled in ipairs(type(lighting.neon.enabled) == 'table' and lighting.neon.enabled or {}) do
            if index <= 4 and type(enabled) == 'boolean' then SetVehicleNeonLightEnabled(vehicle, index - 1, enabled) end
        end
        if validRgb(lighting.neon.colour) then SetVehicleNeonLightsColour(vehicle, lighting.neon.colour.r, lighting.neon.colour.g, lighting.neon.colour.b) end
    end
    if type(lighting.xenon) == 'boolean' and GetNumVehicleMods(vehicle, Constants.Toggle.XENON) > 0 then ToggleVehicleMod(vehicle, Constants.Toggle.XENON, lighting.xenon) end
    if isInteger(lighting.xenonColour) then nativeCall(SetVehicleXenonLightsColor, vehicle, lighting.xenonColour) end
    if type(lighting.tyreSmoke) == 'boolean' and GetNumVehicleMods(vehicle, Constants.Toggle.TYRE_SMOKE) > 0 then ToggleVehicleMod(vehicle, Constants.Toggle.TYRE_SMOKE, lighting.tyreSmoke) end
    if validRgb(lighting.tyreSmokeColour) then SetVehicleTyreSmokeColor(vehicle, lighting.tyreSmokeColour.r, lighting.tyreSmokeColour.g, lighting.tyreSmokeColour.b) end
    if isInteger(lighting.windowTint) and lighting.windowTint >= -1 and lighting.windowTint < (tonumber(GetNumVehicleWindowTints()) or 0) then SetVehicleWindowTint(vehicle, lighting.windowTint) end
    if type(setup.details) == 'table' then
        if isInteger(setup.details.plateStyle) then SetVehicleNumberPlateTextIndex(vehicle, clamp(setup.details.plateStyle, 0, 5)) end
        if type(setup.details.plateText) == 'string' then SetVehicleNumberPlateText(vehicle, setup.details.plateText:sub(1, 8)) end
        if finiteNumber(setup.details.dirtLevel) then SetVehicleDirtLevel(vehicle, clamp(setup.details.dirtLevel, 0.0, 15.0)) end
    end
    return true, summary
end

captureVehicleSetup = captureAdvancedSetup
applySetup = function(vehicle, setup)
    local ok, _, message = applyAdvancedSetup(vehicle, setup, false)
    return ok, message
end

local function presetStore()
    local value = kvpRead(Constants.Kvp.presets, {})
    return type(value) == 'table' and value or {}
end

local function presetMetadata()
    local list = {}
    for _, preset in ipairs(presetStore()) do
        if type(preset) == 'table' and type(preset.id) == 'string' and type(preset.name) == 'string' then
            list[#list + 1] = {
                id = preset.id, name = preset.name, favorite = preset.favorite == true,
                vehicleModel = preset.setup and preset.setup.vehicleModel,
                createdAt = preset.createdAt, updatedAt = preset.updatedAt
            }
        end
    end
    table.sort(list, function(a, b)
        if a.favorite ~= b.favorite then return a.favorite end
        return (a.updatedAt or 0) > (b.updatedAt or 0)
    end)
    return list
end

local function preferences()
    return {
        favorites = kvpRead(Constants.Kvp.favorites, {}),
        recents = kvpRead(Constants.Kvp.recents, {}),
        filters = kvpRead(Constants.Kvp.filters, {}),
        colours = kvpRead(Constants.Kvp.colours, {}),
        ui = kvpRead(Constants.Kvp.ui, { mode = Config.UI.DefaultMode or 'compact' })
    }
end

local function pushRecent(model)
    local recent, output = kvpRead(Constants.Kvp.recents, {}), { model }
    for _, item in ipairs(recent) do
        if item ~= model and #output < (tonumber(Config.UI.RecentVehicleLimit) or 20) then output[#output + 1] = item end
    end
    kvpWrite(Constants.Kvp.recents, output)
end

local function pushHistory(label, before, after)
    if historyReplaying or type(before) ~= 'table' or type(after) ~= 'table' then return end
    if json.encode(before) == json.encode(after) then return end
    historyUndo[#historyUndo + 1] = { label = label, before = clone(before), after = clone(after), model = spawnedModel }
    local limit = math.max(1, tonumber(Config.HistoryLimit) or 50)
    while #historyUndo > limit do table.remove(historyUndo, 1) end
    historyRedo = {}
end

local function withHistory(vehicle, label, action)
    local before = captureAdvancedSetup(vehicle)
    local ok, message, extra = action()
    if ok then pushHistory(label, before, captureAdvancedSetup(vehicle)) end
    return ok, message, extra
end

local stanceLimitsForModel

local function currentStanceState(vehicle)
    local baseline = spawnBaseline and spawnBaseline.wheels and spawnBaseline.wheels.stance or nil
    local mapping = advancedCapabilities and advancedCapabilities.wheelMap or wheelResolver(vehicle, spawnedModel)
    local current = captureStance(vehicle, mapping)
    local state = { support = stanceSupport(), baseline = baseline, current = current, controls = {}, limits = stanceLimitsForModel and stanceLimitsForModel() or clone(Config.Stance.Limits) }
    if baseline and current then
        if finiteNumber(baseline.wheelSize) and finiteNumber(current.wheelSize) then state.controls.wheelSize = { baseline = baseline.wheelSize, current = current.wheelSize, delta = current.wheelSize - baseline.wheelSize } end
        if finiteNumber(baseline.wheelWidth) and finiteNumber(current.wheelWidth) then state.controls.wheelWidth = { baseline = baseline.wheelWidth, current = current.wheelWidth, delta = current.wheelWidth - baseline.wheelWidth } end
        if finiteNumber(baseline.suspensionHeight) and finiteNumber(current.suspensionHeight) then state.controls.suspensionHeight = { baseline = baseline.suspensionHeight, current = current.suspensionHeight, delta = current.suspensionHeight - baseline.suspensionHeight } end
        state.individualWheels = {}
        for name, baseWheel in pairs(type(baseline.wheels) == 'table' and baseline.wheels or {}) do
            local currentWheel = current.wheels and current.wheels[name]
            if type(name) == 'string' and type(baseWheel) == 'table' and type(currentWheel) == 'table'
                and finiteNumber(baseWheel.offset) and finiteNumber(currentWheel.offset) then
                local direction = name:find('Left', 1, true) and -1.0 or 1.0
                local delta = (currentWheel.offset - baseWheel.offset) * direction
                local info = {
                    wheel = name, index = baseWheel.index, baseline = 0.0, current = delta, delta = delta,
                    baselineOffset = baseWheel.offset, currentOffset = currentWheel.offset
                }
                state.individualWheels[name] = info
                state.controls['wheelOffset:' .. name] = info
            end
        end
        for _, definition in ipairs({ { id = 'front', left = 'frontLeft', right = 'frontRight' }, { id = 'rear', left = 'rearLeft', right = 'rearRight' } }) do
            local bl, br = baseline.wheels and baseline.wheels[definition.left], baseline.wheels and baseline.wheels[definition.right]
            local cl, cr = current.wheels and current.wheels[definition.left], current.wheels and current.wheels[definition.right]
            if bl and br and cl and cr then
                local trackDelta = ((cr.offset - br.offset) - (cl.offset - bl.offset)) / 2.0
                state.controls[definition.id .. 'Track'] = { baseline = 0.0, current = trackDelta, delta = trackDelta, wheels = { definition.left, definition.right } }
                local leftDelta, rightDelta = cl.rotation - bl.rotation, cr.rotation - br.rotation
                local degrees = ((leftDelta - rightDelta) / 2.0) * 180.0 / math.pi
                state.controls[definition.id .. 'Camber'] = { baseline = 0.0, current = degrees, delta = degrees, wheels = { definition.left, definition.right } }
            end
        end
    end
    return state
end

local function diagnosticsState(vehicle, setup)
    local entry = getConfiguredVehicle(spawnedModel) or {}
    local networked = NetworkGetEntityIsNetworked(vehicle)
    local networkId = networked and NetworkGetNetworkIdFromEntity(vehicle) or nil
    local owner
    if networked then
        local ownerOk, value = nativeCall(NetworkGetEntityOwner, vehicle)
        if ownerOk then owner = value end
    end
    local modCounts = {}
    for modType = 0, 49 do
        local count = tonumber(GetNumVehicleMods(vehicle, modType)) or 0
        if count > 0 then modCounts[tostring(modType)] = count end
    end
    return {
        version = Config.Version, model = spawnedModel, modelHash = GetEntityModel(vehicle),
        displayName = VehicleLab.State.displayName or entry.label,
        manufacturer = VehicleLab.State.manufacturer or entry.manufacturer,
        sourceResource = VehicleLab.State.sourceResource or entry.resource,
        sourceType = VehicleLab.State.sourceType or entry.sourceType,
        ownership = VehicleLab.State.ownership,
        synchronized = VehicleLab.State.synchronized == true,
        capabilityWarnings = advancedCapabilities and advancedCapabilities.warnings or {},
        vehicleClass = GetVehicleClass(vehicle), vehicleType = advancedCapabilities and advancedCapabilities.vehicleType,
        entityExists = true, networked = networked, networkId = networkId, entityOwner = owner,
        wheelCount = advancedCapabilities and advancedCapabilities.wheelCount,
        wheelMapping = advancedCapabilities and advancedCapabilities.wheelMap,
        modKit = GetVehicleModKit(vehicle), modSlots = modCounts,
        nativeLiveryCount = GetVehicleLiveryCount(vehicle), slot48LiveryCount = GetNumVehicleMods(vehicle, 48),
        roofLiveryCount = advancedCapabilities and advancedCapabilities.liveries.roof and advancedCapabilities.liveries.roof.count or 0,
        extras = advancedCapabilities and advancedCapabilities.extras,
        turbo = IsToggleModOn(vehicle, Constants.Toggle.TURBO), xenon = IsToggleModOn(vehicle, Constants.Toggle.XENON),
        tyreSmoke = IsToggleModOn(vehicle, Constants.Toggle.TYRE_SMOKE),
        wheelType = GetVehicleWheelType(vehicle), frontWheel = GetVehicleMod(vehicle, 23), rearWheel = GetVehicleMod(vehicle, 24),
        stance = currentStanceState(vehicle), paint = setup and setup.paint, lighting = setup and setup.lighting
    }
end

local legacyBuildVehicleState = buildVehicleState
buildVehicleState = function()
    local vehicle = getVehicle()
    local synchronized = vehicle ~= nil and VehicleLab.State.synchronized == true
    local activeVehicle = synchronized and {
        model = VehicleLab.State.model,
        modelHash = VehicleLab.State.modelHash,
        displayName = VehicleLab.State.displayName or VehicleLab.State.model,
        manufacturer = VehicleLab.State.manufacturer,
        sourceResource = VehicleLab.State.sourceResource,
        sourceType = VehicleLab.State.sourceType,
        ownership = VehicleLab.State.ownership
    } or nil
    local common = {
        revision = VehicleLab.State.revision,
        version = Config.Version,
        hasVehicle = synchronized,
        vehicleSynchronized = synchronized,
        model = synchronized and spawnedModel or nil,
        activeVehicle = activeVehicle,
        capabilities = synchronized and advancedCapabilities or nil,
        history = { undo = #historyUndo, redo = #historyRedo, undoLabel = historyUndo[#historyUndo] and historyUndo[#historyUndo].label, redoLabel = historyRedo[#historyRedo] and historyRedo[#historyRedo].label },
        preferences = preferences(), presets = presetMetadata(),
        config = { stance = Config.Stance, panelMode = Config.UI.DefaultMode, advancedPermission = advancedPermission },
        cameraEnabled = Config.AutoTuningCamera == true
    }
    if not synchronized then
        common.liveries, common.body, common.extras = {}, {}, {}
        return common
    end
    if not advancedCapabilities or advancedCapabilities.model ~= spawnedModel then advancedCapabilities = scanAdvancedCapabilities(vehicle) end
    advancedCapabilities = type(advancedCapabilities) == 'table' and advancedCapabilities or {
        model = spawnedModel, displayName = VehicleLab.State.displayName or spawnedModel,
        mods = {}, bodyMods = {}, performanceMods = {}, toggleMods = {}, wheelTypes = {}, liveries = {}, extras = {}
    }
    VehicleLab.State.capabilities = advancedCapabilities
    VehicleLab.State.baseline = spawnBaseline
    for _, item in ipairs(advancedCapabilities.mods or {}) do
        local ok, current = nativeCall(GetVehicleMod, vehicle, item.modType)
        if ok then item.current = current end
    end
    for _, item in ipairs(advancedCapabilities.toggleMods or {}) do
        local ok, enabled = nativeCall(IsToggleModOn, vehicle, item.modType)
        if ok then item.enabled = enabled == true end
    end
    if advancedCapabilities.liveries.native then
        local ok, current = nativeCall(GetVehicleLivery, vehicle)
        if ok then advancedCapabilities.liveries.native.current = current end
    end
    if advancedCapabilities.liveries.mod then
        local ok, current = nativeCall(GetVehicleMod, vehicle, 48)
        if ok then advancedCapabilities.liveries.mod.current = current end
    end
    if advancedCapabilities.liveries.roof then
        local roofOk, roof = nativeCall(GetVehicleRoofLivery, vehicle)
        if roofOk then advancedCapabilities.liveries.roof.current = roof end
    end
    common.capabilities = advancedCapabilities
    local setupOk, setup = pcall(captureAdvancedSetup, vehicle, advancedCapabilities)
    if not setupOk then setup = VehicleLab.State.currentSetup end
    VehicleLab.State.currentSetup = type(setup) == 'table' and setup or nil
    common.setup = setup
    common.currentSetup = setup
    common.body = advancedCapabilities and advancedCapabilities.bodyMods or {}
    common.performance = advancedCapabilities and advancedCapabilities.performanceMods or {}
    local extrasOk, extras = pcall(buildExtrasState, vehicle)
    common.extras = extrasOk and extras or (advancedCapabilities.extras or {})
    common.liveries = advancedCapabilities and advancedCapabilities.liveries or {}
    local stanceOk, stance = pcall(currentStanceState, vehicle)
    common.stance = stanceOk and stance or { support = stanceSupport(), controls = {} }
    local diagnosticsOk, diagnostics = pcall(diagnosticsState, vehicle, setup)
    common.diagnostics = diagnosticsOk and diagnostics or VehicleLab.State.diagnostics
    VehicleLab.State.diagnostics = common.diagnostics
    common.cameraEnabled = Config.AutoTuningCamera == true
    return common
end

publishActiveVehicleState = function(reason)
    local snapshot = buildVehicleState()
    SendNUIMessage({
        action = 'activeVehicleChanged',
        reason = reason,
        active = snapshot.activeVehicle ~= nil,
        activeVehicle = snapshot.activeVehicle,
        vehicle = snapshot.activeVehicle,
        capabilities = snapshot.capabilities,
        currentSetup = snapshot.currentSetup,
        setup = snapshot.currentSetup,
        diagnostics = snapshot.diagnostics,
        state = snapshot
    })
    return snapshot
end

clearActiveVehicleState = function(reason, notifyNui)
    local previous = VehicleLab.State.vehicle
    VehicleLab.State.spawnSessionId = (tonumber(VehicleLab.State.spawnSessionId) or 0) + 1
    clearActiveVehicle(previous)
    VehicleLab.State.ownership = nil
    VehicleLab.State.displayName = nil
    VehicleLab.State.manufacturer = nil
    VehicleLab.State.sourceResource = nil
    VehicleLab.State.sourceType = nil
    VehicleLab.State.currentSetup = nil
    VehicleLab.State.diagnostics = nil
    VehicleLab.State.capabilities = nil
    VehicleLab.State.baseline = nil
    VehicleLab.State.synchronized = false
    VehicleLab.State.isInitializingVehicle = false
    advancedCapabilities, spawnBaseline, stockVisualSetup = nil, nil, nil
    confirmedTuning, historyUndo, historyRedo, sessionUnsafe = {}, {}, {}, {}
    bodyPreviewOriginal = {}
    stancePreviewSessions = {}
    stancePreviewSequences = {}
    stancePreviewBarrier = -1
    destroyTuningCamera()
    debugLog('active vehicle cleared: %s', tostring(reason or 'unspecified'))
    if notifyNui == true then
        local snapshot = publishActiveVehicleState(reason or 'cleared')
        if reason == 'entity-invalid' then
            SendNUIMessage({ action = 'toast', type = 'warning', message = 'The active vehicle no longer exists.' })
        end
        return snapshot
    end
    return buildVehicleState()
end

local function resolveActiveVehicleMetadata(vehicle, options)
    local _, modelHash = nativeCall(GetEntityModel, vehicle)
    modelHash = tonumber(modelHash)
    if not modelHash then return nil end
    local entry = getConfiguredVehicle(options.model) or getConfiguredVehicleByHash(modelHash)
    local model = entry and entry.model or options.model
    if not validModelName(model) then model = ('hash_%s'):format(tostring(modelHash):gsub('%-', 'n')) end
    local displayName = entry and entry.label or nil
    if not displayName then
        local displayOk, displayKey = nativeCall(GetDisplayNameFromVehicleModel, modelHash)
        if displayOk then displayName = resolveTextLabel(displayKey) or (trim(displayKey) ~= '' and displayKey or nil) end
    end
    local manufacturer = entry and entry.manufacturer or nil
    if not manufacturer then
        local makeOk, makeKey = nativeCall(GetMakeNameFromVehicleModel, modelHash)
        if makeOk then manufacturer = resolveTextLabel(makeKey) or nil end
    end
    return {
        model = model, modelHash = modelHash, displayName = displayName or formatModelName(model),
        manufacturer = manufacturer, sourceResource = entry and entry.resource or 'External',
        sourceType = entry and entry.sourceType or 'external', entry = entry
    }
end

activateVehicleForVehicleLab = function(vehicle, options)
    options = type(options) == 'table' and options or {}
    if not validActiveVehicle(vehicle) then return false, 'The selected entity is not a valid vehicle.' end
    local ownership = options.ownership == 'spawned' and 'spawned' or 'adopted'
    debugLog('Activating vehicle entity=%s ownership=%s', tostring(vehicle), ownership)
    local metadata = resolveActiveVehicleMetadata(vehicle, options)
    if not metadata then return false, 'The vehicle model could not be identified.' end

    local previous = getActiveVehicle()
    if previous and previous ~= vehicle then
        if VehicleLab.State.ownership == 'spawned' then
            local deleted, deleteError = deleteTrackedVehicle(false)
            if not deleted then return false, deleteError end
        else
            clearActiveVehicleState('replaced', false)
        end
    end

    VehicleLab.State.spawnSessionId = (tonumber(VehicleLab.State.spawnSessionId) or 0) + 1
    local spawnSessionId = VehicleLab.State.spawnSessionId
    VehicleLab.State.isInitializingVehicle = true
    if not setActiveVehicle(vehicle, metadata.model, metadata.modelHash) then
        VehicleLab.State.isInitializingVehicle = false
        return false, 'VehicleLab could not store the active vehicle entity.'
    end
    VehicleLab.State.ownership = ownership
    VehicleLab.State.displayName = metadata.displayName
    VehicleLab.State.manufacturer = metadata.manufacturer
    VehicleLab.State.sourceResource = metadata.sourceResource
    VehicleLab.State.sourceType = metadata.sourceType
    VehicleLab.State.synchronized = false
    advancedCapabilities, spawnBaseline, stockVisualSetup = nil, nil, nil
    bodyPreviewOriginal = {}
    stancePreviewSessions = {}
    stancePreviewSequences = {}
    stancePreviewBarrier = -1
    confirmedTuning, historyUndo, historyRedo, sessionUnsafe = {}, {}, {}, {}
    destroyTuningCamera()
    nativeCall(SetVehicleModKit, vehicle, 0)
    if ownership == 'spawned' then nativeCall(SetEntityAsMissionEntity, vehicle, true, true) end
    debugLog('Active vehicle stored model=%s', metadata.model)

    local warnings = {}
    local baselineOk, baseline = xpcall(function() return captureAdvancedSetup(vehicle) end, errorTrace)
    if not baselineOk or type(baseline) ~= 'table' then
        warnings[#warnings + 1] = 'baseline capture was unavailable'
        baseline = nil
    else
        debugLog('Baseline captured')
    end
    local scanOk, capabilities, scanWarnings = xpcall(function()
        local value, sectionWarnings = scanAdvancedCapabilities(vehicle)
        return value, sectionWarnings
    end, errorTrace)
    if not scanOk or type(capabilities) ~= 'table' then
        warnings[#warnings + 1] = 'capability scan was unavailable'
        capabilities = {
            model = metadata.model, displayName = metadata.displayName, manufacturer = metadata.manufacturer,
            sourceResource = metadata.sourceResource, sourceType = metadata.sourceType,
            mods = {}, bodyMods = {}, performanceMods = {}, toggleMods = {}, wheelTypes = {}, liveries = {}, extras = {}, warnings = warnings
        }
    elseif type(scanWarnings) == 'table' then
        for _, warning in ipairs(scanWarnings) do warnings[#warnings + 1] = warning end
    end

    if VehicleLab.State.spawnSessionId ~= spawnSessionId or getActiveVehicle() ~= vehicle
        or VehicleLab.State.modelHash ~= metadata.modelHash then
        return false, 'The active vehicle changed before initialization completed.'
    end
    advancedCapabilities = capabilities
    advancedCapabilities.warnings = warnings
    spawnBaseline = baseline
    stockVisualSetup = baseline and clone(baseline) or nil
    VehicleLab.State.capabilities = capabilities
    VehicleLab.State.baseline = baseline
    local setupOk, currentSetup = pcall(captureAdvancedSetup, vehicle, capabilities)
    VehicleLab.State.currentSetup = setupOk and currentSetup or baseline
    local diagnosticsOk, diagnostics = pcall(diagnosticsState, vehicle, VehicleLab.State.currentSetup)
    VehicleLab.State.diagnostics = diagnosticsOk and diagnostics or { model = metadata.model, warnings = warnings }
    VehicleLab.State.synchronized = true
    VehicleLab.State.isInitializingVehicle = false
    VehicleLab.State.revision = VehicleLab.State.revision + 1
    local snapshot = publishActiveVehicleState(options.reason or ownership)
    debugLog('Capability scan complete body=%d extras=%d', #(capabilities.bodyMods or {}), #(capabilities.extras or {}))
    debugLog('Active vehicle sent to NUI')
    if metadata.entry then pushRecent(metadata.model) end
    debugLog('activated %s vehicle %s with %d capability warning(s)', ownership, metadata.model, #warnings)
    return true, ('Active vehicle: %s.'):format(metadata.displayName), { state = snapshot, warnings = warnings }
end

refreshActiveVehicleCapabilities = function(reason)
    local vehicle = getActiveVehicle()
    if not vehicle then return false, 'No active VehicleLab vehicle exists.' end
    VehicleLab.State.spawnSessionId = (tonumber(VehicleLab.State.spawnSessionId) or 0) + 1
    local spawnSessionId = VehicleLab.State.spawnSessionId
    VehicleLab.State.isInitializingVehicle = true
    nativeCall(SetVehicleModKit, vehicle, 0)
    local scanOk, capabilities, warnings = xpcall(function()
        local value, scanWarnings = scanAdvancedCapabilities(vehicle)
        return value, scanWarnings
    end, errorTrace)
    if VehicleLab.State.spawnSessionId ~= spawnSessionId or getActiveVehicle() ~= vehicle then
        return false, 'The active vehicle changed while capabilities were refreshing.'
    end
    if not scanOk or type(capabilities) ~= 'table' then
        VehicleLab.State.isInitializingVehicle = false
        return false, 'Capability refresh failed; the active vehicle was preserved.'
    end
    advancedCapabilities = capabilities
    VehicleLab.State.capabilities = capabilities
    if not spawnBaseline then
        local baselineOk, baseline = pcall(captureAdvancedSetup, vehicle, capabilities)
        if baselineOk then
            spawnBaseline, stockVisualSetup = baseline, clone(baseline)
            VehicleLab.State.baseline = baseline
        end
    end
    local setupOk, setup = pcall(captureAdvancedSetup, vehicle, capabilities)
    if setupOk then VehicleLab.State.currentSetup = setup end
    local diagnosticsOk, diagnostics = pcall(diagnosticsState, vehicle, VehicleLab.State.currentSetup)
    if diagnosticsOk then VehicleLab.State.diagnostics = diagnostics end
    VehicleLab.State.synchronized = true
    VehicleLab.State.isInitializingVehicle = false
    VehicleLab.State.revision = VehicleLab.State.revision + 1
    local snapshot = publishActiveVehicleState(reason or 'capabilities-refreshed')
    warnings = type(warnings) == 'table' and warnings or {}
    local message = #warnings > 0
        and ('Vehicle capabilities refreshed with %d warning(s).'):format(#warnings)
        or 'Vehicle capabilities refreshed.'
    return true, message, { state = snapshot, warnings = warnings }
end

local function adoptCurrentVehicle(reason)
    local targeting = Config.VehicleTargeting or {}
    if targeting.AllowCurrentVehicleAdoption == false then
        return false, 'Current-vehicle adoption is disabled in VehicleLab configuration.'
    end
    local pedOk, playerPed = nativeCall(PlayerPedId)
    local existsOk, playerExists = nativeCall(DoesEntityExist, playerPed)
    if not pedOk or not playerPed or playerPed == 0 or not existsOk or not nativeBoolean(playerExists) then
        return false, 'The player entity is not ready.'
    end
    local vehicleOk, vehicle = nativeCall(GetVehiclePedIsIn, playerPed, false)
    if not vehicleOk or not validActiveVehicle(vehicle) then
        return false, 'Enter a vehicle before using it in VehicleLab.'
    end
    if targeting.RequireDriverSeat ~= false then
        local seatOk, driver = nativeCall(GetPedInVehicleSeat, vehicle, -1)
        if not seatOk or driver ~= playerPed then return false, 'You must be in the driver seat to adopt this vehicle.' end
    end
    local ok, message, result = activateVehicleForVehicleLab(vehicle, { ownership = 'adopted', reason = reason or 'adopted-current' })
    if ok then message = 'Current vehicle adopted by VehicleLab.' end
    return ok, message, result
end

local function releaseActiveVehicle(reason)
    if not getActiveVehicle() then return false, 'No active VehicleLab vehicle exists.' end
    clearActiveVehicleState(reason or 'released', true)
    return true, 'Active vehicle released.', { state = buildVehicleState() }
end

finalizeSpawnTransaction = function()
    if type(activeSpawnTransaction) ~= 'table' then return end
    activeSpawnTransaction.uiUpdated = true
    activeSpawnTransaction.completedAtMs = monotonicMilliseconds()
    activeSpawnTransaction = nil
end

cleanupSpawnTransaction = function(transaction, reason)
    transaction = type(transaction) == 'table' and transaction or {}
    local partialVehicle = transaction.createdVehicle
    local existsOk, exists = nativeCall(DoesEntityExist, partialVehicle)
    if existsOk and nativeBoolean(exists) then
        local networkedOk, networked = nativeCall(NetworkGetEntityIsNetworked, partialVehicle)
        local controlOk, hasControl = nativeCall(NetworkHasControlOfEntity, partialVehicle)
        if networkedOk and nativeBoolean(networked) and (not controlOk or not nativeBoolean(hasControl)) then
            nativeCall(NetworkRequestControlOfEntity, partialVehicle)
            local deadline = monotonicMilliseconds() + 750
            while monotonicMilliseconds() < deadline do
                local stillExistsOk, stillExists = nativeCall(DoesEntityExist, partialVehicle)
                local controlledOk, controlled = nativeCall(NetworkHasControlOfEntity, partialVehicle)
                if not stillExistsOk or not nativeBoolean(stillExists) or (controlledOk and nativeBoolean(controlled)) then break end
                Wait(0)
                nativeCall(NetworkRequestControlOfEntity, partialVehicle)
            end
        end
        nativeCall(SetEntityAsMissionEntity, partialVehicle, true, true)
        nativeCall(DeleteVehicle, partialVehicle)
        local remainsOk, remains = nativeCall(DoesEntityExist, partialVehicle)
        if remainsOk and nativeBoolean(remains) then nativeCall(DeleteEntity, partialVehicle) end
    end
    if transaction.modelHash then nativeCall(SetModelAsNoLongerNeeded, transaction.modelHash) end

    local replacedPrevious = transaction.createdVehicle ~= nil or transaction.previousVehicleRemoved == true
    if replacedPrevious then
        clearActiveVehicleState('spawn-failed', false)
        pcall(SendNUIMessage, { action = 'spawnFailed' })
    else
        if transaction.previousVehicle then
            setActiveVehicle(transaction.previousVehicle, transaction.previousModel, transaction.previousModelHash)
            VehicleLab.State.ownership = transaction.previousOwnership
            VehicleLab.State.displayName = transaction.previousDisplayName
            VehicleLab.State.manufacturer = transaction.previousManufacturer
            VehicleLab.State.sourceResource = transaction.previousSourceResource
            VehicleLab.State.sourceType = transaction.previousSourceType
        else
            clearActiveVehicle()
        end
        advancedCapabilities, spawnBaseline = transaction.previousCapabilities, transaction.previousBaseline
        VehicleLab.State.capabilities, VehicleLab.State.baseline = transaction.previousCapabilities, transaction.previousBaseline
        VehicleLab.State.currentSetup, VehicleLab.State.diagnostics = transaction.previousCurrentSetup, transaction.previousDiagnostics
        stockVisualSetup = transaction.previousStockVisualSetup
        confirmedTuning = transaction.previousConfirmedTuning or {}
        historyUndo, historyRedo, sessionUnsafe = transaction.previousUndo or {}, transaction.previousRedo or {}, transaction.previousUnsafe or {}
        VehicleLab.State.synchronized = transaction.previousSynchronized == true
    end
    activeSpawnTransaction = nil
    recoverRuntimeState(false, false)
    pcall(sendState)
    debugLog('rolled back failed spawn for %s: %s', tostring(transaction.model), tostring(reason))
end

local legacySpawnConfiguredVehicle = spawnConfiguredVehicle
spawnConfiguredVehicle = function(entry)
    local transaction = {
        model = entry and entry.model,
        startedAtMs = monotonicMilliseconds(),
        previousVehicle = getVehicle(),
        previousModel = spawnedModel,
        previousModelHash = VehicleLab.State.modelHash,
        previousOwnership = VehicleLab.State.ownership,
        previousDisplayName = VehicleLab.State.displayName,
        previousManufacturer = VehicleLab.State.manufacturer,
        previousSourceResource = VehicleLab.State.sourceResource,
        previousSourceType = VehicleLab.State.sourceType,
        previousCurrentSetup = VehicleLab.State.currentSetup,
        previousDiagnostics = VehicleLab.State.diagnostics,
        previousCapabilities = advancedCapabilities,
        previousBaseline = spawnBaseline,
        previousStockVisualSetup = stockVisualSetup,
        previousConfirmedTuning = confirmedTuning,
        previousUndo = historyUndo,
        previousRedo = historyRedo,
        previousUnsafe = sessionUnsafe,
        previousSynchronized = VehicleLab.State.synchronized == true
    }
    activeSpawnTransaction = transaction

    local callOk, ok, message = xpcall(function()
        return legacySpawnConfiguredVehicle(entry)
    end, errorTrace)
    if not callOk then
        cleanupSpawnTransaction(transaction, ok)
        return false, 'Vehicle spawning failed during entity creation.'
    end
    if not ok then
        if transaction.vehicleCreationAttempted or transaction.createdVehicle or transaction.previousVehicleRemoved then
            cleanupSpawnTransaction(transaction, message)
        else
            if transaction.modelHash then nativeCall(SetModelAsNoLongerNeeded, transaction.modelHash) end
            activeSpawnTransaction = nil
        end
        return false, message
    end

    local activated, activationMessage, activationResult = activateVehicleForVehicleLab(transaction.createdVehicle, {
        ownership = 'spawned', model = entry.model, reason = 'spawned'
    })
    if not activated then
        cleanupSpawnTransaction(transaction, activationMessage)
        return false, activationMessage
    end
    transaction.baselineCaptured = true
    debugLog('spawn baseline captured for %s in %.3fs', entry.model,
        (monotonicMilliseconds() - transaction.startedAtMs) / 1000.0)
    return true, message or activationMessage, activationResult
end

local legacyDeleteTrackedVehicle = deleteTrackedVehicle
deleteTrackedVehicle = function(notifyNui)
    local ok, message = legacyDeleteTrackedVehicle()
    if ok then
        clearActiveVehicleState('deleted', notifyNui ~= false)
    end
    return ok, message
end

local rawSetMenuOpen = setMenuOpen
setMenuOpen = function(open)
    if open == true and Config.Permissions.RequireAce == true then
        TriggerServerEvent('vehiclelab:server:checkPermission', 'open')
        return
    end
    if open ~= true then screenshotMode, hideHudForScreenshot = false, false end
    rawSetMenuOpen(open)
end

local rawForceCloseMenu = forceCloseMenu
forceCloseMenu = function(clearState)
    screenshotMode, hideHudForScreenshot = false, false
    if recoverRuntimeState then
        recoverRuntimeState(true, clearState)
        debugLog('menu force-closed and runtime state recovered')
    else
        rawForceCloseMenu(clearState)
    end
end

RegisterNetEvent(Constants.Events.permission, function(result)
    if type(result) ~= 'table' then return end
    if result.action == 'open' then
        if result.allowed then rawSetMenuOpen(true) else SendNUIMessage({ action = 'toast', type = 'error', message = 'You do not have permission to open VehicleLab.' }) end
    elseif result.action == 'advanced' then
        advancedPermission = result.allowed == true
        sendState()
    elseif result.action == 'refresh' and not result.allowed then
        SendNUIMessage({ action = 'toast', type = 'error', message = 'You do not have permission to refresh the catalogue.' })
    end
end)

local function respondState(respond, ok, message, extra)
    if ok then
        sendState()
        local payload = success(message, buildVehicleState())
        if finalizeSpawnTransaction then finalizeSpawnTransaction() end
        if type(extra) == 'table' then for key, value in pairs(extra) do payload[key] = value end end
        respond(payload)
    else
        respond(failure(message or 'The requested action failed.', buildVehicleState()))
    end
end

local function applyBodyAction(vehicle, data)
    local modType, index = tonumber(data.modType), tonumber(data.index)
    if not isInteger(modType) or not isInteger(index) then return false, 'Invalid body modification.' end
    if data.operation == 'preview' then
        if bodyPreviewOriginal[modType] == nil then bodyPreviewOriginal[modType] = GetVehicleMod(vehicle, modType) end
        if not safeSetMod(vehicle, modType, index, false) then return false, 'That body option is unavailable.' end
        return true
    elseif data.operation == 'revert' then
        local original = bodyPreviewOriginal[modType]
        if original == nil or not safeSetMod(vehicle, modType, original, false) then return false, 'There is no preview to revert.' end
        bodyPreviewOriginal[modType] = nil
        return true, 'Preview reverted.'
    elseif data.operation == 'confirm' then
        local current = GetVehicleMod(vehicle, modType)
        if current ~= index or not safeSetMod(vehicle, modType, index, false) then return false, 'That preview is no longer valid.' end
        local after = captureAdvancedSetup(vehicle)
        local before = clone(after)
        before.bodyMods[tostring(modType)] = bodyPreviewOriginal[modType] == nil and current or bodyPreviewOriginal[modType]
        bodyPreviewOriginal[modType] = nil
        pushHistory(MOD_FALLBACKS[modType] or ('Modification %d'):format(modType), before, after)
        return true, 'Body option confirmed.'
    elseif data.operation == 'unsafe' then
        if index < 0 then return false, 'Stock cannot be marked unsafe.' end
        sessionUnsafe[modType] = sessionUnsafe[modType] or {}
        sessionUnsafe[modType][index] = true
        if GetVehicleMod(vehicle, modType) == index then safeSetMod(vehicle, modType, -1, false) end
        advancedCapabilities = scanAdvancedCapabilities(vehicle)
        return true, 'Option skipped for this session.'
    elseif data.operation == 'clearUnsafe' then
        sessionUnsafe = {}
        advancedCapabilities = scanAdvancedCapabilities(vehicle)
        return true, 'Session unsafe list cleared.'
    end
    return false, 'Unknown body action.'
end

local function applyWheelAction(vehicle, data)
    return withHistory(vehicle, 'Wheels', function()
        if data.operation == 'type' then
            local wheelType = tonumber(data.wheelType)
            local allowed = false
            for _, item in ipairs(advancedCapabilities.wheelTypes or {}) do if item.id == wheelType then allowed = true break end end
            if not allowed then return false, 'That wheel category is unavailable.' end
            local stance = captureStance(vehicle, advancedCapabilities.wheelMap)
            SetVehicleWheelType(vehicle, wheelType)
            local count = GetNumVehicleMods(vehicle, 23)
            local index = tonumber(data.index) or -1
            if index < -1 or index >= count then index = -1 end
            SetVehicleMod(vehicle, 23, index, data.customTyres == true)
            if GetNumVehicleMods(vehicle, 24) > 0 then
                local rear = tonumber(data.rearIndex) or -1
                if rear >= -1 and rear < GetNumVehicleMods(vehicle, 24) then SetVehicleMod(vehicle, 24, rear, data.customTyres == true) end
            end
            applyStanceSnapshot(vehicle, stance, { applied = 0 })
            advancedCapabilities = scanAdvancedCapabilities(vehicle)
            return true, 'Wheel category updated.'
        elseif data.operation == 'model' then
            local modType = data.axle == 'rear' and 24 or 23
            if modType == 24 and GetNumVehicleMods(vehicle, 24) <= 0 then return false, 'Separate rear wheels are unavailable.' end
            if not safeSetMod(vehicle, modType, tonumber(data.index), data.customTyres == true) then return false, 'That wheel is unavailable.' end
            if data.linked == true and modType == 23 and GetNumVehicleMods(vehicle, 24) > 0 then
                local rearCount = GetNumVehicleMods(vehicle, 24)
                if data.index >= -1 and data.index < rearCount then safeSetMod(vehicle, 24, data.index, data.customTyres == true) end
            end
            return true, 'Wheel model updated.'
        elseif data.operation == 'bulletproof' and type(data.enabled) == 'boolean' then
            SetVehicleTyresCanBurst(vehicle, not data.enabled)
            return true, data.enabled and 'Bulletproof tyres enabled.' or 'Bulletproof tyres disabled.'
        elseif data.operation == 'drift' and type(data.enabled) == 'boolean' and type(SetDriftTyresEnabled) == 'function' then
            nativeCall(SetDriftTyresEnabled, vehicle, data.enabled)
            return true, data.enabled and 'Drift tyres enabled.' or 'Drift tyres disabled.'
        elseif data.operation == 'reset' and spawnBaseline and spawnBaseline.wheels then
            local partial = { vehicleModel = spawnedModel, wheels = clone(spawnBaseline.wheels) }
            local ok = applyAdvancedSetup(vehicle, partial, false)
            advancedCapabilities = scanAdvancedCapabilities(vehicle)
            return ok, ok and 'Wheels restored to spawn state.' or 'Wheels could not be restored.'
        end
        return false, 'Invalid wheel action.'
    end)
end

stanceLimitsForModel = function()
    local limits = clone(Config.Stance.Limits) or {}
    local override = overrideForModel(spawnedModel)
    if type(override.stanceLimits) == 'table' then
        for key, value in pairs(override.stanceLimits) do if type(value) == 'table' then limits[key] = clone(value) end end
    end
    return limits
end

local function applyStanceAction(vehicle, data)
    if Config.Stance.Enabled == false or overrideForModel(spawnedModel).stanceEnabled == false then return false, 'Stance is disabled for this model.' end
    if not spawnBaseline or not spawnBaseline.wheels or not spawnBaseline.wheels.stance then return false, 'The stance baseline is unavailable.' end
    local baseline, support = spawnBaseline.wheels.stance, stanceSupport()
    local limits, absolute = stanceLimitsForModel(), Config.Stance.AbsoluteLimits
    local function setWheelOffset(name, value)
        local baseWheel = type(baseline.wheels) == 'table' and baseline.wheels[name]
        if not baseWheel or not isInteger(baseWheel.index) or not finiteNumber(baseWheel.offset) then
            return false, 'That wheel mapping is unavailable.'
        end
        value = clamp(value, limits.trackDelta.min, limits.trackDelta.max)
        local direction = name:find('Left', 1, true) and -1.0 or 1.0
        local rawValue = clamp(baseWheel.offset + (value * direction), absolute.wheelOffset.min, absolute.wheelOffset.max)
        local ok = nativeCall(SetVehicleWheelXOffset, vehicle, baseWheel.index, rawValue)
        if not ok then return false, 'The wheel position native failed.' end
        return true, nil, (rawValue - baseWheel.offset) * direction
    end

    local function applyValue(control, requestedValue, wheel, rangeMode)
        local value = tonumber(requestedValue)
        if not finiteNumber(value) then return false, 'Stance values must be finite numbers.' end
        local extended = rangeMode == 'extended' and Config.Stance.UI and Config.Stance.UI.ExtendedLimits or nil
        if control == 'wheelSize' and support.wheelSize and finiteNumber(baseline.wheelSize) then
            local range = extended and extended.wheelSizeDelta or limits.wheelSizeDelta
            value = clamp(value, range.min, range.max)
            local actual = clamp(baseline.wheelSize + value, absolute.wheelSize.min, absolute.wheelSize.max)
            if not nativeCall(SetVehicleWheelSize, vehicle, actual) then return false, 'Wheel size could not be applied.' end
            return true, nil, actual - baseline.wheelSize, actual
        elseif control == 'wheelWidth' and support.wheelWidth and finiteNumber(baseline.wheelWidth) then
            local range = extended and extended.wheelWidthDelta or limits.wheelWidthDelta
            value = clamp(value, range.min, range.max)
            local actual = clamp(baseline.wheelWidth + value, absolute.wheelWidth.min, absolute.wheelWidth.max)
            if not nativeCall(SetVehicleWheelWidth, vehicle, actual) then return false, 'Wheel width could not be applied.' end
            return true, nil, actual - baseline.wheelWidth, actual
        elseif control == 'suspensionHeight' and support.suspensionHeight and finiteNumber(baseline.suspensionHeight) then
            value = clamp(value, limits.suspensionHeightDelta.min, limits.suspensionHeightDelta.max)
            local actual = clamp(baseline.suspensionHeight + value, absolute.suspensionHeight.min, absolute.suspensionHeight.max)
            if not nativeCall(SetVehicleSuspensionHeight, vehicle, actual) then return false, 'Suspension height could not be applied.' end
            return true, nil, actual - baseline.suspensionHeight, actual
        elseif (control == 'frontTrack' or control == 'rearTrack') and advancedCapabilities.stance.axleControls then
            value = clamp(value, limits.trackDelta.min, limits.trackDelta.max)
            local leftName = control == 'frontTrack' and 'frontLeft' or 'rearLeft'
            local rightName = control == 'frontTrack' and 'frontRight' or 'rearRight'
            local leftOk, leftMessage = setWheelOffset(leftName, value)
            if not leftOk then return false, leftMessage end
            local rightOk, rightMessage = setWheelOffset(rightName, value)
            if not rightOk then return false, rightMessage end
            return true, nil, value, value
        elseif (control == 'frontCamber' or control == 'rearCamber') and advancedCapabilities.stance.axleControls then
            value = clamp(value, limits.camberDegrees.min, limits.camberDegrees.max)
            local leftName = control == 'frontCamber' and 'frontLeft' or 'rearLeft'
            local rightName = control == 'frontCamber' and 'frontRight' or 'rearRight'
            local left, right = baseline.wheels[leftName], baseline.wheels[rightName]
            if not left or not right then return false, 'That axle mapping is unavailable.' end
            local radians = value * math.pi / 180.0
            local leftOk = nativeCall(SetVehicleWheelYRotation, vehicle, left.index,
                clamp(left.rotation + radians, absolute.wheelRotation.min, absolute.wheelRotation.max))
            local rightOk = nativeCall(SetVehicleWheelYRotation, vehicle, right.index,
                clamp(right.rotation - radians, absolute.wheelRotation.min, absolute.wheelRotation.max))
            if not leftOk or not rightOk then return false, 'Camber could not be applied.' end
            return true, nil, value, value
        elseif control == 'wheelOffset' and support.wheelOffset and type(wheel) == 'string' then
            local ok, message, applied = setWheelOffset(wheel, value)
            return ok, message, applied, applied
        end
        return false, 'Unsupported by current runtime or wheel layout.'
    end

    if data.operation == 'reset' then
        local before = captureAdvancedSetup(vehicle)
        applyStanceSnapshot(vehicle, baseline, { applied = 0 })
        stancePreviewSessions = {}
        local resetSequence = tonumber(data.sequence)
        if isInteger(resetSequence) then
            stancePreviewBarrier = math.max(stancePreviewBarrier, resetSequence)
            for key, previous in pairs(stancePreviewSequences) do
                stancePreviewSequences[key] = math.max(tonumber(previous) or -1, resetSequence)
            end
        end
        pushHistory('Reset Entire Stance', before, captureAdvancedSetup(vehicle))
        return true, 'Stance restored to the captured baseline.'
    end

    if data.operation == 'wheelOffsetBatch' then
        local before, current = captureAdvancedSetup(vehicle), currentStanceState(vehicle)
        local individual = current.individualWheels or {}
        local targets = {}
        if data.action == 'mirrorLeftToRight' then
            if individual.frontLeft and individual.frontRight then targets.frontRight = individual.frontLeft.delta end
            if individual.rearLeft and individual.rearRight then targets.rearRight = individual.rearLeft.delta end
        elseif data.action == 'mirrorRightToLeft' then
            if individual.frontLeft and individual.frontRight then targets.frontLeft = individual.frontRight.delta end
            if individual.rearLeft and individual.rearRight then targets.rearLeft = individual.rearRight.delta end
        elseif data.action == 'copyFrontToRear' then
            if individual.frontLeft and individual.rearLeft then targets.rearLeft = individual.frontLeft.delta end
            if individual.frontRight and individual.rearRight then targets.rearRight = individual.frontRight.delta end
        elseif data.action == 'resetIndividual' then
            for _, name in ipairs({ 'frontLeft', 'frontRight', 'rearLeft', 'rearRight' }) do
                if individual[name] then targets[name] = 0.0 end
            end
        else
            return false, 'Invalid individual wheel action.'
        end
        if next(targets) == nil then return false, 'The required wheel mappings are unavailable.' end
        for name, target in pairs(targets) do
            local ok, message = setWheelOffset(name, target)
            if not ok then return false, message end
        end
        stancePreviewSessions = {}
        local batchSequence = tonumber(data.sequence)
        if isInteger(batchSequence) then
            stancePreviewBarrier = math.max(stancePreviewBarrier, batchSequence)
            for key, previous in pairs(stancePreviewSequences) do
                stancePreviewSequences[key] = math.max(tonumber(previous) or -1, batchSequence)
            end
        end
        pushHistory('Individual Wheel Position', before, captureAdvancedSetup(vehicle))
        return true, 'Individual wheel positions updated.'
    end

    if data.operation ~= 'set' then return false, 'Invalid stance action.' end
    local control = type(data.control) == 'string' and data.control or ''
    local wheel = type(data.wheel) == 'string' and data.wheel or nil
    local phase = data.phase == 'preview' and 'preview' or 'commit'
    local sequence = tonumber(data.sequence)
    if not isInteger(sequence) or sequence < 0 then return false, 'Invalid stance request sequence.' end
    local key = control .. ':' .. (wheel or '')
    local previousSequence = tonumber(stancePreviewSequences[key]) or -1
    if sequence <= previousSequence or sequence <= stancePreviewBarrier then
        return true, nil, { stancePreview = true, ignored = true, control = control, wheel = wheel, sequence = sequence }
    end
    stancePreviewSequences[key] = sequence

    local session = stancePreviewSessions[key]
    if phase == 'preview' and not session then
        session = { before = captureAdvancedSetup(vehicle), vehicle = vehicle, spawnSessionId = VehicleLab.State.spawnSessionId }
        stancePreviewSessions[key] = session
    end
    local directBefore = phase == 'commit' and not session and captureAdvancedSetup(vehicle) or nil
    local ok, message, appliedValue, actualValue = applyValue(control, data.value, wheel, data.rangeMode)
    if not ok then
        local rollback = session and session.before or directBefore
        if rollback and rollback.wheels and rollback.wheels.stance then
            applyStanceSnapshot(vehicle, rollback.wheels.stance, { applied = 0 })
        end
        stancePreviewSessions[key] = nil
        return false, message
    end
    debugLog('stance %s%s %s applied %.4f sequence=%d', control, wheel and (':' .. wheel) or '', phase, appliedValue, sequence)
    local extra = {
        stancePreview = phase == 'preview', control = control, wheel = wheel, sequence = sequence,
        value = appliedValue, actualValue = actualValue
    }
    if phase == 'preview' then return true, nil, extra end

    local before = session and session.vehicle == vehicle
        and session.spawnSessionId == VehicleLab.State.spawnSessionId and session.before or directBefore or captureAdvancedSetup(vehicle)
    stancePreviewSessions[key] = nil
    local labels = {
        wheelSize = 'Wheel Size', wheelWidth = 'Wheel Width', frontTrack = 'Front Wheel Position',
        rearTrack = 'Rear Wheel Position', frontCamber = 'Front Camber', rearCamber = 'Rear Camber',
        suspensionHeight = 'Suspension Height', wheelOffset = 'Individual Wheel Position'
    }
    pushHistory(labels[control] or 'Stance', before, captureAdvancedSetup(vehicle))
    return true, ('%s confirmed.'):format(labels[control] or 'Stance'), extra
end

local function applyPerformanceAction(vehicle, data)
    return withHistory(vehicle, 'Performance', function()
        SetVehicleModKit(vehicle, 0)
        if data.operation == 'set' then
            local modType, index = tonumber(data.modType), tonumber(data.index)
            if not (modType == 11 or modType == 12 or modType == 13 or modType == 15 or modType == 16)
                or not safeSetMod(vehicle, modType, index, false) then return false, 'That performance level is unavailable.' end
            return true, 'Performance level updated.'
        elseif data.operation == 'turbo' and type(data.enabled) == 'boolean' then
            if GetNumVehicleMods(vehicle, Constants.Toggle.TURBO) <= 0 then return false, 'Turbo is unavailable.' end
            ToggleVehicleMod(vehicle, Constants.Toggle.TURBO, data.enabled)
            debugLog('turbo toggle %s', tostring(data.enabled))
            return true, data.enabled and 'Turbo enabled.' or 'Turbo disabled.'
        elseif data.operation == 'max' or data.operation == 'stock' then
            for _, modType in ipairs(Constants.Performance) do
                local count = GetNumVehicleMods(vehicle, modType)
                if count > 0 then SetVehicleMod(vehicle, modType, data.operation == 'max' and count - 1 or -1, false) end
            end
            if GetNumVehicleMods(vehicle, Constants.Toggle.TURBO) > 0 then ToggleVehicleMod(vehicle, Constants.Toggle.TURBO, data.operation == 'max') end
            return true, data.operation == 'max' and 'Maximum performance applied.' or 'Performance returned to stock.'
        elseif data.operation == 'reset' and spawnBaseline then
            local partial = { vehicleModel = spawnedModel, performance = clone(spawnBaseline.performance), toggleMods = { [tostring(Constants.Toggle.TURBO)] = spawnBaseline.toggleMods[tostring(Constants.Toggle.TURBO)] } }
            local ok = applyAdvancedSetup(vehicle, partial, false)
            return ok, ok and 'Performance restored to spawn state.' or 'Performance could not be restored.'
        end
        return false, 'Invalid performance action.'
    end)
end

local function applyPaintAction(vehicle, data)
    return withHistory(vehicle, 'Paint & Finish', function()
        local target, operation = data.target, data.operation
        if operation == 'custom' and (target == 'primary' or target == 'secondary') and validRgb(data) then
            if target == 'primary' then SetVehicleCustomPrimaryColour(vehicle, data.r, data.g, data.b)
            else SetVehicleCustomSecondaryColour(vehicle, data.r, data.g, data.b) end
            return true, 'Custom paint updated.'
        elseif operation == 'indexed' and (target == 'primary' or target == 'secondary') then
            local index = tonumber(data.index)
            if not isInteger(index) or index < 0 or index > 255 then return false, 'Paint index must be from 0 to 255.' end
            local primary, secondary = GetVehicleColours(vehicle)
            if target == 'primary' then ClearVehicleCustomPrimaryColour(vehicle); SetVehicleColours(vehicle, index, secondary)
            else ClearVehicleCustomSecondaryColour(vehicle); SetVehicleColours(vehicle, primary, index) end
            return true, 'Factory paint updated.'
        elseif operation == 'finish' and (target == 'primary' or target == 'secondary') then
            local paintType, colour, pearl = tonumber(data.paintType), tonumber(data.colour), tonumber(data.pearlescent) or 0
            if not isInteger(paintType) or paintType < 0 or paintType > 5 or not isInteger(colour) or colour < 0 or colour > 255 then return false, 'Invalid paint finish.' end
            if target == 'primary' then ClearVehicleCustomPrimaryColour(vehicle); SetVehicleModColor_1(vehicle, paintType, colour, clamp(pearl, 0, 255))
            else ClearVehicleCustomSecondaryColour(vehicle); SetVehicleModColor_2(vehicle, paintType, colour) end
            return true, 'Paint finish updated.'
        elseif operation == 'extraColour' then
            local pearl, wheel = GetVehicleExtraColours(vehicle)
            local value = tonumber(data.index)
            if not isInteger(value) or value < 0 or value > 255 then return false, 'Colour index must be from 0 to 255.' end
            if target == 'pearlescent' then pearl = value elseif target == 'wheel' then wheel = value else return false, 'Invalid detail colour.' end
            SetVehicleExtraColours(vehicle, pearl, wheel)
            return true, 'Detail colour updated.'
        elseif operation == 'interior' or operation == 'dashboard' then
            local value = tonumber(data.index)
            if not isInteger(value) or value < 0 or value > 255 then return false, 'Colour index must be from 0 to 255.' end
            local native = operation == 'interior' and SetVehicleInteriorColour or SetVehicleDashboardColour
            if type(native) ~= 'function' then return false, 'Unsupported by current runtime.' end
            nativeCall(native, vehicle, value)
            return true, operation == 'interior' and 'Interior colour updated.' or 'Dashboard colour updated.'
        elseif operation == 'copy' or operation == 'swap' then
            local pr, pg, pb = GetVehicleCustomPrimaryColour(vehicle)
            local sr, sg, sb = GetVehicleCustomSecondaryColour(vehicle)
            if operation == 'swap' then
                SetVehicleCustomPrimaryColour(vehicle, sr, sg, sb); SetVehicleCustomSecondaryColour(vehicle, pr, pg, pb)
            elseif target == 'primaryToSecondary' then SetVehicleCustomSecondaryColour(vehicle, pr, pg, pb)
            elseif target == 'secondaryToPrimary' then SetVehicleCustomPrimaryColour(vehicle, sr, sg, sb)
            else return false, 'Invalid copy direction.' end
            return true, operation == 'swap' and 'Primary and secondary colours swapped.' or 'Colour copied.'
        elseif operation == 'reset' and spawnBaseline then
            local ok = applyAdvancedSetup(vehicle, { vehicleModel = spawnedModel, paint = clone(spawnBaseline.paint) }, false)
            return ok, ok and 'Paint restored to spawn state.' or 'Paint could not be restored.'
        end
        return false, 'Invalid paint action.'
    end)
end

local function applyLightingAction(vehicle, data)
    return withHistory(vehicle, 'Lighting & Details', function()
        local side = tonumber(data.side)
        if data.operation == 'neonSide' and isInteger(side) and side >= 0 and side <= 3 and type(data.enabled) == 'boolean' then
            SetVehicleNeonLightEnabled(vehicle, side, data.enabled)
            return true, 'Neon state updated.'
        elseif data.operation == 'neonAll' and type(data.enabled) == 'boolean' then
            for side = 0, 3 do SetVehicleNeonLightEnabled(vehicle, side, data.enabled) end
            return true, data.enabled and 'All neon lights enabled.' or 'All neon lights disabled.'
        elseif data.operation == 'neonColour' and validRgb(data) then
            SetVehicleNeonLightsColour(vehicle, data.r, data.g, data.b); return true, 'Neon colour updated.'
        elseif data.operation == 'xenon' and type(data.enabled) == 'boolean' and GetNumVehicleMods(vehicle, Constants.Toggle.XENON) > 0 then
            ToggleVehicleMod(vehicle, Constants.Toggle.XENON, data.enabled); return true, data.enabled and 'Xenon enabled.' or 'Xenon disabled.'
        elseif data.operation == 'xenonColour' and isInteger(tonumber(data.index)) and tonumber(data.index) >= -1 and tonumber(data.index) <= 14 and type(SetVehicleXenonLightsColor) == 'function' then
            nativeCall(SetVehicleXenonLightsColor, vehicle, tonumber(data.index)); return true, 'Xenon colour updated.'
        elseif data.operation == 'smoke' and type(data.enabled) == 'boolean' and GetNumVehicleMods(vehicle, Constants.Toggle.TYRE_SMOKE) > 0 then
            ToggleVehicleMod(vehicle, Constants.Toggle.TYRE_SMOKE, data.enabled); return true, 'Tyre smoke state updated.'
        elseif data.operation == 'smokeColour' and validRgb(data) then
            SetVehicleTyreSmokeColor(vehicle, data.r, data.g, data.b); return true, 'Tyre smoke colour updated.'
        elseif data.operation == 'tint' then
            local index = tonumber(data.index)
            if not isInteger(index) or index < -1 or index >= (tonumber(GetNumVehicleWindowTints()) or 0) then return false, 'Window tint is unavailable.' end
            SetVehicleWindowTint(vehicle, index); return true, 'Window tint updated.'
        elseif data.operation == 'plateStyle' then
            local index = tonumber(data.index)
            if not isInteger(index) or index < 0 or index > 5 then return false, 'Invalid plate style.' end
            SetVehicleNumberPlateTextIndex(vehicle, index); return true, 'Plate style updated.'
        elseif data.operation == 'plateText' and type(data.text) == 'string' then
            SetVehicleNumberPlateText(vehicle, data.text:sub(1, 8)); return true, 'Plate text updated.'
        elseif data.operation == 'reset' and spawnBaseline then
            local ok = applyAdvancedSetup(vehicle, { vehicleModel = spawnedModel, lighting = clone(spawnBaseline.lighting), details = { plateStyle = spawnBaseline.details.plateStyle, plateText = spawnBaseline.details.plateText } }, false)
            return ok, ok and 'Lighting restored to spawn state.' or 'Lighting could not be restored.'
        end
        return false, 'Invalid lighting action.'
    end)
end

local function applyLiveryAction(vehicle, data)
    return withHistory(vehicle, 'Livery', function()
        local system, index = data.system, tonumber(data.index)
        SetVehicleModKit(vehicle, 0)
        if data.operation == 'reset' and spawnBaseline then index = spawnBaseline.liveries[system] end
        if not isInteger(index) then return false, 'The livery baseline is unavailable.' end
        if system == 'native' then
            local count = GetVehicleLiveryCount(vehicle)
            if index < 0 or index >= count then return false, 'Native livery index is unavailable.' end
            SetVehicleLivery(vehicle, index)
        elseif system == 'mod' then
            if not safeSetMod(vehicle, 48, index, false) then return false, 'Mod-slot livery index is unavailable.' end
        elseif system == 'roof' then
            local ok, count = nativeCall(GetVehicleRoofLiveryCount, vehicle)
            if not ok or index < 0 or index >= count then return false, 'Roof livery index is unavailable.' end
            nativeCall(SetVehicleRoofLivery, vehicle, index)
        else return false, 'Invalid livery system.' end
        debugLog('livery system=%s index=%d', system, index)
        return true, ('%s livery %d applied.'):format(system, index)
    end)
end

local function applyExtrasAction(vehicle, data)
    return withHistory(vehicle, 'Vehicle Extras', function()
        if data.operation == 'set' then
            local id = tonumber(data.id)
            if not isInteger(id) or id < 0 or id > (Config.Safety.ExtraScanMax or 50) or type(data.enabled) ~= 'boolean' or not DoesExtraExist(vehicle, id) then return false, 'That extra is unavailable.' end
            if type(overrideForModel(spawnedModel).unsafeExtras) == 'table' and overrideForModel(spawnedModel).unsafeExtras[id] then return false, 'That extra is disabled by the model safety override.' end
            SetVehicleExtra(vehicle, id, not data.enabled)
            return true, ('Extra %d %s.'):format(id, data.enabled and 'enabled' or 'disabled')
        elseif data.operation == 'all' and type(data.enabled) == 'boolean' then
            for _, extra in ipairs(buildExtrasState(vehicle)) do SetVehicleExtra(vehicle, extra.id, not data.enabled) end
            return true, data.enabled and 'All available extras enabled.' or 'All available extras disabled.'
        elseif data.operation == 'reset' and spawnBaseline then
            local ok = applyAdvancedSetup(vehicle, { vehicleModel = spawnedModel, extras = clone(spawnBaseline.extras) }, false)
            return ok, ok and 'Extras restored to spawn state.' or 'Extras could not be restored.'
        end
        return false, 'Invalid extras action.'
    end)
end

local function utilityAction(vehicle, data)
    local operation = data.operation
    if operation == 'repair' then SetVehicleFixed(vehicle); SetVehicleDeformationFixed(vehicle); return true, 'Vehicle repaired.' end
    if operation == 'clean' then WashDecalsFromVehicle(vehicle, 1.0); RemoveDecalsFromVehicle(vehicle); SetVehicleDirtLevel(vehicle, 0.0); return true, 'Vehicle cleaned.' end
    if operation == 'fixTyres' then for wheel = 0, 7 do SetVehicleTyreFixed(vehicle, wheel) end return true, 'Tyres fixed.' end
    if operation == 'fixWindows' then for window = 0, 7 do FixVehicleWindow(vehicle, window) end return true, 'Windows fixed.' end
    if operation == 'dirt' and finiteNumber(tonumber(data.value)) then SetVehicleDirtLevel(vehicle, clamp(data.value, 0.0, 15.0)); return true, 'Dirt level updated.' end
    if operation == 'freeze' and type(data.enabled) == 'boolean' then FreezeEntityPosition(vehicle, data.enabled); return true, data.enabled and 'Vehicle frozen.' or 'Vehicle unfrozen.' end
    if operation == 'engine' and type(data.enabled) == 'boolean' then SetVehicleEngineOn(vehicle, data.enabled, true, true); return true, data.enabled and 'Engine started.' or 'Engine stopped.' end
    if operation == 'lock' and type(data.enabled) == 'boolean' then SetVehicleDoorsLocked(vehicle, data.enabled and 2 or 1); return true, data.enabled and 'Doors locked.' or 'Doors unlocked.' end
    local door = tonumber(data.door)
    if operation == 'door' and isInteger(door) and door >= 0 and door <= 7 and type(data.open) == 'boolean' then
        if data.open then SetVehicleDoorOpen(vehicle, door, false, false) else SetVehicleDoorShut(vehicle, door, false) end
        return true, 'Door state updated.'
    end
    if operation == 'ground' then SetVehicleOnGroundProperly(vehicle); return true, 'Vehicle placed on the ground.' end
    if operation == 'upright' then local heading = GetEntityHeading(vehicle); SetEntityRotation(vehicle, 0.0, 0.0, heading, 2, true); SetVehicleOnGroundProperly(vehicle); return true, 'Vehicle flipped upright.' end
    if operation == 'resetEntire' and spawnBaseline then
        local ok, summary = applyAdvancedSetup(vehicle, spawnBaseline, false)
        if ok then advancedCapabilities = scanAdvancedCapabilities(vehicle); historyUndo, historyRedo = {}, {}; spawnBaseline = captureAdvancedSetup(vehicle) end
        return ok, ok and ('Vehicle baseline restored: %d applied, %d skipped.'):format(summary.applied, summary.skipped) or 'Vehicle baseline could not be restored.'
    end
    return false, 'Invalid utility action.'
end

registerSafeCallback('manualRefresh', function(_, respond)
    TriggerServerEvent(Constants.Events.refreshCatalogue)
    respond(success('Catalogue refresh requested.'))
end)

registerSafeCallback('advancedAction', function(data, respond)
    local group = type(data.group) == 'string' and data.group or ''
    local lockName = ({ body = 'bodyPreview', wheels = 'wheelChanges', stance = 'stanceChanges',
        performance = 'performanceChanges', paint = 'paintChanges', lighting = 'paintChanges',
        livery = 'liveryChanges', extras = 'extras', utility = 'resetActions' })[group]
    if not lockName then respond(failure('Unknown action group.')) return end
    if group == 'stance' then
        lockName = ('stance:%s:%s'):format(tostring(data.control or data.action or data.operation), tostring(data.wheel or ''))
    end
    if advancedLocks[lockName] then respond(failure('That action is already in progress.')) return end
    local vehicle = getVehicle()
    if not vehicle then
        debugLog('%s:%s failed: no authoritative active vehicle', group, tostring(data.operation))
        respond(failure('No active VehicleLab vehicle exists.'))
        return
    end
    advancedLocks[lockName] = true
    local ok, message, extra
    if group == 'body' then ok, message, extra = applyBodyAction(vehicle, data)
    elseif group == 'wheels' then ok, message, extra = applyWheelAction(vehicle, data)
    elseif group == 'stance' then ok, message, extra = applyStanceAction(vehicle, data)
    elseif group == 'performance' then ok, message, extra = applyPerformanceAction(vehicle, data)
    elseif group == 'paint' then ok, message, extra = applyPaintAction(vehicle, data)
    elseif group == 'lighting' then ok, message, extra = applyLightingAction(vehicle, data)
    elseif group == 'livery' then ok, message, extra = applyLiveryAction(vehicle, data)
    elseif group == 'extras' then ok, message, extra = applyExtrasAction(vehicle, data)
    elseif group == 'utility' then ok, message, extra = utilityAction(vehicle, data) end
    advancedLocks[lockName] = nil
    if group == 'stance' and data.phase == 'preview' then
        if not ok then respond(failure(message or 'The stance preview could not be applied.')) return end
        local payload = success()
        if type(extra) == 'table' then for key, value in pairs(extra) do payload[key] = value end end
        respond(payload)
        return
    end
    respondState(respond, ok, message, extra)
end)

registerSafeCallback('historyAction', function(data, respond)
    local direction = data.direction
    local source, target = direction == 'undo' and historyUndo or direction == 'redo' and historyRedo or nil,
        direction == 'undo' and historyRedo or historyUndo
    if not source then respond(failure('Invalid history direction.')) return end
    local item = source[#source]
    local vehicle = getVehicle()
    if not vehicle then respond(failure('No active VehicleLab vehicle exists.')) return end
    if not item then respond(failure(direction == 'undo' and 'Nothing to undo.' or 'Nothing to redo.')) return end
    if item.model ~= spawnedModel then respond(failure('History belongs to another vehicle model.')) return end
    historyReplaying = true
    local ok, summary, message = applyAdvancedSetup(vehicle, direction == 'undo' and item.before or item.after, false)
    historyReplaying = false
    if not ok then respond(failure(message or 'History action failed.')) return end
    table.remove(source)
    target[#target + 1] = item
    advancedCapabilities = scanAdvancedCapabilities(vehicle)
    respondState(respond, true, ('%s: %s (%d applied, %d skipped).'):format(direction == 'undo' and 'Undid' or 'Redid', item.label, summary.applied, summary.skipped))
end)

registerSafeCallback('preferenceAction', function(data, respond)
    if data.operation == 'favoriteVehicle' and validModelName(data.model) then
        local values = kvpRead(Constants.Kvp.favorites, {})
        local found
        for index = #values, 1, -1 do if values[index] == data.model then table.remove(values, index); found = true end end
        if not found then values[#values + 1] = data.model end
        kvpWrite(Constants.Kvp.favorites, values)
        respondState(respond, true, found and 'Vehicle removed from favorites.' or 'Vehicle added to favorites.')
    elseif data.operation == 'filters' and type(data.value) == 'table' then
        local clean = { source = trim(data.value.source):sub(1, 64), type = trim(data.value.type):sub(1, 16), class = tonumber(data.value.class) }
        kvpWrite(Constants.Kvp.filters, clean); respond(success())
    elseif data.operation == 'ui' and (data.mode == 'compact' or data.mode == 'expanded') then
        kvpWrite(Constants.Kvp.ui, { mode = data.mode }); respond(success('Panel mode saved.'))
    elseif data.operation == 'saveColour' and validRgb(data) then
        local colours = kvpRead(Constants.Kvp.colours, {})
        table.insert(colours, 1, { r = data.r, g = data.g, b = data.b })
        while #colours > (tonumber(Config.UI.SavedColourLimit) or 30) do table.remove(colours) end
        kvpWrite(Constants.Kvp.colours, colours); respondState(respond, true, 'Colour swatch saved.')
    else respond(failure('Invalid preference action.')) end
end)

local function findPreset(store, id)
    if type(id) ~= 'string' then return nil end
    for index, preset in ipairs(store) do if preset.id == id then return preset, index end end
end

registerSafeCallback('presetAction', function(data, respond)
    if advancedLocks.presetLoading then respond(failure('A preset operation is already running.')) return end
    advancedLocks.presetLoading = true
    local store, operation = presetStore(), data.operation
    local preset, index = findPreset(store, data.id)
    if operation == 'save' then
        local vehicle, name = getVehicle(), trim(data.name)
        if not vehicle then advancedLocks.presetLoading = nil respond(failure('No active VehicleLab vehicle exists.')) return end
        if name == '' or #name > 48 then advancedLocks.presetLoading = nil respond(failure('Preset names must be 1 to 48 characters.')) return end
        if #store >= (tonumber(Config.Presets.Limit) or 100) then advancedLocks.presetLoading = nil respond(failure('The preset limit has been reached.')) return end
        local setup = captureAdvancedSetup(vehicle)
        if type(setup) ~= 'table' then advancedLocks.presetLoading = nil respond(failure('The current vehicle setup could not be captured.')) return end
        local now = requestUnixTimestamp(true)
        if now > 0 then setup.savedAt = now end
        store[#store + 1] = { id = ('%d-%d'):format(now, monotonicMilliseconds()), name = name, favorite = false, createdAt = now, updatedAt = now, setup = setup }
        kvpWrite(Constants.Kvp.presets, store)
        advancedLocks.presetLoading = nil; respondState(respond, true, ('Preset saved: %s.'):format(name)); return
    elseif operation == 'import' then
        local setup = data.setup
        if type(setup) ~= 'table' or tonumber(setup.schemaVersion) ~= tonumber(Config.Presets.SchemaVersion) or not validModelName(setup.vehicleModel) then
            advancedLocks.presetLoading = nil; respond(failure('Imported JSON does not use the supported preset schema.')); return
        end
        local name = trim(data.name) ~= '' and trim(data.name):sub(1, 48) or ('Imported %s'):format(setup.vehicleModel)
        local now, imported = requestUnixTimestamp(true), clone(setup)
        if type(imported) ~= 'table' then advancedLocks.presetLoading = nil respond(failure('Imported JSON could not be normalized.')) return end
        if now > 0 then imported.savedAt = now else imported.savedAt = nil end
        store[#store + 1] = { id = ('%d-%d'):format(now, monotonicMilliseconds()), name = name, favorite = false, createdAt = now, updatedAt = now, setup = imported }
        kvpWrite(Constants.Kvp.presets, store); advancedLocks.presetLoading = nil; respondState(respond, true, 'Preset JSON imported.'); return
    end
    if not preset then advancedLocks.presetLoading = nil respond(failure('Preset not found.')) return end
    if operation == 'rename' then
        local name = trim(data.name)
        if name == '' or #name > 48 then advancedLocks.presetLoading = nil respond(failure('Preset names must be 1 to 48 characters.')) return end
        preset.name, preset.updatedAt = name, requestUnixTimestamp(true); kvpWrite(Constants.Kvp.presets, store)
        advancedLocks.presetLoading = nil; respondState(respond, true, 'Preset renamed.'); return
    elseif operation == 'duplicate' then
        if #store >= (tonumber(Config.Presets.Limit) or 100) then advancedLocks.presetLoading = nil respond(failure('The preset limit has been reached.')) return end
        local copy, now = clone(preset), requestUnixTimestamp(true); copy.id = ('%d-%d'):format(now, monotonicMilliseconds()); copy.name = (preset.name .. ' Copy'):sub(1, 48); copy.favorite = false; copy.createdAt, copy.updatedAt = now, now
        store[#store + 1] = copy; kvpWrite(Constants.Kvp.presets, store); advancedLocks.presetLoading = nil; respondState(respond, true, 'Preset duplicated.'); return
    elseif operation == 'delete' then
        table.remove(store, index); kvpWrite(Constants.Kvp.presets, store); advancedLocks.presetLoading = nil; respondState(respond, true, 'Preset deleted.'); return
    elseif operation == 'favorite' then
        preset.favorite, preset.updatedAt = not preset.favorite, requestUnixTimestamp(true); kvpWrite(Constants.Kvp.presets, store); advancedLocks.presetLoading = nil; respondState(respond, true, 'Preset favorite updated.'); return
    elseif operation == 'export' then
        advancedLocks.presetLoading = nil; respond({ success = true, setup = clone(preset.setup), name = preset.name }); return
    elseif operation == 'load' then
        local vehicle = getVehicle()
        if not vehicle then advancedLocks.presetLoading = nil respond(failure('No active VehicleLab vehicle exists.')) return end
        local crossModel = preset.setup.vehicleModel ~= spawnedModel
        if crossModel and data.confirmCrossModel ~= true then advancedLocks.presetLoading = nil respond(failure('This preset belongs to another model. Confirm cross-model loading to continue.')) return end
        local before = captureAdvancedSetup(vehicle)
        local ok, summary, message = applyAdvancedSetup(vehicle, preset.setup, crossModel and Config.Presets.AllowCrossModelLoad == true)
        if ok then pushHistory(('Load preset %s'):format(preset.name), before, captureAdvancedSetup(vehicle)); advancedCapabilities = scanAdvancedCapabilities(vehicle) end
        advancedLocks.presetLoading = nil
        if ok then respondState(respond, true, ('Preset loaded: %d applied, %d skipped, %d unsupported, %d invalid.'):format(summary.applied, summary.skipped, summary.unsupported, summary.invalid), { result = summary })
        else respond(failure(message or 'Preset could not be loaded.')) end
        return
    end
    advancedLocks.presetLoading = nil; respond(failure('Invalid preset action.'))
end)

registerSafeCallback('getCurrentSetup', function(_, respond)
    local vehicle = getVehicle()
    if not vehicle then respond(failure('No active VehicleLab vehicle exists.')) return end
    respond({ success = true, setup = captureAdvancedSetup(vehicle) })
end)

registerSafeCallback('getDiagnostics', function(_, respond)
    local vehicle = getVehicle()
    if not vehicle then respond(failure('No active VehicleLab vehicle exists.')) return end
    respond({ success = true, diagnostics = diagnosticsState(vehicle, captureAdvancedSetup(vehicle)) })
end)

registerSafeCallback('screenshotMode', function(data, respond)
    if type(data.enabled) ~= 'boolean' then respond(failure('Invalid screenshot mode.')) return end
    screenshotMode, hideHudForScreenshot = data.enabled, data.hideHud == true
    respond(success(data.enabled and 'Screenshot mode enabled.' or 'Screenshot mode disabled.'))
end)

registerSafeCallback('deleteAdvancedVehicle', function(_, respond)
    if advancedLocks.vehicleDeletion then respond(failure('Vehicle deletion is already in progress.')) return end
    advancedLocks.vehicleDeletion = true
    local ok, message = deleteTrackedVehicle()
    advancedLocks.vehicleDeletion = nil
    respondState(respond, ok, message)
end)

registerSafeCallback('respawnVehicle', function(_, respond)
    if advancedLocks.spawning then respond(failure('Vehicle spawning is already in progress.')) return end
    local entry = getConfiguredVehicle(spawnedModel)
    if not entry and getActiveVehicle() then
        entry = { model = VehicleLab.State.model, modelHash = VehicleLab.State.modelHash }
    end
    if not entry then respond(failure('The active model is unavailable.')) return end
    local respawnEntry = {}
    for key, value in pairs(entry) do respawnEntry[key] = value end
    respawnEntry.deleteAdoptedOnReplace = true
    advancedLocks.spawning = true
    local ok, message, result = spawnConfiguredVehicle(respawnEntry)
    advancedLocks.spawning = nil
    if not ok then respond(failure(message, buildVehicleState())) return end
    if finalizeSpawnTransaction then finalizeSpawnTransaction() end
    local payload = success(message, result and result.state or buildVehicleState())
    payload.warnings = result and result.warnings or {}
    respond(payload)
end)

registerSafeCallback('useCurrentVehicle', function(_, respond)
    if advancedLocks.vehicleActivation then respond(failure('Vehicle activation is already in progress.')) return end
    advancedLocks.vehicleActivation = true
    local ok, message, result = adoptCurrentVehicle('adopted-current')
    advancedLocks.vehicleActivation = nil
    if not ok then respond(failure(message, buildVehicleState())) return end
    local payload = success(message, result and result.state or buildVehicleState())
    payload.warnings = result and result.warnings or {}
    respond(payload)
end)

registerSafeCallback('releaseActiveVehicle', function(_, respond)
    local ok, message, result = releaseActiveVehicle('released-by-user')
    respond(ok and success(message, result and result.state or buildVehicleState()) or failure(message, buildVehicleState()))
end)

registerSafeCallback('refreshVehicleCapabilities', function(_, respond)
    if advancedLocks.capabilityRefresh then respond(failure('A capability refresh is already in progress.')) return end
    advancedLocks.capabilityRefresh = true
    local ok, message, result = refreshActiveVehicleCapabilities('capabilities-refreshed')
    advancedLocks.capabilityRefresh = nil
    if not ok then respond(failure(message, buildVehicleState())) return end
    local payload = success(message, result and result.state or buildVehicleState())
    payload.warnings = result and result.warnings or {}
    respond(payload)
end)

registerSafeCallback('selectCatalogueVehicle', function(data, respond)
    local entry = getConfiguredVehicle(data.model)
    if not entry then respond(failure('The selected catalogue vehicle is unavailable.')) return end
    VehicleLab.State.selectedCatalogueModel = entry.model
    respond(success())
end)

RegisterCommand('vehiclelabusecurrent', function()
    local ok, message = adoptCurrentVehicle('adopted-by-command')
    print(('[vehiclelab] %s'):format(message))
    SendNUIMessage({ action = 'toast', type = ok and 'success' or 'error', message = message })
end, false)

RegisterCommand('vehiclelabrefreshvehicle', function()
    local ok, message = refreshActiveVehicleCapabilities('refreshed-by-command')
    print(('[vehiclelab] %s'):format(message))
    SendNUIMessage({ action = 'toast', type = ok and 'success' or 'error', message = message })
end, false)

RegisterCommand('vehiclelabstate', function()
    local vehicle = getActiveVehicle()
    print('[vehiclelab] Active vehicle state')
    if not vehicle then
        print('[vehiclelab] entity=0 valid=false reason=no_active_vehicle')
        local pedOk, playerPed = nativeCall(PlayerPedId)
        local currentOk, currentVehicle = false, 0
        if pedOk then currentOk, currentVehicle = nativeCall(GetVehiclePedIsIn, playerPed, false) end
        currentVehicle = currentOk and tonumber(currentVehicle) or 0
        local existsOk, exists = nativeCall(DoesEntityExist, currentVehicle)
        local typeOk, entityType = nativeCall(GetEntityType, currentVehicle)
        local modelOk, entityModel = nativeCall(GetEntityModel, currentVehicle)
        local _, rawVehicleNative = optionalVehicleNativeResult(currentVehicle)
        local seatOk, driver = nativeCall(GetPedInVehicleSeat, currentVehicle, -1)
        print(('[vehiclelab] playerVehicle=%s exists=%s type=%s isEntityAVehicle=%s model=%s driverSeat=%s'):format(
            tostring(currentVehicle), tostring(existsOk and nativeBoolean(exists)),
            tostring(typeOk and entityType or 'unavailable'), tostring(rawVehicleNative),
            tostring(modelOk and entityModel or 'unavailable'), tostring(seatOk and driver == playerPed)))
        return
    end
    local capabilities = type(advancedCapabilities) == 'table' and advancedCapabilities or {}
    local liveries = capabilities.liveries or {}
    local actualHashOk, actualModelHash = nativeCall(GetEntityModel, vehicle)
    print(('[vehiclelab] entity=%s valid=true ownership=%s actualModelHash=%s storedModel=%s selectedCatalogueModel=%s'):format(
        tostring(vehicle), tostring(VehicleLab.State.ownership), tostring(actualHashOk and actualModelHash or 'unknown'),
        tostring(VehicleLab.State.model), tostring(VehicleLab.State.selectedCatalogueModel)))
    print(('[vehiclelab] baseline=%s capabilities=%s bodySlots=%d nativeLiveries=%d slot48Liveries=%d roofLiveries=%d extras=%d spawnSessionId=%d menuOpen=%s'):format(
        tostring(spawnBaseline ~= nil), tostring(advancedCapabilities ~= nil), #(capabilities.bodyMods or {}),
        tonumber(liveries.native and liveries.native.count) or 0, tonumber(liveries.mod and liveries.mod.count) or 0,
        tonumber(liveries.roof and liveries.roof.count) or 0, #(capabilities.extras or {}),
        tonumber(VehicleLab.State.spawnSessionId) or 0, tostring(menuOpen)))
end, false)

RegisterNetEvent(Constants.Events.permission, function(result)
    if type(result) == 'table' and result.action == 'open' and result.allowed == true and Config.Permissions.RequireAce == true then
        TriggerServerEvent('vehiclelab:server:checkPermission', 'advanced')
    end
end)

CreateThread(function()
    while true do
        if screenshotMode and hideHudForScreenshot then
            HideHudAndRadarThisFrame()
            Wait(0)
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        if menuOpen and VehicleLab.State.vehicle ~= nil then
            getActiveVehicle() -- Invalid entities self-clear and publish an inactive state.
            Wait(750)
        else
            Wait(1500)
        end
    end
end)
