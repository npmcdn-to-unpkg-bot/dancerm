define [
  'underscore'
  'moment'
  '../base'
], (_, moment, Base) ->

  # Payment of a given registration in a dance class. 
  # May be per month, quarter or year.
  class Payment extends Base

    # traveler check, cash, check
    type: 'check'

    # amount of money paid
    value: 0

    # receiption date
    receipt: null

    # bank name
    bank: null

    # free text, for example to store check owner name
    details: null

    # Creates a payment from a set of raw JSON arguments
    #
    # @param raw [Object] raw attributes of this payment
    constructor: (raw = {}) ->
      # set default values
      _.defaults raw, 
        type: 'check'
        bank: null
        receipt: moment()
        value: 0
        details: null
      # fill attributes
      super(raw)
      # enrich object attributes
      @receipt = moment @receipt