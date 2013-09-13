_ = require 'underscore'
moment = require 'moment'
i18n = require '../labels/common'
Dancer = require '../model/dancer/dancer'
Registration = require '../model/dancer/registration'
Planning = require '../model/planning/planning'
RegisterController = require './register'
  
paths = ['title', 'firstname', 'lastname',
  'address.street', 'address.zipcode', 'address.city', 
  'email', 'phone', 'cellphone',
  'birth', 'certified', 'knownBy']

# Displays and edits a given dancer.
# New registration may be added, and the corresponding directive will be consequently used.
#
# Associated with the `template/dancer.html` view.
module.exports = class DancerController
            
  # Controller dependencies
  @$inject: ['$scope', '$stateParams', '$state', '$modal', '$q']

  # Controller scope, injected within constructor
  scope: null
      
  # Link to Angular modal service
  modal: null

  # Link to Angular deferred implementation
  q: null

  # link to Angular state service
  state: null

  # Dancers's search request in progress
  _reqInProgress: false

  # Controller constructor: bind methods and attributes to current scope
  #
  # @param scope [Object] Angular current scope
  # @param stateParams [Object] invokation route parameters
  # @param state [Object] Angular state service
  # @param modal [Object] Angular modal service
  # @param q [Object] Angular deferred implementation
  constructor: (@scope, stateParams, @state, @modal, @q) -> 
    @_reqInProgress = false
    @scope.isNew = false
    @scope.hasChanged = false
    if stateParams.id
      # load edited dancer
      Dancer.find stateParams.id, (err, dancer) =>
        throw err if err?
        @scope.$apply => @_displayDancer dancer
    else
      @scope.isNew = true
      # creates an empty dancer
      @_displayDancer new Dancer()

    # fill the scope and bind public methods
    @scope.i18n = i18n
    @scope.birthValid = true
    @scope[attr] = value for attr, value of @ when _.isFunction(value) and not _.startsWith attr, '_'

    @scope.$on '$stateChangeStart', (event, toState, toParams, fromState, fromParams) =>
      return unless @scope.hasChanged
      # stop state change until user choose what to do with pending changes
      event.preventDefault()
      # confirm if dancer changed
      modalScope = @scope.$new()
      modalScope.title = i18n.ttl.confirm 
      modalScope.message = i18n.msg.confirmGoBack
      modalScope.buttons = [
        {label: i18n.btn.no, cssClass: 'btn-warning'}
        {label: i18n.btn.yes, result: true}
      ]
      @modal.open(
        backdrop: true
        keyboard: true
        templateUrl: "messagebox.html"
        scope: modalScope
      ).result.then (confirmed) =>
        return unless confirmed
        # if confirmed, effectively go on desired state
        @scope.hasChanged = false
        @state.go toState.name, toParams 

  # Goes back to list, after a confirmation if dancer has chnaged
  onBack: =>
    console.log 'go back to list'
    @state.go 'list-and-planning'

  # Save the current values inside storage
  onSave: =>
    console.log "save dancer #{@scope.dancer.fistname} #{@scope.dancer.lastname} (#{@scope.dancer.id})"
    @scope.displayed = new Dancer @scope.dancer.toJSON()
    @scope.displayed.save (err) =>
      throw err if err?
      @scope.hasChanged = false
      # reload search
      @scope.triggerSearch()

  # restore previous values
  onCancel: =>
    return unless @scope.hasChanged
    modalScope = @scope.$new()
    modalScope.title = i18n.ttl.confirm 
    modalScope.message = _.sprintf i18n.msg.cancelEdition, @scope.dancer.firstname, @scope.dancer.lastname
    modalScope.buttons = [
      {label: i18n.btn.no, cssClass: 'btn-warning'}
      {label: i18n.btn.yes, result: true}
    ]
    @modal.open(
      backdrop: true
      keyboard: true
      templateUrl: "messagebox.html"
      scope: modalScope
    ).result.then (confirmed) =>
      return unless confirmed
      @scope.dancer = new Dancer @scope.displayed.toJSON()

  # Search within existing models a match on given attribute
  # Only available when dancer is not saved yet.
  #
  # @param attr [String] matching attribute name
  # @param typed [String] typed string
  # @return a promise of mathcing dancers
  findByAttr: (attr, typed) =>
    # disable if request in progress
    return [] if @_reqInProgress
    @_reqInProgress = true
    defer = @q.defer()
    # prepare search conditions
    typed = typed.toLowerCase()
    condition = {}
    condition[attr] = (val) -> 0 is val?.toLowerCase().indexOf typed
    # find matching dancers
    Dancer.findWhere condition, (err, models) => 
      next = =>
        @_reqInProgress = false
        defer.resolve models
      return next() if @scope.$$phase
      @scope.$apply next
    defer.promise

  # Invoked by the typeahead directive when a suggested dancer is chosen.
  # Replace the edited dancer with selected one.
  #
  # @param dancer [Dancer] chosen dancer
  onChooseDancer: (dancer) =>
    # removes typeahead
    @scope.isNew = false
    #TODO $('.typeahead.dropdown-menu').remove()
    # replace current dancer
    @_displayDancer dancer

  # Validates the birth input and only accepts dates
  #
  # @param event [event] key-up event
  onBirthInput: =>
    # allow empty
    unless @scope.birth
      @scope.dancer.birth = null
      @scope.birthValid = true
    else
      # parse input
      birth = moment @scope.birth, i18n.formats.birth
      # set validation class
      @scope.birthValid = birth.isValid()
      #updates model only if valid
      @scope.dancer.birth = birth if @scope.birthValid

  # Invoked by view to update dancer's title according to selected item
  #
  # @param selected [String] the new dancer's title
  onUpdateTitle: (selected) =>
    @scope.dancer?.title = selected

  # Add a new registration for the current season to the edited dancer, or edit an existing one
  # Displays the registration modal
  #
  # @param registration [Registration] the edited registration, null to create a new one 
  onRegister: (registration = null) =>
    handled = new Registration()
    # display modal to choose registration season and dance classes
    @modal.open(
      backdrop: true
      keyboard: false
      templateUrl: "register.html"
      controller: RegisterController
      resolve: registration: -> registration or handled
    ).result.then (confirmed) =>
      return if !confirmed or registration?
      # add the created registration to current dancer at the first position
      @scope.dancer.registrations.splice 0, 0, handled

  # Invoked when registration needs to be removed.
  # First display a confirmation modal, and then removes it
  #
  # @param removed [Registration] the removed registration
  onRemoveRegistration: (removed) =>
    Planning.find removed.planningId, (err, planning) =>
      throw err if err?
      @scope.$apply =>
        modalScope = @scope.$new()
        modalScope.title = i18n.ttl.confirm 
        modalScope.message = _.sprintf i18n.msg.removeRegistration, planning.season
        modalScope.buttons = [
          {result: false, label: i18n.btn.no}
          {result: true, label: i18n.btn.yes, cssClass: 'btn-warning'}
        ]
        @modal.open(
          backdrop: true
          keyboard: true
          templateUrl: "messagebox.html"
          scope: modalScope
        ).result.then (confirmed) =>
          return unless confirmed
          @scope.dancer.registrations.splice @scope.dancer.registrations.indexOf(removed), 1

  # Invoked when the list of known-by meanings has changed.
  # Updates the model corresponding array.
  onUpdateKnownBy: =>
    @scope.dancer.knownBy = (value for value of i18n.knownByMeanings when @scope.knownBy[value])
    @scope.dancer.knownBy.push @scope.knownByOther if @scope.knownByOther

  # Print the registration confirmation form
  #
  # @param registration [Registration] the concerned registration
  onPrintRegistration: (registration) =>
    Planning.find registration.planningId, (err, planning) =>
      console.error err if err?
      preview = window.open 'registrationprint.html'
      preview.dancer = @scope.dancer
      preview.registration = registration
      preview.planning = planning

  # **private**
  # Update rendering with a given dancer
  #
  # @param dancer [Dancer] the new displayed dancer
  _displayDancer: (dancer) =>
    # update layout displayed
    @scope.displayed = dancer
    # makes a clone of displayed dancer to allow cancellation
    @scope.dancer = new Dancer dancer.toJSON()
    @scope.birth = @scope.dancer.birth?.toDate()
    @scope.showBirthPicker = false
    # translate the "known by" possibilities into a list of boolean
    @scope.knownBy = {}
    for value of i18n.knownByMeanings 
      @scope.knownBy[value] = _.contains @scope.dancer.knownBy, value
    @scope.knownByOther = _.find @scope.dancer.knownBy, (value) -> !(value of i18n.knownByMeanings)
    @scope.birth = @scope.dancer.birth?.format(i18n.formats.birth) or null
    # listen to dancer's changes 
    # TODO found better way to do this
    @scope.$watch @_onChange 

  # **private**
  # Checks if a field has been changed
  _onChange: =>
    @scope.dancer.address = null unless @scope.dancer.address?.zipcode? or @scope.dancer.address?.city? or @scope.dancer.address?.street?
    @scope.hasChanged = not _.isEqual @scope.dancer.toJSON(), @scope.displayed.toJSON()
