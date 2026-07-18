fx_version 'cerulean'
game 'gta5'

author 'SkrifHub'
description 'Standalone FiveM vehicle development, tuning and livery testing tool'
version '1.0.0'

ui_page 'html/index.html'

shared_script 'config.lua'

client_scripts {
    'shared/base_vehicles.lua',
    'client.lua'
}
server_script 'server.lua'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}
