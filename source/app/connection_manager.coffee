Utils = require "../app/utils"


###
  Watch the connection, providing callbacks on connection lost and recovered
###
module.exports = class  ConnectionManager

  _CHECK_INTERVAL = 1000 #ms
  _connectionLostCallbacks      : {}
  _connectionRecoveredCallbacks : {}

  constructor: (@isOnline = Utils.isOnline)->
    @_watchConnection()
    @onLine = @isOnline()

  _watchConnection: =>
    # Connection revovered
    if @isOnline() and not @onLine
      _.map(@_connectionRecoveredCallbacks, (callback) ->
        try
          callback(true)
        catch e
          console.error "Cannot call ", callback
          )

    # Connection lost
    else if not @isOnline() and @onLine
      _.map(@_connectionLostCallbacks, (callback) ->
        try
          callback(false)
        catch e
          console.error "Cannot call ", callback
          )

    @onLine = @isOnline()
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

  unsubscribe: (key) ->
    delete @_connectionLostCallbacks[key]
    delete @_connectionRecoveredCallbacks[key]
