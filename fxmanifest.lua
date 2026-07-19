fx_version 'cerulean'
game 'gta5'

author 'SkrifHub'
description 'Standalone FiveM vehicle development, tuning and livery testing tool'
version '2.0.0'

ui_page 'html/index.html'

shared_scripts {
    'config.lua',
    'shared/constants.lua'
}

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
