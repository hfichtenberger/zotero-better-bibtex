# Components.utils.importGlobalProperties(['Blob'])

Zotero_BetterBibTeX_ErrorReport = new class
  constructor: ->
    @form = JSON.parse(Zotero.File.getContentsFromURL("resource://zotero-better-bibtex/logs/s3.json"))

  submit: (filename, data, callback) ->
    fd = new FormData()
    for own name, value of @form.fields
      fd.append(name, value)

    file = new Blob([data], { type: 'text/plain'})
    fd.append('file', file, "#{@timestamp}-#{@key}-#{filename}")

    request = Components.classes["@mozilla.org/xmlextras/xmlhttprequest;1"].createInstance()
    request.open('POST', @form.action, true)

    request.onload = (e) ->
      Zotero.debug("BBT.error.submit.onload: #{request.readystate}")
      return unless request.readystate == 4
        callback(request)
    request.onerror = (e) ->
      callback(request)
    request.send(fd)

  init: ->
    Zotero.debug('BBT.error.init')
    @key = Zotero.Utilities.generateObjectKey()
    @timestamp = (new Date()).toISOString().replace(/\..*/, '').replace(/:/g, '.')
    Zotero.debug("BBT.error.init: #{@key}")

    wizard = document.getElementById('zotero-error-report')
    continueButton = wizard.getButton('next')
    continueButton.disabled = true
    document.getElementById('zotero-references').hidden = true

    Zotero.debug("BBT.error.init: here we go")

    Zotero.getSystemInfo((info) =>
      schema = {}
      for table in Zotero.DB.columnQuery("SELECT name FROM betterbibtex.sqlite_master WHERE type='table' AND name <> 'schema' ORDER BY name") || []
        schema[table] = Zotero.BetterBibTeX.table_info(table)
      schema = "Better BibTeX schema #{Zotero.DB.valueQuery('select version from betterbibtex.schema') || '<new>'}: #{JSON.stringify(schema)}"
      info += "\n\n#{schema}"

      @errorLog = {
        full: Zotero.getErrors(true).join('\n') + "\n\n" + info + "\n\n"
      }
      @errorLog.truncated = @errorLog.full

      maxSize = if @form.maxSize then (@form.maxSize - @errorLog.full.length) * 0.95 else null
      debug = Zotero.Debug.get()
      debug = debug.slice(-1 * maxSize) if maxSize && debug.length > maxSize
      @errorLog.full += debug

      debug = debug.split("\n")
      debug = debug.slice(0, 5000) # max 5k lines
      debug = (Zotero.Utilities.ellipsize(line, 80, true) for line in debug) # trim lines
      debug = debug.join("\n")
      @errorLog.truncated += debug

      Zotero.debug("BBT.error.init: message set")

      params = window.arguments[0].wrappedJSObject
      if params.references
        document.getElementById('zotero-references').hidden = false
        document.getElementById('zotero-references').value = params.references.substring(0, 5000)
        Zotero.debug("BBT.error.init: references set")

      document.getElementById('zotero-error-message').value = @errorLog.truncated
      Zotero.debug("BBT.error.init: error log set")

      continueButton.disabled = false
      continueButton.focus()
      str = Zotero.getString('errorReport.advanceMessage', continueButton.getAttribute('label')).replace('Zotero', 'ZotPlus')
      document.getElementById('zotero-advance-message').setAttribute('value', str)
      Zotero.debug("BBT.error.init: proceed")
    )

  finished: ->
    Zotero.debug("BBT.error.finished")
    wizard = document.getElementById('zotero-error-report')
    wizard.advance()
    wizard.getButton('cancel').disabled = true
    wizard.canRewind = false

    document.getElementById('zotero-report-id').setAttribute('value', @key)
    document.getElementById('zotero-report-result').hidden = false

  verify: (request) ->
    Zotero.debug("BBT.error.verify: #{request.status}")
    wizard = document.getElementById('zotero-error-report')
    ps = Components.classes['@mozilla.org/embedcomp/prompt-service;1'].getService(Components.interfaces.nsIPromptService)

    switch
      when !request || !request.status || request.status > 1000
        ps.alert(null, Zotero.getString('general.error'), Zotero.getString('errorReport.noNetworkConnection') + ': ' + request?.status)
      when request.status != parseInt(@form.fields.success_action_status)
        ps.alert(null, Zotero.getString('general.error'), Zotero.getString('errorReport.invalidResponseRepository') + ': ' + request.status + ': ' + request.responseText)
      else
        return true

    wizard.rewind() if wizard?.rewind
    return false

  sendErrorReport: ->
    Zotero.debug("BBT.error.send")
    wizard = document.getElementById('zotero-error-report')
    continueButton = wizard.getButton('next')
    continueButton.disabled = true

    params = window.arguments[0].wrappedJSObject

    @submit('errorlog.txt', @errorLog.full, (request) =>
      Zotero.debug("BBT.error.send done: errorlog.txt")
      return unless @verify(request)

      return @finished() unless params.references

      @submit('references.json', params.references, (request) =>
        Zotero.debug("BBT.error.send done: references.json")
        return unless @verify(request)

        @finished()
      )
    )
