_ = require 'underscore'
moment = require 'moment'
i18n = require '../labels/common'
{generateId} = require '../util/common'
Dancer = require '../model/dancer'
Card = require '../model/card'
Address = require '../model/address'
Registration = require '../model/registration'
LayoutController = require './layout'
RegisterController = require './register'

# Displays and edits a a dancer card, that is a bunch of dancers, their registrations and their classes
# New registration may be added, and the corresponding directive will be consequently used.
#
# Associated with the `template/dancer.html` view.
module.exports = class CardController extends LayoutController
            
  # Controller dependencies
  @$inject: ['$stateParams'].concat LayoutController.$inject

  # for rendering
  i18n: i18n

  # displayed card
  card: null

  # Array of dancers displaced on this card
  dancers: []

  # Corresponding array of dancers's address, to ensure model reuse
  addresses: []

  # temporary stores known-by values
  knownBy: {}

  # temporary stores known by other value
  knownByOther: null

  # for edited models (id used as key), contains an array of required fields
  required: {}

  # **private**
  # Stores for each displayed model a change status
  # Model's id is used as key
  _changed: {}

  # **private**
  # Store if a modal is currently opened
  _modalOpened: false

  # **private**
  # Stores card previous values for change detection
  _previous: {}

  # Controller constructor: bind methods and attributes to current scope
  #
  # @param stateParams [Object] invokation route parameters
  constructor: (stateParams, parentArgs...) -> 
    super parentArgs...
    # initialize global change status
    @hasChanged = false
    @dancers = []
    @addresses = []
    @required = {}
    @_changes = {}
    @_modalOpened = false
    @_previous = {}

    if stateParams.id
      # load edited dancer
      Dancer.find(stateParams.id).then(@loadDancer)
        .catch (err) -> console.error err
    else
      @_reset()

    @rootScope.$on '$stateChangeStart', (event, toState, toParams) =>
      return unless @hasChanged
      # stop state change until user choose what to do with pending changes
      event.preventDefault()
      # confirm if dancer changed
      @dialog.messageBox(@i18n.ttl.confirm, i18n.msg.confirmGoBack, [
          {label: @i18n.btn.no, cssClass: 'btn-warning'}
          {label: @i18n.btn.yes, result: true}
        ]
      ).result.then (confirmed) =>
        return unless confirmed
        # if confirmed, effectively go on desired state
        @hasChanged = false
        @state.go toState.name, toParams

  # Goes back to list, after a confirmation if dancer has changed
  back: =>
    console.log 'go back to list'
    @state.go 'list-and-planning'

  # restore previous values
  cancel: =>
    return unless @hasChanged and not @_modalOpened
    names = ("#{dancer.firstname or ''} #{dancer.lastname or ''}" for dancer in @dancers when dancer.firstname or dancer.lastname)
    @_modalOpened = true
    @dialog.messageBox(@i18n.ttl.confirm, 
      _.sprintf(@i18n.msg.cancelEdition, names.join ', '), [
        {label: @i18n.btn.no, cssClass: 'btn-warning'}
        {label: @i18n.btn.yes, result: true}
      ]
    ).result.then (confirmed) =>
      @_modalOpened = false
      return unless confirmed
      # restore values by reloading first dancer from storage
      return @loadDancer @dancers[0] if @dancers[0].id?
      # or ecreate a brand new dancer if it was an empty card
      @_reset()

  # Save the current values inside storage
  # 
  # @param force [Boolean] true to ignore required fields. Default to false.
  save: (force = false) =>
    return unless @hasChanged
    # check required fields
    if not force and @_checkRequired()
      return @dialog.messageBox(@i18n.ttl.confirm, i18n.msg.requiredFields, [
          {label: @i18n.btn.no, cssClass: 'btn-warning'}
          {label: @i18n.btn.yes, result: true}
        ]
      ).result.then (confirmed) =>
        return unless confirmed
        @save true
    # first, resolve addresses and card
    Promise.all((dancer.address for dancer in @dancers)
    ).then((models) =>
      models.push @card
      console.log "addresses resolved", models
      Promise.all((
        saved = []
        for model in models when not (model.id in saved) and @_changes[model.id]
          if model.constructor.name is 'Address'
            console.log "save addresss #{model.street} #{model.zipcode} (#{model.id})"
          else
            console.log "save card #{model.id}"
          # to avoid saving the same address multiple times
          saved.push model.id
          model.save()
      )).then =>
        console.log "addresses and card saved"
        # affect to dancers (for those which address was new) and save dancers
        Promise.all((
          for dancer, i in @dancers when not dancer.id? or @_changes[dancer.id]
            console.log "save #{dancer.firstname} #{dancer.lastname} (#{dancer.id})"
            dancer.address = models[i]
            dancer.card = @card
            dancer.save()
        )).then => @rootScope.$apply =>
          console.log "dancers saved"
          # reset change state and refresh search
          @hasChanged = false
          @_changes = {}
          @_resetRequired()
          @triggerSearch()
    ).catch (err) => console.error err

  # Load a dancer: replace current card with dancer's card, and get all other dancers of this card.
  #
  # @param added [Dancer] loaded dancer.
  loadDancer: (dancer) =>
    # get other dancers, and load card to display registrations
    Promise.all([
      Dancer.findWhere cardId:dancer.cardId
      dancer.card
    ]).then( ([dancers, card]) =>
      console.log "load card #{card.id}"
      @card.removeListener 'change', @_onChange
      @card = card
      @_previous = @card.toJSON()
      @card.on 'change', @_onChange
      console.log "load dancer #{dancer.lastname} #{dancer.firstname} (#{dancer.id})" for dancer in dancers
      @required = {}
      @dancers = _.sortBy dancers, "firstname"
      @required[dancer.id] = [] for dancer in @dancers
      @required.regs = ([] for registration in @card.registrations)
      # get dance classes
      Promise.all((dancer.danceClasses for dancer in @dancers)).then (danceClasses) =>
        # get addresses
        Promise.all((dancer.address for dancer in @dancers)).then (addresses) =>
          unic = {}
          @addresses = []
          for address in addresses
            @required[address.id] = []
            unless address.id of unic
              # found a new model
              unic[address.id] = address
              @addresses.push address
            else
              # reuse existing model
              @addresses.push unic[address.id]

          # translate the "known by" possibilities into a list of boolean
          @knownBy = {}
          for value of @i18n.knownByMeanings 
            @knownBy[value] = _.contains @card.knownBy, value
          @knownByOther = _.find @card.knownBy, (value) => not(value of @i18n.knownByMeanings)
          
          # reset changes and displays everything
          @hasChanged = false
          @_changes = {}
          @rootScope.$digest()
    ).catch (err) =>
      console.error err

  # Add a new dancer to this card.
  # Reuse address of last dancer
  addDancer: =>
    added = new Dancer id: generateId()
    # get the existing address and card
    added.address = @addresses[-1..][0]
    added.card = @card
    # adds this new dancer to the list
    @dancers.push added
    @required[added.id] = []
    @required[added.address.id] = []
    # scroll to last
    elem = $('.card') 
    _.defer => 
      $('.card-dancer > .dropup > a').focus()
      elem.scrollTop elem[0].scrollHeight

  # When a dancer that share an address with another one want to separate, 
  # we affect him a brand new address
  # Only for dancers that share address with another one
  #
  # @param dancer [Dancer] the concerned dancer
  addAddress: (dancer) =>
    return unless @isAddressReadOnly dancer
    address = new Address id: generateId()
    @addresses[@dancers.indexOf dancer] = address
    @required[address.id] = []
    dancer.address = address

  # Add a new registration for the current season to the edited dancer, or edit an existing one
  # Displays the registration dialog
  #
  # @param dancer [Dancer] doncer for whom a registration is added
  # @param registration [Registration] the edited registration, null to create a new one 
  addRegistration: (dancer, registration = null) =>
    # display dialog to choose registration season and dance classes
    @dialog.modal(
      size: 'lg'
      keyboard: false
      templateUrl: 'register.html'
      controller: RegisterController
      # TODO waiting for version angular-ui-bootstrap@0.12.0
      # https://github.com/angular-ui/bootstrap/commit/7b7cdf842278e86a677980d29bd74a1afd467ff1
      controllerAs: 'ctrl'
      resolve: 
        danceClasses: -> dancer.danceClasses
        isEdit: -> console.log(dancer.danceClassIds); dancer.danceClassIds.length > 0
    ).result.then ({confirmed, season, danceClasses}) =>
      return unless confirmed
      registration = null
      # search for existing registration
      for candidate in @card.registrations when candidate.season is season
        registration = candidate
        break
      # or add a new registration on top
      unless registration?
        registration = new Registration season: season
        @card.registrations.splice 0, 1, registration
        @required.regs.push []
      # add selected class ids to dancer
      dancer.danceClasses.then (existing) =>
        # removes previous dance classes for that season
        dancer.danceClasses = danceClasses.concat (danceClass for danceClass in existing when danceClass.season isnt season)
        @rootScope.$digest()
        _.delay =>
          $('.registration').last().find('.scrollable').focus()
        , 100

  # Indicates whether this dancer's address was reused or not
  #
  # @param dancer [Dancer] tested dancer
  # @return false if his address is editable, true if not
  isAddressReadOnly: (dancer) =>
    used = {}
    for candidate in @dancers
      if candidate is dancer
        return dancer.addressId of used
      else
        used[candidate.addressId] = true

  # Invoked when the list of known-by meanings has changed.
  # Updates the model corresponding array.
  setKnownBy: =>
    @card?.knownBy = (value for value of @i18n.knownByMeanings when @knownBy[value])
    @card?.knownBy.push @knownByOther if @knownByOther

  # Checks if a field has been changed
  #
  # @param model [Base] model that has changed
  # @param hasChanged [Boolean] true if this model has changed
  onChange: (model, hasChanged) =>
    # performs comparison between current and old values
    # console.log "model #{model.id} (#{model.constructor.name}) has changed: #{hasChanged}"
    return @hasChanged = true unless model.id?
    @_changes[model.id] = hasChanged
    # quit at first modification
    @hasChanged = false
    return @hasChanged = true for id, changed of @_changes when changed

  # Invoked when registration needs to be removed.
  # First display a confirmation dialog, and then removes it
  #
  # @param removed [Registration] the removed registration
  ###onRemoveRegistration: (removed) =>
    Planning.find removed.planningId, (err, planning) =>
      throw err if err?
      @rootScope.$apply =>
        @dialog.messageBox(@i18n.ttl.confirm, _.sprintf(@i18n.msg.removeRegistration, planning.season), [
          {result: false, label: @i18n.btn.no}
          {result: true, label: @i18n.btn.yes, cssClass: 'btn-warning'}
        ]).result.then (confirm) =>
          return unless confirm
          @dancer.registrations.splice @dancer.registrations.indexOf(removed), 1###

  # Print the registration confirmation form
  #
  # @param registration [Registration] the concerned registration
  printRegistration: (registration) =>
    try
      preview = window.open 'registrationprint.html'
      preview.card = @card
      preview.season = registration.season
    catch err
      console.error err

  # **private**
  # Reset displayed card and its relative models
  _reset: =>
    @knownBy = {}
    @required = {}
    @knownByOther = null
    # creates an empty dancer with empty address and card
    dancer = new Dancer id: generateId()
    @required[dancer.id] = []
    # set an id to address to allow sharing with other dancers
    address = new Address id: generateId()
    @required[address.id] = []
    @card?.removeListener 'change', @_onChange
    @card = new Card()
    @_previous = {}
    @card.on 'change', @_onChange
    @required.regs = ([] for registration in @card.registrations)
    dancer.address = address
    dancer.card = @card
    @dancers = [dancer]
    @addresses = [address]
    @_changes[@card.id] = true


  # **private**
  # Card change handler: check if card has changed from its previous values
  #
  # @param attr [String] modified path
  # @param value [Any] new value
  _onChange: (attr, value) =>
    @onChange @card, @card._v is -1 or not _.isEqual @_previous, @card.toJSON()
    # because observer break the digest progresss
    @rootScope.$digest() unless @rootScope.$$phase

  # **private**
  # Check required fields when saving models
  # 
  # @return true if a required field is missing
  _checkRequired: =>
    missing = false
    for dancer in @dancers
      @required[dancer.id] = (
        for field in ['title', 'firstname', 'lastname'] when not(dancer[field]?) or _.trim(dancer[field]).length is 0
          missing = true
          field
      )
    for address in @addresses
      @required[address.id] = (
        for field in ['street', 'zipcode', 'city'] when not(address[field]?) or _.trim(address[field]).length is 0
          missing = true
          field 
      )
    for registration, i in @card.registrations
      @required.regs[i] = (
        for payment in registration.payments
          requiredFields = ['type']
          requiredFields.push 'payer', 'bank' if payment.type is 'check'
          tmp = (
            for field in requiredFields when not(payment[field]?) or _.trim(payment[field]).length is 0
              missing = true
              field 
          )
          tmp
      )
    missing

  # **private**
  # Reset required fields
  _resetRequired: =>
    @required[dancer.id] = [] for dancer in @dancers
    @required[address.id] = [] for address in @addresses
    for registration, i in @card.registrations
      @required.regs[i] = ([] for payment in registration.payments)
