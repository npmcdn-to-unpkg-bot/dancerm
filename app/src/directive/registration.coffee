_ = require 'underscore'
i18n = require '../labels/common'
Planning = require '../model/planning/planning'
Payment = require '../model/dancer/payment'

# The registration directive displays dancer's registration to dance classes and their payments
app.directive 'registration', ->
  # directive template
  templateUrl: 'registration.html'
  # will remplace hosting element
  replace: true
  # transclusion is needed to be properly used within ngRepeat
  transclude: true
  # applicable as element and attribute
  restrict: 'EA'
  # controller
  controller: RegistrationDirective
  # parent scope binding.
  scope: 
    # displayed registration
    src: '='
    # invoked when registration needs editing
    onEdit: '&'
    # invoked when registration needs removal
    onRemove: '&'
    # invoked when printing the registration
    onPrint: '&'

class RegistrationDirective
                
  # Controller dependencies
  @$inject: ['$scope', '$element', '$modal']
  
  # Controller scope, injected within constructor
  scope: null
  
  # JQuery enriched element for directive root
  $el: null

  # Angular's modal service
  modal: null
  
  # Controller constructor: bind methods and attributes to current scope
  #
  # @param scope [Object] directive scope
  # @param element [DOM] directive root element
  # @param modal [Object] Angular's modal service
  constructor: (@scope, element, @modal) ->
    @$el = $(element)
    # class use to highlight the balance state
    @scope.i18n = i18n
    @scope.balanceState = ""
    @scope.$watch 'src', @_onDisplayRegistration
    @scope.$watchCollection 'src.danceClassIds', @_onDisplayRegistration
    @scope[attr] = value for attr, value of @ when _.isFunction(value) and not _.startsWith attr, '_'

  # Creates a new payment and adds it to the current registration
  onNewPayment: =>
    @scope.src.payments.push new Payment()

  # Invoked each time a payment value changed
  # Updates the registration balance
  onPaymentChanged: =>
    @scope.src.updateBalance()
    if @scope.src.balance < @scope.src.charged 
      @scope.balanceState = 'balance-low' 
    else if @scope.src.charged isnt 0 
      @scope.balanceState = 'balance-right'
    else 
      @scope.balanceState = ''

  # Updates the payment period of the source registration object
  #
  # @param period [String] selected period
  onUpdatePeriod: (period) =>
    @scope.src.period = period
    @scope.periodLabel = i18n.periods[@scope.src.period]

  # Invoked when a payment needs to be removed.
  # Confirm operation with a modal popup and proceed to the removal
  #
  # @param removed [Payment] the removed payment model
  onRemovePayment: (removed) =>
    modalScope = @scope.$new()
    modalScope.title = i18n.ttl.confirm 
    modalScope.message = _.sprintf i18n.msg.removePayment, 
      i18n.paymentTypes[removed.type], 
      removed.value, 
      removed.receipt.format i18n.formats.receipt
    modalScope.buttons = [
      {result: false, label: i18n.btn.no}
      {result: true, label: i18n.btn.yes, cssClass: 'btn-warning'}
    ]
    @modal.open(
        backdrop: true
        keyboard: true
        templateUrl: "messagebox.html"
        scope: modalScope
      ).result.then (confirm) =>
        return unless confirm
        @scope.src.payments.splice @scope.src.payments.indexOf(removed), 1
        @onPaymentChanged()

  # Validates the charged input and only accepts numbers
  #
  # @param event [event] key-up event
  onChargedInput: (event) =>
    @scope.stringCharged = $(event.target).val().replace /[^\d\.]/g, ''
    # invoke method inheritted from parent scope
    @scope.src.charged = parseFloat @scope.stringCharged
    @onPaymentChanged()

  # **private**
  # When displayed registration changed, refresh rendering by retrieving planning and selected dance classes
  _onDisplayRegistration: =>
    # get the friendly labels for period
    @onUpdatePeriod @scope.src.period
    # gets all dance classes details from the models
    Planning.find @scope.src.planningId, (err, planning) =>
      throw err if err?
      # sets season for displayal
      @scope.season = planning.season
      # retrieves full dance class objects from their ids
      @scope.danceClasses = (
        for id in @scope.src.danceClassIds
          _.findWhere planning.danceClasses, id: id
      )
      @scope.stringCharged = @scope.src.charged
      @onPaymentChanged()
      @scope.$apply()