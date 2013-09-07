_ = require 'underscore'
i18n = require  '../labels/common'
Dancer = require  '../model/dancer/dancer'
  
module.exports = class LayoutController
              
  # Controller dependencies
  # Inject storage to ensure that models are properly initialized
  @$inject: ['$scope', 'import', '$dialog', '$state', 'storage']
  
  # Controller scope, injected within constructor
  scope: null

  # Link to import service
  import: null
      
  # Link to Angular dialog service
  dialog: null

  # **private**
  # Disable concurrent search. Only first search is taken in account
  _searchPending: false

  # Controller constructor: bind methods and attributes to current scope
  #
  # @param scope [Object] Angular current scope
  # @param import [import] Import service
  # @param dialog [Object] Angular dialog service
  # @param state [Object] Angular state provider
  constructor: (@scope, @import, @dialog, state) -> 
    @_searchPending = false
    @_isExpand = false
    # updates main existance when state is loaded
    @scope.$on '$stateChangeSuccess', (event, toState, toParams, fromState) =>
      @scope.hasMain = state?.current?.views?.main?
      if toState.name is 'expanded-list' or fromState.name is 'expanded-list'
        @scope.animation = 'animate-expand'
      else
        @scope.animation = 'animate-main'

    # displayed dancer's list
    @scope.list = []
    # search criteria
    @scope.search = 
      danceClasses: []
      seasons: []
      string: null
      teachers: []
    # displayed dancer.
    @scope.displayed = null
    @scope.hasChanged = false
    # injects public methods into scope
    @scope[attr] = value for attr, value of @ when _.isFunction(value) and not _.startsWith attr, '_'
    # Ask immediately dump entry if missing
    @_loadDumpEntry()

  # Trigger the search based on `scope.search` descriptor.
  # `scope.list` will be updated at the search end.
  triggerSearch: =>
    return if @_searchPending
    conditions = {}
    # depending on criterias
    if @scope.search.name?.length >= 3 
      # find all dancers by first name/last name
      searched = @scope.search.name.toLowerCase()
      conditions.id = (id, dancer) -> 
        0 is dancer.firstname?.toLowerCase().indexOf(searched) or 
        0 is dancer.lastname?.toLowerCase().indexOf(searched) or
        0 is dancer.address?.city?.toLowerCase().indexOf(searched)

    # find all dancers by season and optionnaly by teacher for this season
    if @scope.search.seasons?.length > 0
      conditions['registrations.planning.season'] = (season) => season in @scope.search.seasons
    
    if @scope.search.danceClasses?.length > 0
      ids = _.pluck @scope.search.danceClasses, 'id'
      # select class students: can be combined with season and name
      conditions['registrations.danceClassIds'] = (id) -> id in ids
    else if @scope.search.teachers?.length > 0
      # add teacher if needed: can be combined with season and name
      conditions['registrations.danceClasses.teacher'] = (teacher) => teacher in @scope.search.teachers
    
    # clear list content
    return @scope.list = [] if _.isEmpty conditions
    @_searchPending = true
    Dancer.findWhere conditions, (err, dancers) =>
      @_searchPending = false
      return @dialog.messageBox(i18n.ttl.search, _.sprintf(i18n.err.search, err.message), [label: i18n.btn.nok]).open() if err?
      @scope.$apply =>
        @scope.list = _.sortBy dancers, 'lastname'

  # Read a given xlsx file to import dancers.
  # Existing dancers (same firstname/lastname) are not modified
  importDancers: =>
    dialog = $('<input style="display:none;" type="file" accept="application/json,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"/>')
    dialog.change (evt) =>
      filePath = dialog.val()
      dialog.remove()
      # dialog cancellation
      return unless filePath
      @scope.$apply => 
        dialog = @dialog.messageBox i18n.ttl.import, i18n.msg.importing
        dialog.open()
      @import.fromFile filePath, (err, dancers) =>
        err = new Error "No dancers found" if !err? and dancers?.length is 0
        if err?
          console.error "Import failed: #{err}"
          # displays an error dialog
          return @scope.$apply =>
            dialog.close()
            @dialog.messageBox(i18n.ttl.import, _.sprintf(i18n.err.importFailed, err.message), [label: i18n.btn.ok]).open()

        # get all existing dancers
        Dancer.findAll (err, existing) =>
          if err?
            @scope.$apply =>
              dialog.close()
            return console.error err 

          @import.merge existing, dancers, (err, imported) =>
            console.info "#{imported}/#{dancers.length} dancers imported"
            @scope.$apply =>
              dialog.close()
              msg = if err? then  _.sprintf(i18n.err.importFailed, err.message) else _.sprintf i18n.msg.importSuccess, imported, dancers.length
              @dialog.messageBox(i18n.ttl.import, msg, [label: i18n.btn.ok]).open().then =>
                # refresh all
                @scope.$broadcast 'model-imported'

    dialog.trigger 'click'

  # **private**
  # Load from localStorage the saved dump fileEntry, and reloads it.
  # @param callback [Function] invoked when dump is finished, with arguments.
  # @option callback error [Error] an error object or null if no error occurred.
  _loadDumpEntry: (callback) =>
    # nothing in localStorage
    dumpPath = localStorage.getItem 'dumpPath'
    @_chooseDumpLocation callback unless dumpPath

  # **private**
  # Ask user to choose a dump location, and immediately dump data inside.
  # @param callback [Function] invoked when dump is finished, with arguments.
  # @option callback error [Error] an error object or null if no error occurred.
  _chooseDumpLocation: (callback) =>
    # first, explain what we're asking
    @dialog.messageBox(i18n.ttl.dump, i18n.msg.dumpData, [label: i18n.btn.ok]).open().then =>
      dialog = $('<input style="display:none;" type="file" nwsaveas value="dump_dancerm.json" accept="application/json"/>')
      dialog.change (evt) =>
        dumpPath = dialog.val()
        dialog.remove()
        # dialog cancellation
        return @_chooseDumpLocation() unless dumpPath
        # retain entry for next loading
        localStorage.setItem 'dumpPath', dumpPath
        return callback err if err?

      dialog.trigger 'click'
