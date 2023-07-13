# frozen_string_literal: true

require('darkroom/asset')
require('darkroom/darkroom')
require('darkroom/delegate')
require('darkroom/version')

require('darkroom/delegates/css')
require('darkroom/delegates/html')
require('darkroom/delegates/htx')
require('darkroom/delegates/javascript')

Darkroom.register('.css', Darkroom::CSSDelegate)
Darkroom.register('.htm', '.html', Darkroom::HTMLDelegate)
Darkroom.register('.htx', Darkroom::HTXDelegate)
Darkroom.register('.ico', 'image/x-icon')
Darkroom.register('.jpg', '.jpeg', 'image/jpeg')
Darkroom.register('.js', Darkroom::JavaScriptDelegate)
Darkroom.register('.json', 'application/json')
Darkroom.register('.png', 'image/png')
Darkroom.register('.svg', 'image/svg+xml')
Darkroom.register('.txt', 'text/plain')
Darkroom.register('.woff', 'font/woff')
Darkroom.register('.woff2', 'font/woff2')
