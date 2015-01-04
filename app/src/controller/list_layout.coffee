{join} = require 'path'

module.exports = class ListLayoutController
              
  # Controller dependencies
  @$inject: ['cardList', '$state']

  @declaration:
    controller: ListLayoutController
    controllerAs: 'listCtrl'
    templateUrl: 'list_layout.html'

  # Link to card list service
  cardList: null

  # Link to Angular's state provider
  state: null

  # Displayed columns
  columns: [
    {name: 'firstname', title: 'lbl.firstname'}
    {name: 'lastname', title: 'lbl.lastname'}
    {name: 'certified', title: 'lbl.certified', attr: (dancer, done) -> 
      dancer.getLastRegistration (err, registration) -> done err, registration?.certified(dancer) or false
    }
    {name: 'due', title: 'lbl.due', attr: (dancer, done) -> 
      dancer.getLastRegistration (err, registration) -> done err, registration?.due() or 0
    }
  ]

  # contextual actions, an array of objects containing properties:
  # - label [String] displayed label with i18n filter
  # - icon [String] optionnal icon name (prepended with 'glyphicon-')
  # - action [Function] function invoked (without argument) when clicked
  # modified by main view's controller
  actions: []

  # **private**
  # Call list print preview window
  _preview: null

  # Controller constructor: bind methods and attributes to current scope
  #
  # @param cardList [CardListService] service responsible for card list
  # @param state [Object] Angular's state provider
  constructor: (@cardList, @state) -> 
    @_preview = null

  # Displays a given dancer on the main part
  #
  # @param dancer [Dancer] choosen dancer
  displayCard: (dancer) =>
    console.log "ask to display #{dancer.id}"
    @state.go 'list.card', id: dancer.cardId

  # @return true if the current list concerned a dance class
  canPrintCallList: =>
    @cardList.criteria.string is null and @cardList.criteria.danceClasses.length is 1

  # Print call list from the current day
  # 
  # @param danceClass [DanceClass] danceClass concerned
  printCallList: =>
    return @_preview.focus() if @_preview?
    _console = global.console 
    try
      @_preview = gui.Window.open "file://#{join(__dirname, '..', '..', 'template', 'call_list_print.html').replace(/\\/g, '/')}",
        frame: true
        toolbar: false
        title: window.document.title
        icon: require('../../../package.json')?.window?.icon
        focus: true
        # size to A4 format, landscape
        width: 1000
        height: 400

      # obviously, a bug !
      global.console = _console
        
      # set displayed list and wait for closure
      @_preview.list = @cardList.list
      @_preview.danceClass = @cardList.criteria.danceClasses[0]
      @_preview.on 'closed', => @_preview = null
    catch err
      console.error err