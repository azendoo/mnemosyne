# Backbone = require 'backbone'

module.exports = class Utils

  # Return true if we are connected, false otherwise ;)
  @isOnline = ->
    # Require cordova plugin org.apache.cordova.core.network-information
    if window.device && window.navigator.connection?
      return window.navigator.connection.type isnt Connection.NONE
    else
      return window.navigator.onLine


  @addWithoutDuplicates = (array, model) ->
    return if not model?
    array = _.filter(array, (m) -> model.get('_pending_id') isnt m.get('_pending_id'))
    array.unshift(model)
    return array


  # Temporary use localStorage for easy debugging, (-> use localForage)
  @store = {}
  @store.getItem = (key) ->
    value = localStorage.getItem(key)
    if value?
      return $.Deferred().resolve(JSON.parse(value))
    return $.Deferred().reject()


  @store.setItem = (key, value) ->
    try
      localStorage.setItem(key, JSON.stringify(value))
    catch e
      return $.Deferred().reject()
    return $.Deferred().resolve()


  @store.removeItem = (key) ->
    localStorage.removeItem(key)
    return $.Deferred().resolve()


  @store.clear = ->
    localStorage.clear()
    return $.Deferred().resolve()
