
###
  Manage the connection, provide callbacks on connection lost and recovered
###
module.exports = class  ConnectionManager

  _CHECK_INTERVAL = 1000 #ms
  _connectionLostCallbacks      : {}
  _connectionRecoveredCallbacks : {}

  constructor: ->
    @_watchConnection()
    @onLine = window.navigator.onLine

  _watchConnection: =>
    # Connection revovered
    if window.navigator.onLine and not @onLine
      _.map(@_connectionRecoveredCallbacks, (callback) ->
        try
          callback(true)
        catch e
          console.error "Cannot call ", callback
          )

    # Connection lost
    else if not window.navigator.onLine and @onLine
      _.map(@_connectionLostCallbacks, (callback) ->
        try
          callback(false)
        catch e
          console.error "Cannot call ", callback
          )

    @onLine = window.navigator.onLine
    setTimeout(@_watchConnection, _CHECK_INTERVAL)

  subscribe: (event, key, callback) ->
    return if typeof key isnt 'string' or typeof callback isnt 'function'
    switch event
      when 'connectionLost'
        @_connectionLostCallbacks[key] = callback
      when 'connectionRecovered'
        @_connectionRecoveredCallbacks[key] = callback
      else
        console.warn 'No callback for ', event

  unsubscribe: (event, key) ->
    switch event
      when 'connectionLost'
        delete @_connectionLostCallbacks[key]
      when 'connectionRecovered'
        delete @_connectionRecoveredCallbacks[key]
      else
        console.warn 'No callback for ', event

  isOnline: -> window.navigator.onLine
