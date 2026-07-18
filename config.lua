Config = {}

Config.Command = 'cartest'
Config.DefaultKey = 'F6'
Config.SpawnDistance = 5.0
Config.ModelLoadTimeout = 10000
Config.Debug = false
Config.AutoTuningCamera = true
Config.AutoDetectVehicles = true
Config.IncludeBaseVehicles = true
Config.IncludeStoppedResources = false
Config.MaxMetadataFileBytes = 4 * 1024 * 1024

-- Use this only for unusual, encrypted, or runtime-generated vehicle resources
-- whose vehicles.meta cannot be discovered through FiveM resource APIs.
Config.ManualVehicles = {
    -- {
    --     model = 'customcar',
    --     label = 'Custom Car',
    --     category = 'Add-on',
    --     resource = 'manual'
    -- }
}
