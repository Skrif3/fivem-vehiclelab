# VehicleLab

VehicleLab is a standalone, framework-free FiveM vehicle customization and development resource. It discovers streamed vehicles through FiveM resource metadata, validates them on the client, and builds the interface from the capabilities of the VehicleLab-spawned vehicle.

It does not include vehicle files, edit metadata, mutate handling data, use a database, or modify nearby vehicles. No framework, npm package, database, external API, CDN, or build step is required.

## Features

- Cached automatic base-game and add-on discovery through FiveM resource APIs
- Client validation and a normalized per-vehicle capability scan
- Confirmed body previews, wheels, safe stance, performance, paint, liveries, and sparse extras
- Persistent KVP favorites, recents, filters, colour swatches, panel mode, and versioned presets
- Undo/redo, developer diagnostics, utilities, and a tuning camera
- Optional server-authorized ACE permissions and model-specific safety overrides
- Transparent nine-section right-side NUI, hidden until explicitly opened

## Installation

Place the resource in the server resources directory as `vehiclelab` and add exactly:

```cfg
ensure vehiclelab
```

For a running resource, use:

```text
refresh
restart vehiclelab
vehiclelabrefresh
```

If it is stopped:

```text
refresh
ensure vehiclelab
vehiclelabrefresh
```

VehicleLab does not modify vehicle resources or metadata. It reads available resource metadata to build its catalogue at runtime.

## Commands

| Command | Purpose | Access |
| --- | --- | --- |
| `/vehiclelab` | Open or close VehicleLab | Everyone |
| `/vehiclelabreset` | Close VehicleLab and delete its tracked vehicle | Everyone |
| `vehiclelabrefresh` | Rebuild the vehicle catalogue | Console or configured ACE |

The default keybind is **F6** and can be changed in FiveM key bindings.

For compatibility, `/cartest`, `/cartestreset`, and `cartestrefreshvehicles` remain available as aliases. New installations and documentation should use the VehicleLab commands.

## Automatic vehicle discovery

The server enumerates resources and inspects resources declaring `VEHICLE_METADATA_FILE`. Declared `vehicles.meta` paths and conventional resource-local fallbacks are read only through `LoadResourceFile`; arbitrary operating-system paths are never scanned and discovered code is never executed. Multiple metadata files/models are supported, duplicates are removed case-insensitively, malformed/oversized files are skipped, and the source resource is retained.

The catalogue is cached and rescanned on VehicleLab startup, an authorized refresh, or a relevant vehicle-resource start/stop. `Config.ManualVehicles` remains an empty fallback for encrypted, generated, or unusually structured resources. Every model is validated with `IsModelInCdimage`, `IsModelValid`, and `IsModelAVehicle` before display or spawn. Catalogue loading never spawns a vehicle.

## Dynamic capability scanning and tabs

After spawn, VehicleLab calls `SetVehicleModKit(vehicle, 0)` and scans every normal mod slot, live option counts/labels, toggles, wheel types, livery systems, sparse extras, paint support, wheel count/mapping, and named stance-native support. Unsupported categories are hidden.

The transparent right-side panel has compact/expanded modes and these sections: Vehicles, Body, Wheels & Stance, Performance, Paint & Finish, Liveries, Extras, Utilities, and Diagnostics.

The vehicle browser searches display name, model, manufacturer, and resource, with base/add-on, class, resource, favorite, and recent filters.

## Body customization

Select any dynamically supported visual slot, preview Previous/Next/Stock, then Confirm or Revert Preview. Labels use native localization with `Stock`/`Option N` fallbacks. Every index is validated before `SetVehicleMod`. Mark Current Option Unsafe adds it to a session-only skip list and never edits configuration.

## Wheels and stance

Wheel categories come from editable `Config.Wheels.Types` and are tested on the current vehicle. VehicleLab supports validated front and separate rear models, linked selection, custom tyres, bulletproof tyres, runtime-gated drift tyres, and spawn-state reset. Category changes preserve/reapply stance and never force an unavailable rear slot.

Stance uses named natives only. Missing wheel-size, wheel-width, X-offset, Y-rotation, or suspension-height getters/setters hide the related control. Reset restores the captured post-spawn baseline rather than zeroes. Default relative limits are:

| Control | Minimum | Maximum |
|---|---:|---:|
| Wheel size delta | -0.20 | +0.30 |
| Wheel width delta | -0.15 | +0.30 |
| Track delta | -0.05 | +0.15 |
| Camber | -12.0° | +12.0° |
| Suspension height delta | -0.10 | +0.10 |

Track uses mirrored left/right deltas from each captured offset. Camber is shown in degrees and converted to the wheel native's underlying rotation value. Current CFX wheel setters validate contiguous indices from zero to `wheelCount - 1`: standard four-wheel layouts use front 0/1 and rear 2/3; standard six-wheel layouts use front 0/1, middle 2/3, and rear 4/5. Two-wheel and unknown layouts intentionally hide paired axle controls. Verified unusual layouts can use `Config.VehicleOverrides[model].wheelMap`; overrides are empty by default.

## Performance

Engine (11), brakes (12), transmission (13), suspension (15), and armour (16) levels are validated live. Turbo is a real ON/OFF toggle using mod 18. Max Performance touches only those five slots and turbo. Runtime handling mutation is intentionally omitted.

## Paint & Finish

Factory/indexed paint and custom RGB are separate. Controls cover primary/secondary GTA indexes and paint types, pearlescent, wheel, interior, and dashboard colours where supported. Custom RGB has picker/hex input, copy/swap, and saved swatches. Applying indexed/native finish paint clears incompatible custom state; VehicleLab does not invent a gloss native.

Lighting/detail controls include neon per side/RGB/all, xenon, tyre smoke, tint, and plate text. RGB channels are validated as integers from 0–255.

## Liveries and extras

Native, mod-slot 48, and roof liveries are detected and controlled independently. Each system has direct selection, previous/next, count/current readout, and captured-state reset. Extras are shown only when `DoesExtraExist` succeeds and support individual, enable-all, disable-all, and captured-state reset.

## Presets, KVP, and undo/redo

The local preset manager supports save/name, rename, duplicate, favorite, load, delete, JSON import, and JSON copy/export. Cross-model loading requires confirmation and skips incompatible values. Schema example:

```json
{
  "schemaVersion": 1,
  "vehicleModel": "modelname",
  "savedAt": 1234567890,
  "bodyMods": {},
  "toggleMods": {},
  "wheels": { "stance": {} },
  "performance": {},
  "paint": {},
  "lighting": {},
  "liveries": {},
  "extras": {},
  "details": {}
}
```

Application order is wheels, normal/toggle mods, paint, liveries, extras, stance, lighting, and details. Results report applied/skipped/unsupported/invalid counts. Undo/redo stores meaningful confirmed before/after snapshots, validates the current model, avoids recursive entries, and coalesces debounced colour/stance changes.

KVP keys are `vehiclelab:favorites:v1`, `vehiclelab:recents:v1`, `vehiclelab:filters:v1`, `vehiclelab:colours:v1`, `vehiclelab:presets:v1`, and `vehiclelab:ui:v1`.

## Diagnostics and utilities

Diagnostics includes version, model/hash, labels/source, class/type, network status/ID/owner, wheel mapping, mod kit/counts, livery counts, extras, toggles, wheel/stance, and paint/lighting state. Output is copyable JSON with no private paths or entity handles.

Utilities include separate repair/clean, tyre/window fixes, dirt testing, freeze/engine/lock, individual door testing, ground/upright, respawn/delete, complete baseline reset, camera focus, and local screenshot mode. VehicleLab tracks only its own spawned entity.

## Keyboard controls

- Global: `Q`/`E` tabs, `Ctrl+Z`/`Ctrl+Y` undo/redo, `Escape` close.
- Body: arrows navigate, Shift+Left/Right skips five, Enter confirms, Backspace selects Stock, `R` reverts.
- Camera: `A`/`D` orbit, `W`/`S` height, mouse wheel zoom, `C` cycles, `F` focuses, `R` resets.

Shortcuts do not run while typing in inputs.

## Permissions and configuration

Permissions are off by default. When `Config.Permissions.RequireAce = true`, opening and refreshing are server-authorized:

```cfg
add_ace group.admin vehiclelab.use allow
add_ace group.admin vehiclelab.refresh allow
add_ace group.admin vehiclelab.advanced allow
```

Configuration groups version/debug, keybind, permissions, discovery, manual fallbacks, model overrides, UI, history, presets, wheels, stance, performance, camera, and safety. `Config.Debug` logs concise `[vehiclelab]` messages. NUI uses `GetParentResourceName()`.

## Safe mode and known limitations

- Per-vehicle support varies and unsupported controls are hidden.
- Broken add-on options can be disabled by override or the session unsafe list.
- Unusual wheel layouts require a verified override for axle stance.
- Named wheel/suspension natives depend on the current FiveM artifact.
- Custom RGB and indexed finish combinations have GTA native limitations.
- Properties without exact getters are skipped rather than guessed during restoration.
- Screenshot Mode does not capture/write/upload files.
- Unsafe stance mode, handling mutation, global weather/time changes, and automatic screenshots are intentionally omitted.

## Troubleshooting

- Missing add-on: confirm its manifest declares `VEHICLE_METADATA_FILE`, start it, then run `vehiclelabrefresh`.
- Rejected model: ensure the model is streamed; metadata alone is not trusted.
- Missing tuning: the vehicle reports no options for that slot.
- Missing axle stance: inspect wheel mapping in Diagnostics and configure a verified override.
- Focus/camera issue after development: run `/vehiclelabreset` or restart the resource.

VehicleLab does not include or redistribute vehicle assets.
