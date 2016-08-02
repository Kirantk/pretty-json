{CompositeDisposable} = require 'atom'
formatter = {}

formatter.space = (scope) ->
  softTabs = [atom.config.get 'editor.softTabs', scope: scope]
  tabLength = Number [atom.config.get 'editor.tabLength', scope: scope]
  if softTabs?
    return Array(tabLength + 1).join ' '
  else
    return '\t'

formatter.stringify = (obj, scope, sorted) ->
  # lazy load requirements
  JSONbig = require 'json-bigint'
  stringify = require 'json-stable-stringify'
  BigNumber = require 'bignumber.js'

  space = formatter.space scope
  if sorted
    return stringify obj,
      space: space
      replacer: (key, value) ->
        try
          if value.constructor.name is 'BigNumber'
            return JSONbig.stringify value
        catch
          # ignore
        return value
  else
    return JSONbig.stringify obj, null, space

formatter.parseAndValidate = (text) ->
  JSONbig = require 'json-bigint' # lazy load requirements
  try
    return JSONbig.parse text
  catch error
    if atom.config.get 'pretty-json.notifyOnParseError'
      atom.notifications.addWarning "JSON Pretty: #{error.name}: #{error.message} at character #{error.at} near \"#{error.text}\""
    throw error

formatter.pretty = (text, scope, sorted) ->
  try
    parsed = formatter.parseAndValidate text
  catch error
    return text
  return formatter.stringify parsed, scope, sorted

formatter.minify = (text) ->
  try
    formatter.parseAndValidate text
  catch error
    return text
  uglify = require 'jsonminify' # lazy load requirements
  return uglify text

formatter.jsonify = (text, scope, sorted) ->
  vm = require 'vm' # lazy load requirements
  try
    vm.runInThisContext "newObject = #{text};"
  catch error
    if atom.config.get 'pretty-json.notifyOnParseError'
      atom.notifications.addWarning "JSON Pretty: eval issue: #{error}"
    return text
  return formatter.stringify newObject, scope, sorted

PrettyJSON =
  config:
    notifyOnParseError:
      type: 'boolean'
      default: true
    prettifyOnSaveJSON:
      type: 'boolean'
      default: false
      title: 'Prettify On Save JSON'
    grammars:
      type: 'array'
      default: ['source.json', 'text.plain.null-grammar']

  doEntireFile: (editor) ->
    grammars = atom.config.get 'pretty-json.grammars' ? []
    if editor?.getGrammar().scopeName not in grammars
      return false
    return editor.getLastSelection().isEmpty()

  replaceText: (editor, fn) ->
    editor.mutateSelectedText (selection) ->
      selection.getBufferRange()
      text = selection.getText()
      selection.deleteSelectedText()
      range = selection.insertText fn text
      selection.setBufferRange range

  prettify: (editor, entire, sorted) ->
    if entire
      pos = editor.getCursorScreenPosition()
      editor.setText formatter.pretty editor.getText(), editor.getRootScopeDescriptor(), sorted
    else
      pos = editor.getLastSelection().getScreenRange().start
      @replaceText editor, (text) -> formatter.pretty text, ['source.json'], sorted
    editor.setCursorScreenPosition pos

  minify: (editor, entire) ->
    if entire
      pos = [0, 0]
      editor.setText formatter.minify editor.getText()
    else
      pos = editor.getLastSelection().getScreenRange().start
      @replaceText editor, (text) -> formatter.minify text
    editor.setCursorScreenPosition pos

  jsonify: (editor, entire, sorted) ->
    if entire
      pos = editor.getCursorScreenPosition()
      editor.setText formatter.jsonify editor.getText(), editor.getRootScopeDescriptor(), sorted
    else
      pos = editor.getLastSelection().getScreenRange().start
      @replaceText editor, (text) -> formatter.jsonify text, ['source.json'], sorted
    editor.setCursorScreenPosition pos

  activate: ->
    atom.commands.add 'atom-workspace',
      'pretty-json:prettify': =>
        editor = atom.workspace.getActiveTextEditor()
        entire = @doEntireFile editor
        @prettify editor, entire, false
      'pretty-json:minify': =>
        editor = atom.workspace.getActiveTextEditor()
        entire = @doEntireFile editor
        @minify editor, entire
      'pretty-json:sort-and-prettify': =>
        editor = atom.workspace.getActiveTextEditor()
        entire = @doEntireFile editor
        @prettify editor, entire, true
      'pretty-json:jsonify-literal-and-prettify': =>
        editor = atom.workspace.getActiveTextEditor()
        entire = @doEntireFile editor
        @jsonify editor, entire, false
      'pretty-json:jsonify-literal-and-sort-and-prettify': =>
        editor = atom.workspace.getActiveTextEditor()
        entire = @doEntireFile editor
        @jsonify editor, entire, true

    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.config.observe 'pretty-json.prettifyOnSaveJSON', (value) =>
      @saveSubscriptions?.dispose()
      @saveSubscriptions = new CompositeDisposable()
      if value
        @subscribeToSaveEvents()

  subscribeToSaveEvents: ->
    @saveSubscriptions.add atom.workspace.observeTextEditors (editor) =>
      return if not editor?.getBuffer()
      bufferSubscriptions = new CompositeDisposable()
      bufferSubscriptions.add editor.getBuffer().onWillSave (filePath) =>
        entire = @doEntireFile editor
        if entire
          @prettify editor, entire, false
      bufferSubscriptions.add editor.getBuffer().onDidDestroy ->
        bufferSubscriptions.dispose()
      @saveSubscriptions.add bufferSubscriptions

  deactivate: ->
    @subscriptions?.dispose()
    @subscriptions = null

module.exports = PrettyJSON
