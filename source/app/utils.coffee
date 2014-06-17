# Backbone = require 'backbone'

module.exports = class Utils

  @isConnected = ->
    return window.navigator.onLine


  @isCollection = (model) ->
    return model instanceof Backbone.Collection


  @isModel = (model) ->
    return model instanceof Backbone.Model


  # The model has to implements "equals" method
  @addWithoutDuplicates = (array, model) ->
    return if not model? or typeof model.equals isnt "function"
    array = _.filter(array, (m) -> not model.equals(m))
    array.unshift(model)

  # Mock localForage
  @store = {}
  @store.getItem = (key) ->
    value = localStorage.getItem(key)
    if value?
      return $.Deferred().resolve(JSON.parse(value))
    return $.Deferred().reject()


  @store.setItem = (key, value) ->
    localStorage.setItem(key, JSON.stringify(value))
    return $.Deferred().resolve()


  @store.removeItem = (key) ->
    localStorage.removeItem(key)
    return $.Deferred().resolve()


  @store.clear = ->
    localStorage.clear()
    return $.Deferred().resolve()
