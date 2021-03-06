_ = require 'lodash'
moment = require 'moment'
i18n = require '../labels/common'
Lesson = require '../model/lesson'
Dancer = require '../model/dancer'

# Simple validation function that check if a given value is defined and acceptable
isInvalidString = (value) -> not(value?) or value.trim?()?.length is 0
isInvalidDate = (value) -> not(value?) or not moment(value).isValid()

# translate a 3 character day to a day offset
toDayOffset = (day) =>
  switch day
    when 'Sun' then 6
    when 'Mon' then 0
    when 'Tue' then 1
    when 'Wed' then 2
    when 'Thu' then 3
    when 'Fri' then 4
    when 'Sat' then 5

# Display lesson planning, and allows to add/edit/remove lessons
module.exports = class LessonsController

  # Controller dependencies
  @$inject: ['$scope', '$rootScope', 'dialog', '$filter', '$state', '$q']

  # Route declaration
  @declaration:
    controller: LessonsController
    controllerAs: 'ctrl'
    templateUrl: 'lessons.html'

  # for rendering
  i18n: i18n

  # Controller's own scope, for change detection
  scope: null

  # Angular's global scope, for digest triggering
  rootScope: null

  # Angular's state service
  state: null

  # Link to modal popup service
  dialog: null

  # Angular's filters factory
  filter: null

  # Angular's promise factory
  q: null

  # List of displayed lessons
  lessons: []

  # Currently edited lesson
  lesson: null

  # Currently edited dancer, for displayal
  selectedDancer: null

  # contains an array of edited lesson required fields
  required: []

  # flag indicating wether the lesson has changed or not
  hasChanged: false

  # invoiced lesson can't be modified
  isReadOnly: false

  # Array of displayed actions
  actions: []

  # All available actions
  _actions: []

  # **private**
  # Store if a modal is currently opened
  _modalOpened: false

  # **private**
  # Stores previous models values for change detection
  _previous: null

  # **private**
  # colors affected to a given teacher
  _colors: {}

  # **private**
  # Next available color (0-based) for affectation
  _nextColor: 0

  # **private**
  # Do not process concurrent search requests
  _reqInProgress: false

  # Controller constructor: bind methods and attributes to current scope
  #
  # @param scope [Object] Controller's own scope, for change detection
  # @param rootscope [Object] Angular global scope for digest triggering
  # @param dialog [Object] Angular dialog service
  # @param filter [Function] Angular's filter factory
  # @param state [Object] Angular state provider
  constructor: (@scope, @rootScope, @dialog, @filter, @state, @q) ->
    day = moment().day()
    @startDay = null
    @lessons = []
    @lesson = null
    @selectedDancer = null
    @hasChanged = false
    @required = []
    @isReadOnly = false
    @_nextColor = 0
    @_colors = {}
    @_modalOpened = false
    @_previous = null
    @_reqInProgress = false

    @_actions =
      cancel: label: 'btn.cancel', icon: 'ban-circle', action: @cancel
      save: label: 'btn.save', icon: 'floppy-disk', action: @save

    # set context actions for planning
    @actions = []
    @_setChanged false

    @rootScope.$on '$stateChangeStart', (event, toState, toParams) =>
      @_confirmQuit (delayed) =>
        @state.go toState.name, toParams if delayed
      , event

    # loads all lesson for all the displayed week
    # delay to let css animation be started (for lesson positionning within planning component)
    _.delay =>
      # beware: sunday is 0
      @_loadLessons moment().subtract((if day is 0 then 7 else day) - 1, 'd').hours(0).minutes(0).seconds(0)
    , 100

  # restore previous values
  cancel: =>
    return unless @hasChanged and not @_modalOpened
    @_modalOpened = true
    @dialog.messageBox(@i18n.ttl.confirm,
      @filter('i18n')('msg.cancelLessonEdition', args: name: "#{@selectedDancer.firstname} #{@selectedDancer.lastname}"), [
        {label: @i18n.btn.no, cssClass: 'btn-warning'}
        {label: @i18n.btn.yes, result: true}
      ]
    ).result.then (confirmed) =>
      @_modalOpened = false
      return unless confirmed
      # cancel and restore previous values
      @rootScope.$broadcast 'cancel-edit'
      Object.assign @lesson, @_previous
      @_previous = @lesson.toJSON()
      @_setChanged false
      @scope.$apply() unless @scope.$$phase

  # Save the current values inside storage
  #
  # @param force [Boolean] true to ignore required fields. Default to false.
  # @param done [Function] completion callback, invoked with arguments:
  # @option done err [Error] an error object or null if no problem occured
  save: (force = false, done = ->) =>
    return done null unless @hasChanged and not @isReadOnly
    # check required fields
    if not force and @_checkRequired()
      return @dialog.messageBox(@i18n.ttl.confirm, i18n.msg.requiredLessonFields, [
          {label: @i18n.btn.no, cssClass: 'btn-warning'}
          {label: @i18n.btn.yes, result: true}
        ]
      ).result.then (confirmed) =>
        # important ! don't invoke done on cancellation, so the current process is cancelled
        return unless confirmed
        @save true, done

    # first, save lesson to get an id
    @lesson.save (err) =>
      if err?
        console.error err
        return @dialog.messageBox(@i18n.ttl.lessonSaveError, err.message, [
            {label: @i18n.btn.ok}
          ]
        ).result.then done
      console.log "lesson #{@lesson.id} saved"

      process = =>
        # always add the edited lesson to new dancer
        @selectedDancer.lessonIds.push @lesson.id
        @selectedDancer.save (err) =>
          if err?
            console.error err
            return @dialog.messageBox(@i18n.ttl.lessonSaveError, err.message, [
                {label: @i18n.btn.ok}
              ]
            ).result.then done
          console.log "new dancer #{@selectedDancer.id} saved"

          @_previous = @lesson.toJSON()
          @onChange()
          @required = []
          @scope.$apply() unless @scope.$$phase
          done()

      # always removes from previous dancer if it exists
      return process() unless @_previous.dancerId?
      Dancer.find @_previous.dancerId, (err, previousDancer) =>
        return console.error err if err
        previousDancer.lessonIds = previousDancer.lessonIds.filter (id) => id isnt @lesson.id
        return process() if previousDancer is @selectedDancer
        previousDancer.save (err) =>
          if err?
            console.error err
            return @dialog.messageBox(@i18n.ttl.lessonSaveError, err.message, [
                {label: @i18n.btn.ok}
              ]
            ).result.then done
          console.log "old dancer #{@_previous.dancerId} saved"
          process()

  # Compute tooltip test for a given lesson
  #
  # @param lesson [Lesson] displayed lesson
  # @param day [String] extracted day string
  # @returns [String] tooltip content
  getPlanningTooltip: (lesson, day) => @q (resolve, reject) ->
    lesson.getDancer (err, dancer) -> if err? then reject err else resolve "#{dancer.firstname} #{dancer.lastname} #{lesson.start.replace(day, '').trim()}~#{lesson.end.replace(day, '').trim()}"

  # Compute displayed title for a given lesson
  #
  # @param lesson [Lesson] displayed lesson
  # @returns [String] title in planning
  getPlanningTitle: (lesson) => @q (resolve, reject) ->
    lesson.getDancer (err, dancer) -> if err? then reject err else resolve "#{dancer.firstname} #{dancer.lastname}"

  # Affect a given color depending on the teacher
  #
  # @param lesson [Lesson] displayed color
  # @returns [Array<String>] computed color and legend item
  affectLegend: (lesson) =>
    @_colors[lesson.teacher] = "color#{++@_nextColor}" unless lesson.teacher of @_colors
    [@_colors[lesson.teacher], lesson.teacher]

  # Create a new lesson for given time
  #
  # @param day [String] selected day
  # @param hourAndMinute [String] selected hour
  createLesson: (day, hourAndMinute) =>
    @_confirmQuit () =>
      [hour, minute] = hourAndMinute.split ':'
      @lesson = new Lesson(
        date: @startDay.clone().add(toDayOffset(day), 'd').hours(+hour).minutes(+minute).seconds(0).milliseconds(0)
        dancerId: @selectedDancer?.id
      )
      @isReadOnly = false
      @_previous = {}
      @scope.$apply() unless @scope.$$phase

  # Search within existing dancers a match on lastname/firstname
  #
  # @param typed [String] typed string
  # @return a promise resolved with relevant models
  search: (typed) =>
    # disable if request in progress
    return [] if @_reqInProgress
    deffered = @q.defer()
    @_reqInProgress = true
    typed = typed.trim()
    # find matching dancers
    Dancer.findWhere $or: [
      {firstname: new RegExp "^#{typed}", 'i'}
      {lastname: new RegExp "^#{typed}", 'i'}
    ], (err, models) =>
      @_reqInProgress = false
      if err?
        console.error err
        return deffered.reject err
      deffered.resolve models
    deffered.promise

  # Displays firstname and lastname of a given dancer
  #
  # @return [String] formated name
  formatDancer: =>
    return "" unless @selectedDancer?
    "#{@selectedDancer.firstname} #{@selectedDancer.lastname}"

  # Displays date and hour of a given lesson
  #
  # @return [String] formated date and hou
  formatDate: =>
    return "" unless @lesson?
    @lesson.date.format @i18n.formats.lesson

  # Affect a given dancer to the edited lesson
  #
  # @param dancer [Dancer] newly affected dancer
  affectDancer: (dancer) =>
    return unless @lesson?
    @lesson.setDancer dancer
    @selectedDancer = dancer
    @required = _.difference @required, ['dancer']
    @onChange 'dancerId'

  # Affect a given teacher to the edited lesson
  #
  # @param teacher [String] newly affected teacher
  setTeacher: (teacher) =>
    return unless @lesson?
    @lesson.teacher = teacher
    @required = _.difference @required, ['teacher']
    @onChange 'teacher'

  # Set the lesson currently edited
  #
  # @param lesson [Lesson] newly edited lesson
  editLesson: (lesson) =>
    @_confirmQuit () =>
      @selectedDancer = null
      @lesson = lesson
      @isReadOnly = @lesson.invoiced
      @required = []
      @_previous = @lesson.toJSON()
      @lesson.getDancer (err, dancer) =>
        return console.error err if err?
        @selectedDancer = dancer
        console.log "load lesson #{@lesson.id} (dancer #{@selectedDancer.id}))"
        # reset changes and displays everything
        @_setChanged false
        @scope.$apply() unless @scope.$$phase

  # Change handler: check if any displayed model has changed from its previous values
  #
  # @param field [String] modified field
  onChange: (field) =>
    # performs comparison between current and old values
    @_setChanged false
    @_setChanged not _.isEqual @_previous, @lesson.toJSON()

  # **private**
  # Update hasChanged flag and contextual actions
  #
  # @param changed [Boolean] new hasChanged flag value
  _setChanged: (changed) =>
    next = []
    if changed
      # can cancel only if already saved once
      next.unshift @_actions.cancel if changed
      next.unshift @_actions.save
    @hasChanged = changed
    # only update actions if they have changed
    @actions = next unless _.isEqual next, @actions

  # **private**
  # Check required fields when saving invoice
  #
  # @return true if a required field is missing
  _checkRequired: =>
    @required = []
    @required.push 'dancer' unless @lesson?.dancerId?
    @required.push 'teacher' if isInvalidString @lesson?.teacher
    # returns true if lesson is missing a field
    @required.length isnt 0

  # **private**
  # Set the week start date, and loads lesson for that week
  #
  # @param start [Date] start day for the week (must be a monday)
  _loadLessons: (start) =>
    @startDay = start
    Lesson.findWhere $and: [{date: $gte: @startDay.valueOf()}, {date: $lte: @startDay.clone().add(7, 'd').valueOf()}], (err, lessons) =>
      return console.error err if err?
      @lessons = lessons
      @scope.$apply()

  # **private**
  # If edited lesson has changed, display a modal to allow user to cancel.
  # @param process [Function] function invoked if action is confirmed and must be done.
  # Invoked with true if the popup was displayed, with false otherwise
  # @param event [Event] optional event that will be cancelled if needed
  _confirmQuit: (process, event = null) =>
    return process false unless @hasChanged
    # stop event (for state changes)
    event?.preventDefault()
    # confirm if dancer changed
    @dialog.messageBox(@i18n.ttl.confirm, i18n.msg.confirmGoBack, [
        {label: @i18n.btn.no, cssClass: 'btn-warning'}
        {label: @i18n.btn.yes, result: true}
      ]
    ).result.then (confirmed) =>
      return unless confirmed
      # if confirmed, effectively go on desired state after reseting previous values
      Object.assign @lesson, @_previous
      @_setChanged false
      process true