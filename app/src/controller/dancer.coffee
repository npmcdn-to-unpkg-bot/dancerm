define [
  'underscore'
  'i18n!nls/common'
  '../model/dancer/dancer'
  '../model/dancer/registration'
  '../model/planning/planning'
  './register'
], (_, i18n, Dancer, Registration, Planning, RegisterController) ->
  
  # Displays and edits a given dancer.
  # New registration may be added, and the corresponding directive will be consequently used.
  #
  # Associated with the `template/dancer.html` view.
  class DancerController
              
    # Controller dependencies
    @$inject: ['$scope', '$routeParams', '$dialog', '$q', '$compile']

    # Controller scope, injected within constructor
    scope: null
        
    # Link to Angular dialog service
    dialog: null

    # Link to Angular deferred implementation
    q: null

    # Dancers's search request in progress
    _reqInProgress: false

    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] Angular current scope
    # @param routeParams [Object] invokation route parameters
    # @param dialog [Object] Angular dialog service
    # @param q [Object] Angular deferred implementation
    # @param compile [Object] Angular directive compiler
    constructor: (@scope, routeParams, @dialog, @q, compile) -> 
      @_reqInProgress = false
      if routeParams.id?
        # load edited dancer
        Dancer.find routeParams.id, (err, dancer) =>
          throw err if err?
          @scope.$apply => @_displayDancer dancer
      else
        # creates an empty dancer
        @_displayDancer new Dancer()
        # creates typeahead
        for attr in ['firstname', 'lastname']
          $(".#{attr}").append compile($(".#{attr}").attr 'data-typeahead', "dancer as dancer.firstname+' '+dancer.lastname for dancer in findByAttr('#{attr}', $viewValue) | filter:$viewValue | limitTo:20") @scope

      # fill the scope and bind public methods
      @scope.i18n = i18n
      @scope.birthValid = true
      @scope[attr] = value for attr, value of @ when _.isFunction(value) and not _.startsWith attr, '_'

    # Save the current values inside storage
    onSave: =>
      console.log '>>> save dancer:', @scope.dancer.toJSON()
      @scope.dancer.save (err) =>
        throw err if err?
        console.log '>>> save done !'

    # Search within existing models a match on given attribute
    # Only available when dancer is not saved yet.
    #
    # @param attr [String] mathcing attribute name
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
        @scope.$apply => 
          @_reqInProgress = false
          defer.resolve models
      defer.promise

    # Invoked by the typeahead directive when a suggested dancer is chosen.
    # Replace the edited dancer with selected one.
    #
    # @param dancer [Dancer] chosen dancer
    onChooseDancer: (dancer) =>
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
    # Displays the registration dialog
    #
    # @param registration [Registration] the edited registration, null to create a new one 
    onRegister: (registration = null) =>
      handled = new Registration()
      # display dialog to choose registration season and dance classes
      @dialog.dialog(
        keyboard: false
        backdropClick: false
        dialogFade: true
        backdropFade: true
        controller: RegisterController
        templateUrl: 'register.html'
        resolve: registration: -> registration or handled
      ).open().then (confirmed) =>
        return if !confirmed or registration?
        # add the created registration to current dancer at the first position
        @scope.dancer.registrations.splice 0, 0, handled

    # Invoked when registration needs to be removed.
    # First display a confirmation dialog, and then removes it
    #
    # @param removed [Registration] the removed registration
    onRemoveRegistration: (removed) =>
      Planning.find removed.planningId, (err, planning) =>
        throw err if err?
        @scope.$apply =>
          @dialog.messageBox(i18n.ttl.confirmRemove, _.sprintf(i18n.msg.removeRegistration, planning.season), [
            {result: false, label: i18n.btn.no}
            {result: true, label: i18n.btn.yes, cssClass: 'btn-warning'}
          ]).open().then (confirm) =>
            return unless confirm
            @scope.dancer.registrations.splice @scope.dancer.registrations.indexOf(removed), 1

    # Invoked when the list of known-by meanings has changed.
    # Updates the model corresponding array.
    onUpdateKnownBy: =>
      @scope.dancer.knownBy = (value for value of i18n.knownByMeanings when @scope.knownBy[value])
      @scope.dancer.knownBy.push @scope.knownByOther if @scope.knownByOther

    # **private**
    # Update rendering with a given dancer
    #
    # @param dancer [Dancer] the new displayed dancer
    _displayDancer: (dancer) =>
      @scope.dancer = dancer
      @scope.birth = dancer.birth?.toDate()
      @scope.showBirthPicker = false
      # translate the "known by" possibilities into a list of boolean
      @scope.knownBy = {}
      for value of i18n.knownByMeanings 
        @scope.knownBy[value] = _.contains dancer.knownBy, value
      @scope.knownByOther = _.find dancer.knownBy, (value) -> !(value of i18n.knownByMeanings)
      @scope.birth = dancer.birth?.format(i18n.formats.birth) or null