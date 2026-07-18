local currentResource = GetCurrentResourceName()
local cachedCatalogue = {}
local catalogueReady = false
local catalogueVersion = 0
local scanScheduled = false
local scanInProgress = false
local scanQueued = false

local fallbackPaths = {
    'vehicles.meta',
    'data/vehicles.meta',
    'meta/vehicles.meta',
    'common/data/vehicles.meta',
    'common/data/levels/gta5/vehicles.meta'
}

local function debugLog(message, ...)
    if Config.Debug ~= true then return end
    if select('#', ...) > 0 then message = message:format(...) end
    print(('[vehiclelab] %s'):format(message))
end

local function trim(value)
    if type(value) ~= 'string' then return '' end
    return value:match('^%s*(.-)%s*$') or ''
end

local function decodeXmlText(value)
    value = trim(value)
    return value:gsub('&amp;', '&'):gsub('&lt;', '<'):gsub('&gt;', '>')
        :gsub('&quot;', '"'):gsub('&apos;', "'")
end

local function validModelName(model)
    return type(model) == 'string' and #model > 0 and #model <= 64
        and model:match('^[%w_%-]+$') ~= nil
end

local function normalizeResourcePath(path, declared)
    path = trim(path):gsub('\\', '/'):gsub('^%./', '')
    if path == '' or path:sub(1, 1) == '/' or path:find(':', 1, true)
        or path:find('..', 1, true) then
        return nil
    end

    local hadWildcard = path:find('*', 1, true) or path:find('?', 1, true)
    if hadWildcard then
        -- LoadResourceFile does not expand globs. Resolve common manifest forms
        -- such as data/**/vehicles.meta to a reasonable concrete fallback.
        path = path:gsub('%*%*/', ''):gsub('%*/', ''):gsub('%*', ''):gsub('%?', '')
        path = path:gsub('//+', '/')
    end

    local lower = path:lower()
    if hadWildcard and (lower:sub(-6) == '/.meta' or lower:sub(-5) == '/meta') then return nil end
    if declared then
        if lower:sub(-5) ~= '.meta' then return nil end
    elseif lower:sub(-13) ~= 'vehicles.meta' then
        return nil
    end
    return path
end

local function addCandidate(candidates, seen, path, declared)
    path = normalizeResourcePath(path, declared == true)
    if not path then return end
    local key = path:lower()
    if seen[key] then
        if declared then seen[key].declared = true end
        return
    end
    local candidate = { path = path, declared = declared == true }
    seen[key] = candidate
    candidates[#candidates + 1] = candidate
end

local function addMetadataExtraPaths(resourceName, index, candidates, seen)
    local extra = GetResourceMetadata(resourceName, 'data_file_extra', index)
    if type(extra) ~= 'string' or extra == '' then return end

    local ok, decoded = pcall(json.decode, extra)
    if ok and type(decoded) == 'string' then
        addCandidate(candidates, seen, decoded, true)
    elseif ok and type(decoded) == 'table' then
        for _, path in pairs(decoded) do
            if type(path) == 'string' then addCandidate(candidates, seen, path, true) end
        end
    elseif extra:lower():find('vehicles.meta', 1, true) then
        addCandidate(candidates, seen, extra, true)
    end
end

local function collectMetadataPaths(resourceName)
    local candidates, seen = {}, {}
    local dataFileCount = tonumber(GetNumResourceMetadata(resourceName, 'data_file')) or 0
    for index = 0, math.min(dataFileCount - 1, 63) do
        local kind = trim(GetResourceMetadata(resourceName, 'data_file', index)):upper()
        if kind == 'VEHICLE_METADATA_FILE' then
            addMetadataExtraPaths(resourceName, index, candidates, seen)
        end
    end

    -- Legacy manifests and unusual wrappers may expose the path directly.
    for _, metadataKey in ipairs({ 'vehicle_metadata_file', 'file', 'files' }) do
        local count = tonumber(GetNumResourceMetadata(resourceName, metadataKey)) or 0
        for index = 0, math.min(count - 1, 127) do
            local value = GetResourceMetadata(resourceName, metadataKey, index)
            if type(value) == 'string' and value:lower():find('vehicles.meta', 1, true) then
                addCandidate(candidates, seen, value, metadataKey == 'vehicle_metadata_file')
            end
        end
    end

    for _, path in ipairs(fallbackPaths) do addCandidate(candidates, seen, path, false) end
    return candidates
end

local function extractTag(block, tag)
    local value = block:match('<' .. tag .. '>%s*(.-)%s*</' .. tag .. '>')
    if not value then return nil end
    value = decodeXmlText(value)
    return value ~= '' and value or nil
end

local function parseVehiclesMeta(contents, resourceName, detected, stats)
    local parsedAny = false
    for block in contents:gmatch('<Item[^>]*>(.-)</Item>') do
        local model = extractTag(block, 'modelName')
        if model then
            model = model:lower()
            if validModelName(model) then
                parsedAny = true
                if detected[model] then
                    stats.duplicates = stats.duplicates + 1
                elseif stats.vehicles < 5000 then
                    local gameName = extractTag(block, 'gameName')
                    local manufacturer = extractTag(block, 'vehicleMakeName')
                    local handlingId = extractTag(block, 'handlingId')
                    detected[model] = {
                        model = model,
                        label = gameName or model,
                        gameName = gameName,
                        manufacturer = manufacturer,
                        handlingId = handlingId,
                        category = 'Add-on',
                        resource = resourceName,
                        sourceType = 'addon'
                    }
                    stats.vehicles = stats.vehicles + 1
                end
            end
        end
    end
    return parsedAny
end

local function scanResource(resourceName, detected, stats)
    local candidates = collectMetadataPaths(resourceName)
    local maxBytes = math.max(65536, tonumber(Config.MaxMetadataFileBytes) or (4 * 1024 * 1024))

    for _, candidate in ipairs(candidates) do
        local contents = LoadResourceFile(resourceName, candidate.path)
        if type(contents) == 'string' then
            if #contents > maxBytes then
                stats.unreadable = stats.unreadable + 1
                debugLog('skipped oversized metadata %s:%s', resourceName, candidate.path)
            else
                local ok, parsed = pcall(parseVehiclesMeta, contents, resourceName, detected, stats)
                if not ok then
                    stats.unreadable = stats.unreadable + 1
                    debugLog('malformed metadata skipped %s:%s', resourceName, candidate.path)
                elseif parsed then
                    debugLog('read vehicle metadata %s:%s', resourceName, candidate.path)
                end
            end
        elseif candidate.declared then
            stats.unreadable = stats.unreadable + 1
            debugLog('declared metadata unreadable %s:%s', resourceName, candidate.path)
        end
    end
end

local function sendCatalogue(target)
    TriggerClientEvent('vehiclelab:client:catalogue', target, {
        version = catalogueVersion,
        vehicles = cachedCatalogue
    })
end

local function rebuildCatalogue(reason)
    if scanInProgress then
        scanQueued = true
        return
    end

    scanInProgress = true
    local startedAt = GetGameTimer()
    local stats = { resources = 0, vehicles = 0, duplicates = 0, unreadable = 0 }
    local detected = {}

    if Config.AutoDetectVehicles ~= false then
        local resourceCount = tonumber(GetNumResources()) or 0
        for index = 0, resourceCount - 1 do
            local resourceName = GetResourceByFindIndex(index)
            if resourceName and resourceName ~= currentResource then
                local state = GetResourceState(resourceName)
                local included = Config.IncludeStoppedResources == true
                    or state == 'started' or state == 'starting'
                if included then
                    stats.resources = stats.resources + 1
                    local ok, err = pcall(scanResource, resourceName, detected, stats)
                    if not ok then
                        stats.unreadable = stats.unreadable + 1
                        debugLog('resource scan failed for %s: %s', resourceName, tostring(err))
                    end
                end
            end
        end
    end

    local catalogue = {}
    for _, vehicle in pairs(detected) do catalogue[#catalogue + 1] = vehicle end
    table.sort(catalogue, function(left, right) return left.model < right.model end)
    cachedCatalogue = catalogue
    catalogueVersion = catalogueVersion + 1
    catalogueReady = true
    scanInProgress = false

    local duration = GetGameTimer() - startedAt
    debugLog(
        'scan complete (%s): resources=%d vehicles=%d duplicates=%d unreadable=%d duration=%dms',
        reason or 'unknown', stats.resources, stats.vehicles, stats.duplicates, stats.unreadable, duration
    )
    sendCatalogue(-1)

    if scanQueued then
        scanQueued = false
        SetTimeout(250, function() rebuildCatalogue('queued resource change') end)
    end
end

local function scheduleScan(reason)
    if scanScheduled then return end
    scanScheduled = true
    SetTimeout(350, function()
        scanScheduled = false
        rebuildCatalogue(reason)
    end)
end

RegisterNetEvent('vehiclelab:server:requestCatalogue', function()
    local player = source
    if catalogueReady then
        sendCatalogue(player)
    else
        scheduleScan('initial client request')
    end
end)

local function refreshCatalogueCommand(source)
    debugLog('catalogue refresh requested by %s', source == 0 and 'server console' or ('player ' .. source))
    rebuildCatalogue('admin refresh')
end

RegisterCommand(Config.RefreshCommand, refreshCatalogueCommand, true)
RegisterCommand('cartestrefreshvehicles', refreshCatalogueCommand, true)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == currentResource then
        scheduleScan('vehiclelab start')
    else
        scheduleScan(('resource start: %s'):format(resourceName))
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= currentResource then
        scheduleScan(('resource stop: %s'):format(resourceName))
    end
end)

CreateThread(function()
    Wait(0)
    scheduleScan('server initialization')
end)
