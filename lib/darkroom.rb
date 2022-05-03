# frozen_string_literal: true

require('darkroom/asset')
require('darkroom/darkroom')
require('darkroom/version')

require('darkroom/delegates/css')
require('darkroom/delegates/html')
require('darkroom/delegates/htx')
require('darkroom/delegates/javascript')

Darkroom.register('.css', Darkroom::Asset::CSSDelegate)
Darkroom.register('.htm', '.html', Darkroom::Asset::HTMLDelegate)
Darkroom.register('.htx', Darkroom::Asset::HTXDelegate)
Darkroom.register('.ico', 'image/x-icon')
Darkroom.register('.jpg', '.jpeg', 'image/jpeg')
Darkroom.register('.js', Darkroom::Asset::JavaScriptDelegate)
Darkroom.register('.json', 'application/json')
Darkroom.register('.png', 'image/png')
Darkroom.register('.svg', 'image/svg+xml')
Darkroom.register('.txt', 'text/plain')
Darkroom.register('.woff', 'font/woff')
Darkroom.register('.woff2', 'font/woff2')
