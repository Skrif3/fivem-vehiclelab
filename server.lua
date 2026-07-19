local currentResource = GetCurrentResourceName()
local Events = VehicleLabConstants.Events
local discovery = Config.VehicleDiscovery or {}
local cachedCatalogue, catalogueResources = {}, {}
local catalogueReady, scanScheduled, scanInProgress, scanQueued = false, false, false, false
local catalogueVersion = 0

local function unixTimestamp()
    local systemLibrary = type(os) == 'table' and os or nil
    local timeFunction = systemLibrary and systemLibrary.time or nil
    if type(timeFunction) ~= 'function' then return 0 end
    local ok, value = pcall(timeFunction)
    value = ok and tonumber(value) or nil
    if not value or value ~= value or value == math.huge or value == -math.huge then return 0 end
    return math.max(0, math.floor(value))
end

local fallbackPaths = {
    'vehicles.meta', 'data/vehicles.meta', 'meta/vehicles.meta',
    'common/data/vehicles.meta', 'common/data/levels/gta5/vehicles.meta'
}

local function debugLog(message, ...)
    if Config.Debug ~= true then return end
    if select('#', ...) > 0 then message = message:format(...) end
    print(('[vehiclelab] %s'):format(message))
end

local function trim(value)
    return type(value) == 'string' and (value:match('^%s*(.-)%s*$') or '') or ''
end

local function hasPermission(player, permission)
    if player == 0 or Config.Permissions.RequireAce ~= true then return true end
    return type(permission) == 'string' and permission ~= '' and IsPlayerAceAllowed(player, permission)
end

local function decodeXml(value)
    return trim(value):gsub('&amp;', '&'):gsub('&lt;', '<'):gsub('&gt;', '>')
        :gsub('&quot;', '"'):gsub('&apos;', "'")
end

local function validModelName(model)
    return type(model) == 'string' and #model > 0 and #model <= 64
        and model:match('^[%w_%-]+$') ~= nil
end

local function normalizePath(path, declared)
    path = trim(path):gsub('\\', '/'):gsub('^%./', '')
    if path == '' or path:sub(1, 1) == '/' or path:find(':', 1, true)
        or path:find('..', 1, true) then return nil end
    local lower = path:lower()
    if declared and lower:sub(-5) ~= '.meta' and not lower:find('vehicles.meta', 1, true) then return nil end
    if not declared and lower:sub(-13) ~= 'vehicles.meta' then return nil end
    -- LoadResourceFile cannot enumerate a glob. The declaration is retained for
    -- diagnostics while concrete conventional fallbacks are attempted separately.
    if path:find('[%*%?]') then return nil end
    return path
end

local function addCandidate(list, seen, path, declared)
    path = normalizePath(path, declared == true)
    if not path then return end
    local key = path:lower()
    if seen[key] then
        seen[key].declared = seen[key].declared or declared == true
        return
    end
    local item = { path = path, declared = declared == true }
    seen[key], list[#list + 1] = item, item
end

local function collectStrings(value, output, depth)
    if depth > 4 then return end
    if type(value) == 'string' then output[#output + 1] = value return end
    if type(value) ~= 'table' then return end
    for _, child in pairs(value) do collectStrings(child, output, depth + 1) end
end

local function declaredMetadata(resourceName)
    local count = tonumber(GetNumResourceMetadata(resourceName, 'data_file')) or 0
    for index = 0, math.min(count - 1, 127) do
        if trim(GetResourceMetadata(resourceName, 'data_file', index)):upper() == 'VEHICLE_METADATA_FILE' then
            return true
        end
    end
    return (tonumber(GetNumResourceMetadata(resourceName, 'vehicle_metadata_file')) or 0) > 0
end

local function collectMetadataPaths(resourceName)
    local candidates, seen = {}, {}
    local dataCount = tonumber(GetNumResourceMetadata(resourceName, 'data_file')) or 0
    for index = 0, math.min(dataCount - 1, 127) do
        if trim(GetResourceMetadata(resourceName, 'data_file', index)):upper() == 'VEHICLE_METADATA_FILE' then
            local extra = GetResourceMetadata(resourceName, 'data_file_extra', index)
            if type(extra) == 'string' and extra ~= '' then
                local values, ok, decoded = {}, pcall(json.decode, extra)
                if ok then collectStrings(decoded, values, 0) else values[1] = extra end
                for _, value in ipairs(values) do
                    if value:lower():find('.meta', 1, true) then addCandidate(candidates, seen, value, true) end
                end
            end
        end
    end
    for _, key in ipairs({ 'vehicle_metadata_file', 'file', 'files' }) do
        local count = tonumber(GetNumResourceMetadata(resourceName, key)) or 0
        for index = 0, math.min(count - 1, 255) do
            local value = GetResourceMetadata(resourceName, key, index)
            if type(value) == 'string' and value:lower():find('vehicles.meta', 1, true) then
                addCandidate(candidates, seen, value, key == 'vehicle_metadata_file')
            end
        end
    end
    -- Safe fallbacks remain inside the resource virtual filesystem.
    for _, path in ipairs(fallbackPaths) do addCandidate(candidates, seen, path, false) end
    return candidates
end

local function extractTag(block, tag)
    local value = block:match('<%s*' .. tag .. '%s*>%s*(.-)%s*</%s*' .. tag .. '%s*>')
    value = value and decodeXml(value) or nil
    return value ~= '' and value or nil
end

local function parseVehiclesMeta(contents, resourceName, detected, stats)
    if type(contents) ~= 'string' or not contents:lower():find('<modelname', 1, true) then return false end
    local parsed = false
    for block in contents:gmatch('<%s*Item[^>]*>(.-)</%s*Item%s*>') do
        local model = extractTag(block, 'modelName')
        if model then
            model = model:lower()
            if validModelName(model) then
                parsed = true
                if detected[model] then
                    stats.duplicates = stats.duplicates + 1
                elseif stats.vehicles < (tonumber(discovery.MaxVehicles) or 5000) then
                    detected[model] = {
                        model = model,
                        label = extractTag(block, 'gameName') or model,
                        gameName = extractTag(block, 'gameName'),
                        manufacturer = extractTag(block, 'vehicleMakeName'),
                        handlingId = extractTag(block, 'handlingId'),
                        category = 'Add-on', resource = resourceName, sourceType = 'addon'
                    }
                    stats.vehicles = stats.vehicles + 1
                end
            end
        end
    end
    return parsed
end

local function scanResource(resourceName, detected, stats)
    local found = false
    local maxBytes = math.max(65536, tonumber(discovery.MaxMetadataFileBytes) or 4194304)
    for _, candidate in ipairs(collectMetadataPaths(resourceName)) do
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
                    found = true
                    debugLog('read vehicle metadata %s:%s', resourceName, candidate.path)
                end
            end
        elseif candidate.declared then
            debugLog('declared metadata unreadable %s:%s', resourceName, candidate.path)
        end
    end
    return found
end

local function sendCatalogue(target)
    TriggerClientEvent(Events.catalogue, target, { version = catalogueVersion, vehicles = cachedCatalogue })
end

local function rebuildCatalogue(reason)
    if scanInProgress then scanQueued = true return end
    scanInProgress = true
    local startedAt = GetGameTimer()
    local stats = { resources = 0, vehicles = 0, duplicates = 0, unreadable = 0 }
    local detected, sources = {}, {}
    if discovery.Enabled ~= false then
        local count = tonumber(GetNumResources()) or 0
        for index = 0, count - 1 do
            local name = GetResourceByFindIndex(index)
            if name and name ~= currentResource then
                local state = GetResourceState(name)
                local included = discovery.IncludeStoppedResources == true or state == 'started' or state == 'starting'
                if included and declaredMetadata(name) then
                    stats.resources = stats.resources + 1
                    local ok, found = pcall(scanResource, name, detected, stats)
                    if ok and found then sources[name] = true
                    elseif not ok then stats.unreadable = stats.unreadable + 1 end
                end
            end
        end
    end
    local catalogue = {}
    for _, item in pairs(detected) do catalogue[#catalogue + 1] = item end
    table.sort(catalogue, function(a, b) return a.model < b.model end)
    cachedCatalogue, catalogueResources = catalogue, sources
    catalogueVersion, catalogueReady, scanInProgress = catalogueVersion + 1, true, false
    debugLog('scan complete (%s): resources=%d vehicles=%d duplicates=%d unreadable=%d duration=%dms',
        reason or 'unknown', stats.resources, stats.vehicles, stats.duplicates, stats.unreadable,
        GetGameTimer() - startedAt)
    sendCatalogue(-1)
    if scanQueued then scanQueued = false SetTimeout(250, function() rebuildCatalogue('queued change') end) end
end

local function scheduleScan(reason)
    if scanScheduled then return end
    scanScheduled = true
    SetTimeout(tonumber(discovery.RescanDelayMs) or 350, function()
        scanScheduled = false
        rebuildCatalogue(reason)
    end)
end

RegisterNetEvent(Events.requestCatalogue, function()
    local player = source
    if catalogueReady then sendCatalogue(player) else scheduleScan('initial request') end
end)

RegisterNetEvent(Events.requestTimestamp, function()
    TriggerClientEvent(Events.timestamp, source, unixTimestamp())
end)

RegisterNetEvent(Events.refreshCatalogue, function()
    local player = source
    if not hasPermission(player, Config.Permissions.Refresh) then
        TriggerClientEvent(Events.permission, player, { action = 'refresh', allowed = false })
        return
    end
    TriggerClientEvent(Events.permission, player, { action = 'refresh', allowed = true })
    rebuildCatalogue(('player %d refresh'):format(player))
end)

RegisterNetEvent('vehiclelab:server:checkPermission', function(action)
    local player = source
    local permission = action == 'advanced' and Config.Permissions.Advanced or Config.Permissions.Use
    TriggerClientEvent(Events.permission, player, { action = action, allowed = hasPermission(player, permission) })
end)

local function refreshCommand(player)
    if not hasPermission(player, Config.Permissions.Refresh) then
        if player ~= 0 then TriggerClientEvent(Events.permission, player, { action = 'refresh', allowed = false }) end
        return
    end
    rebuildCatalogue(player == 0 and 'console refresh' or ('player %d command'):format(player))
end
RegisterCommand(Config.RefreshCommand, refreshCommand, false)
RegisterCommand('cartestrefreshvehicles', refreshCommand, false)

AddEventHandler('onResourceStart', function(name)
    if name == currentResource then scheduleScan('vehiclelab start')
    elseif declaredMetadata(name) then scheduleScan(('vehicle resource start: %s'):format(name)) end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= currentResource and catalogueResources[name] then
        scheduleScan(('vehicle resource stop: %s'):format(name))
    end
end)

CreateThread(function() Wait(0) scheduleScan('server initialization') end)
