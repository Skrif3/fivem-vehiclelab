# Changelog

## 2.0.0

- Added cached resource-metadata vehicle discovery with multiple-file/model support, source tracking, safe fallbacks, and authorized refreshes.
- Added client model validation and a normalized capability scan for mods, toggles, wheels, stance natives, liveries, extras, paint, and diagnostics.
- Replaced the six-tab UI with a transparent nine-section right-side panel and compact/expanded modes.
- Added confirmed body previews, localized labels, keyboard navigation, session unsafe options, and tuning camera controls.
- Added validated wheel categories/models, separate rear-wheel support, tyre controls, and captured-state reset.
- Added baseline-relative wheel size, width, track, camber, suspension height, runtime native detection, conservative limits, and safe wheel mapping.
- Added validated performance levels and a real turbo toggle using modification type 18.
- Added indexed/native-finish paint, custom RGB, detail colours, saved swatches, neon, xenon, tyre smoke, tint, and plate controls.
- Added independent native, mod-slot 48, and roof liveries plus dynamically discovered sparse extras.
- Added complete spawn baselines, versioned KVP presets, import/export, cross-model summaries, and undo/redo.
- Added developer diagnostics, expanded utilities, screenshot mode, ACE permissions, request locks, safer deletion, and resource-stop cleanup.
- Preserved `/vehiclelab`, `/vehiclelabreset`, F6, `vehiclelabrefresh`, and all `cartest` legacy aliases.
- Fixed client baseline capture using unavailable `os.time`, added server-sourced preset timestamps, transactional spawn rollback, optional-native-safe snapshots, and centralized camera/focus/fade recovery.
- Fixed the startup black screen by removing Chromium's root dark-canvas hint and enforcing a transparent, non-interactive NUI document until VehicleLab is explicitly opened.
- Unified the active VehicleLab entity under `VehicleLab.State`, atomically commits advanced capabilities and baselines after spawning, and rejects stale NUI state responses by revision.
