_ = require 'underscore'
ListController = require './list' 
i18n = require '../labels/common'

module.exports = class ExpandedListController extends ListController

  # Controller dependencies
  @$inject: ['$scope', '$state', '$modal', 'export']

  # Link to export service
  export: null

  # Controller constructor: bind methods and attributes to current scope
  #
  # @param scope [Object] Angular current scope
  # @param state [Object] Angular state provider
  # @param modal [Object] Angular modal service
  # @param export [Export] Export service
  constructor: (scope, state, @modal, @export) -> 
    super scope, state
    @scope.i18n = i18n
    # keeps current sort for inversion
    @scope.sort = null
    @scope.sortAsc = true

  # Sort list by given attribute and order
  #
  # @param attr [String] sort attribute
  onSort: (attr) =>
    # invert if using same sort.
    if attr is @scope.sort
      @scope.list.reverse()
      @scope.sortAsc = !@scope.sortAsc
    else
      @scope.sortAsc = true
      @scope.sort = attr
      # specific attributes
      if attr is 'due'
        attr = (model) -> model?.registrations?[0]?.due() 
      else if attr is 'address'
        attr = (model) -> model?.address?.zipcode
      @scope.list = _.sortBy @scope.list, attr


  # Choose a target file and export list as xlsx
  onExport: =>
    return unless @scope.list?.length > 0
    modal = $('<input style="display:none;" type="file" nwsaveas accept="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"/>')
    modal.change (evt) =>
      filePath = modal.val()
      modal.remove()
      # modal cancellation
      return unless filePath

      # waiting message box
      waitingmodal = null
      @scope.$apply => 
        modalScope = @scope.$new()
        modalScope.title = i18n.ttl.export 
        modalScope.message = i18n.msg.exporting
        waitingmodal = @modal.open
          backdrop: true
          keyboard: true
          templateUrl: "messagebox.html"
          scope: modalScope

      # Perform export
      @export.toFile filePath, @scope.list, (err) =>
        waitingmodal.close()
        if err?
          console.error "Export failed: #{err}"
          # displays an error modal
          @scope.$apply =>
            modalScope = @scope.$new()
            modalScope.title = i18n.ttl.export 
            modalScope.message = _.sprintf i18n.err.exportFailed, err.message
            modalScope.buttons = [label: i18n.btn.ok]
            @modal.open
              backdrop: true
              keyboard: true
              templateUrl: "messagebox.html"
              scope: modalScope

    modal.trigger 'click'