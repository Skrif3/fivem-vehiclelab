Config = {}

-- Version and diagnostics
Config.Version = '2.0.0'
Config.Debug = false

-- Commands and key binding
Config.Command = 'vehiclelab'
Config.ResetCommand = 'vehiclelabreset'
Config.RefreshCommand = 'vehiclelabrefresh'
Config.DefaultKey = 'F6'

-- Optional ACE gates. Console commands are always allowed.
Config.Permissions = {
    RequireAce = false,
    Use = 'vehiclelab.use',
    Refresh = 'vehiclelab.refresh',
    Advanced = 'vehiclelab.advanced'
}

-- Controls how VehicleLab acquires and releases its active vehicle entity.
Config.VehicleTargeting = {
    AllowCurrentVehicleAdoption = true,
    RequireDriverSeat = true,
    DeleteSpawnedVehicleOnResourceStop = true,
    DeleteAdoptedVehicleOnResourceStop = false
}

-- Vehicle catalogue discovery
Config.VehicleDiscovery = {
    Enabled = true,
    IncludeBaseVehicles = true,
    IncludeStoppedResources = false,
    MaxMetadataFileBytes = 4 * 1024 * 1024,
    MaxVehicles = 5000,
    RescanDelayMs = 350
}

-- Backward-compatible discovery names used by VehicleLab 1.x.
Config.AutoDetectVehicles = Config.VehicleDiscovery.Enabled
Config.IncludeBaseVehicles = Config.VehicleDiscovery.IncludeBaseVehicles
Config.IncludeStoppedResources = Config.VehicleDiscovery.IncludeStoppedResources
Config.MaxMetadataFileBytes = Config.VehicleDiscovery.MaxMetadataFileBytes

-- Use only for encrypted, generated, or unusually structured resources whose
-- vehicles.meta cannot be exposed through normal FiveM resource metadata.
Config.ManualVehicles = {}

-- Optional model-specific safety overrides. Keys must be lower-case model names.
-- Supported fields: disabledMods, wheelMap, stanceEnabled, stanceLimits,
-- disableNativeLivery, disableModLivery, disableRoofLivery, unsafeExtras.
Config.VehicleOverrides = {}

Config.UI = {
    DefaultMode = 'compact',
    PreviewDebounceMs = 90,
    SliderDebounceMs = 110,
    RecentVehicleLimit = 20,
    SavedColourLimit = 30
}

Config.HistoryLimit = 50
Config.HistoryDebounceMs = 450

Config.Presets = {
    Limit = 100,
    SchemaVersion = 1,
    AllowCrossModelLoad = true
}

-- FiveM adds wheel types over time. Each definition is validated against the
-- spawned vehicle before it is shown; this list is intentionally configurable.
Config.Wheels = {
    Types = {
        { id = 0, label = 'Sport' },
        { id = 1, label = 'Muscle' },
        { id = 2, label = 'Lowrider' },
        { id = 3, label = 'SUV' },
        { id = 4, label = 'Off-road' },
        { id = 5, label = 'Tuner' },
        { id = 6, label = 'Motorcycle' },
        { id = 7, label = 'High End' },
        { id = 8, label = "Benny's Original" },
        { id = 9, label = "Benny's Bespoke" },
        { id = 10, label = 'Open Wheel' },
        { id = 11, label = 'Street' },
        { id = 12, label = 'Track' }
    }
}

Config.Stance = {
    Enabled = true,
    SafeMode = true,
    AllowUnsafeMode = false,
    DebounceMs = 100,
    UI = {
        PreviewIntervalMs = 40,
        AnimationMs = 160,
        DefaultPrecision = 'normal',
        ShowAdvancedPerWheel = true,
        ExtendedRangeConfirmation = true,
        Steps = {
            fine = { wheelSize = 0.001, wheelWidth = 0.001, track = 0.001, camber = 0.1, suspension = 0.001 },
            normal = { wheelSize = 0.01, wheelWidth = 0.01, track = 0.005, camber = 0.5, suspension = 0.005 },
            coarse = { wheelSize = 0.05, wheelWidth = 0.05, track = 0.02, camber = 2.0, suspension = 0.02 }
        },
        ExtendedLimits = {
            wheelSizeDelta = { min = -0.45, max = 0.75 },
            wheelWidthDelta = { min = -0.35, max = 0.65 }
        },
        Presets = {
            wheelSize = { small = -0.05, slightlyLarger = 0.05, large = 0.15 },
            wheelWidth = { narrow = -0.05, slightlyWider = 0.05, wide = 0.15 }
        }
    },
    Limits = {
        wheelSizeDelta = { min = -0.20, max = 0.30 },
        wheelWidthDelta = { min = -0.15, max = 0.30 },
        trackDelta = { min = -0.05, max = 0.15 },
        camberDegrees = { min = -12.0, max = 12.0 },
        suspensionHeightDelta = { min = -0.10, max = 0.10 }
    },
    AbsoluteLimits = {
        wheelSize = { min = 0.1, max = 5.0 },
        wheelWidth = { min = 0.1, max = 5.0 },
        wheelOffset = { min = -1.0, max = 1.0 },
        wheelRotation = { min = -0.75, max = 0.75 },
        suspensionHeight = { min = -0.5, max = 0.5 }
    }
}

Config.Performance = {
    ExperimentalHandling = false
}

Config.Camera = {
    Enabled = true,
    AutoFocus = true
}
Config.AutoTuningCamera = Config.Camera.Enabled and Config.Camera.AutoFocus

Config.Safety = {
    SpawnDistance = 5.0,
    ModelLoadTimeout = 10000,
    NetworkControlTimeout = 750,
    ExtraScanMax = 50
}
Config.SpawnDistance = Config.Safety.SpawnDistance
Config.ModelLoadTimeout = Config.Safety.ModelLoadTimeout
