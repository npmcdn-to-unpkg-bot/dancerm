'use strict'

_ = require 'lodash'
gui = require 'nw.gui'
{parallel} = require 'async'
{join} = require 'path'
{version} = require '../../package.json'
{dumpError, buildStyles, getColorsFromTheme, fixConsole} = require '../script/util/common'
{init} = require '../script/model/tools/initializer'

process.on 'uncaughtException', dumpError

try
  fixConsole()

  console.log "running DanceRM #{version} on node-webkit v#{process.versions['node-webkit']}"

  # make some variable globals for other scripts
  global.gui = gui
  global.$ = $
  global.angular = angular
  global.localStorage = localStorage
  global.version = version

  i18n = require '../script/labels/common'

  # 'win' is Node-Webkit's window
  # 'window' is DOM's window
  win = gui.Window.get()
  win.isMaximized = false
  hasDump = false
  app = null
  # stores in local storage application state
  win.on 'close', ->
    return @close true if hasDump

    console.log 'ask to close...'
    hasDump = true
    app?.close (err) =>
      if err?
        console.error 'close after save error', err
      else
        console.log 'close after save'
      @close true

    for attr in ['x', 'y', 'width', 'height']
      localStorage?.setItem attr, win[attr]

    localStorage?.setItem 'maximized', win.isMaximized
    false

  win.on 'maximize', -> win.isMaximized = true
  win.on 'unmaximize', -> win.isMaximized = false
  win.on 'minimize', -> win.isMaximized = false

  $(win.window).on 'keydown', (event) ->
    # disable backspace support
    if event.which is 8
      name = event.target?.nodeName?.toLowerCase()
      event.preventDefault() unless name in ['input', 'textarea']
    # opens dev tools on F12 or Command+Option+J
    win.showDevTools() if event.which is 123 or event.witch is 74 and event.metaKey and event.altKey
    # reloads full app on Ctrl+F5
    if event.which is 116 and event.ctrlKey
      # must clear require cache also
      delete global.require.cache[attr] for attr of global.require.cache
      global.reload = true
      win.removeAllListeners()
      win.reloadIgnoringCache()

  parallel [
    (next) -> buildStyles ['dancerm', 'print'], localStorage.theme or 'none', next
    (next) -> $(win.window).on 'load', -> next()
  ], (err, results) ->
    # DOM is ready
    throw err if err?
    [styles] = results
    $('head').append "<style type='text/css' data-theme>#{styles['dancerm']}</style>"
    # make sheets global for others windows
    global.styles = styles

    # set application title
    window.document?.title = i18n.ttl.application

    # restore from local storage application state if possible
    if localStorage.getItem 'x'
      x = Number localStorage.getItem 'x'
      y = Number localStorage.getItem 'y'
      win.moveTo x, y
    if localStorage.getItem 'width'
      width = Number localStorage.getItem 'width'
      height = Number localStorage.getItem 'height'
      win.resizeTo width, height
    else
      infos = require '../../package.json'
      win.resizeTo infos.window.min_width, infos.window.min_height,

    _.delay ->
      # now that body is ready and stylesheet included, get colors
      getColorsFromTheme()

      app = require '../script/app'
      # require directives and filters immediately to allow circular dependencies
      require('../script/util/filters')(app)
      require('../script/directive/address')(app)
      require('../script/directive/app_menu')(app)
      require('../script/directive/dancer')(app)
      require('../script/directive/layout')(app)
      require('../script/directive/list')(app)
      require('../script/directive/planning')(app)
      require('../script/directive/payment')(app)
      require('../script/directive/tags')(app)
      require('../script/directive/registration')(app)

      anchor = $('body.app')

      console.log 'init database...'
      init (err) ->
        if err?
          dumpError err
          console.error err
          # close all windows without dumping data
          hasDump = true
          return win?.close true
        console.log 'database initialized !'
        # we are ready: shows it !
        win.show()
        # local storage stores strings !
        win.maximize() if 'true' is localStorage.getItem 'maximized'
        # starts the application from a separate file to allow circular dependencies to application
        angular.bootstrap anchor, ['app']
    , 200 # needed for colors to be retrieved

catch err
  dumpError err