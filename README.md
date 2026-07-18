# VehicleLab

VehicleLab is a standalone FiveM resource for vehicle development, tuning, paint, livery, extras, and setup testing. It automatically builds a searchable catalogue from base-game vehicles and vehicle metadata exposed by other resources.

## Features

- Automatic base-game and add-on vehicle detection
- Searchable vehicle browser with category and resource filters
- Validated, safe vehicle spawning with request locking
- Primary and secondary paint controls
- Native and mod-slot liveries
- Tuning controls, keyboard navigation, and an orbiting tuning camera
- Vehicle extras
- Repair, clean, reset, and delete actions
- Saved setup presets and JSON export
- Transparent NUI
- Safe native validation and resource cleanup
- Automatic catalogue refresh when resources start or stop
- Optional debug logging through `Config.Debug`

## Installation

1. Download or clone the `fivem-vehiclelab` repository.
2. Place it in your FiveM resources directory using the folder name `vehiclelab`.
3. Add `ensure vehiclelab` to your server configuration.
4. Restart the server or start the resource.

VehicleLab does not modify vehicle resources or metadata. It reads available resource metadata to build its catalogue at runtime.

## Commands

| Command | Purpose | Access |
| --- | --- | --- |
| `/vehiclelab` | Open or close VehicleLab | Everyone |
| `/vehiclelabreset` | Close VehicleLab and delete its tracked vehicle | Everyone |
| `vehiclelabrefresh` | Rebuild the vehicle catalogue | ACE-restricted |

The default keybind is **F6** and can be changed in FiveM key bindings.

For compatibility, `/cartest`, `/cartestreset`, and `cartestrefreshvehicles` remain available as aliases. New installations and documentation should use the VehicleLab commands.

## Configuration

Configuration lives in `config.lua`.

```lua
Config.Command = 'vehiclelab'
Config.ResetCommand = 'vehiclelabreset'
Config.RefreshCommand = 'vehiclelabrefresh'
Config.DefaultKey = 'F6'
Config.Debug = false
```

`Config.ManualVehicles` can be used for unusual encrypted or runtime-generated vehicle resources whose `vehicles.meta` files cannot be discovered through FiveM resource APIs.

## Notes for server owners

- The refresh command is registered as restricted. Grant it with FiveM ACE permissions if players or staff should use it.
- NUI callbacks use `GetParentResourceName()`, so the resource continues to work if its folder is renamed.
- Stopping or restarting VehicleLab closes its UI, releases focus, destroys its camera, and removes the vehicle it created.

## Brand and repository

- Product: **VehicleLab**
- Author: **SkrifHub**
- FiveM resource folder: `vehiclelab`
- GitHub repository: `fivem-vehiclelab`
