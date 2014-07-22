RequestManager = require "../app/request_manager"
SyncMachine    = require "../app/sync_machine"
Utils          = require "../app/utils"
ConnectionManager = require "../app/connection_manager"
# Backbone = require "backbone"
# _        = require "underscore"


# Read the value from cache / server depending on conditions
read = (ctx, model, options) ->
  deferred = $.Deferred()

  if typeof model.getKey isnt 'function' or not model.cache.enabled
    return serverRead(ctx, model, options, deferred)

  Utils.store.getItem(model.getKey())
  .done (value) ->
    validCacheValue(ctx, model, options, value, deferred)
  .fail ->
    serverRead(ctx, model, options, deferred)

  return deferred


# Decide to use or update the value depending on
# value.expirationDate, options.forceRefresh, and model.cache.allowExpiredCache
validCacheValue = (ctx, model, options, value, deferred) ->
  if options.forceRefresh
    serverRead(ctx, model, options, deferred)

  # -- Cache expired
  else if value.expirationDate < new Date().getTime()
    if model.cache.allowExpiredCache and value?
      deferred.resolve(value.data)
    # Try to sync with server
    serverRead(ctx, model, options, deferred)

  # -- Cache valid
  else
    deferred.resolve(value.data)


# Sync `UPDATE` the model with server
serverRead = (ctx, model, options, deferred) ->
  console.log "Sync from server"

  if not Utils.isConnected()
    console.log 'No connection'
    if model instanceof Backbone.Collection
      return deferred.resolve([])
    else
      return deferred.reject()

  Backbone.sync('read', model, options)
  .done (value)->
    console.log "Succeed sync from server"
    updateCache(ctx, model, value).always -> deferred.resolve(value)

  .fail (error) ->
    console.log "Fail sync from server"
    deferred.reject.apply(this, arguments)


# Remove the value of model attributes from the collection
removeFromCollectionCache = (ctx, collectionKey, model) ->
  deferred = $.Deferred()

  Utils.store.getItem(collectionKey)
  .done (value) ->
    models = value.data
    models = _.filter(models, (m) -> m.id isnt model.get('id'))
    Utils.store.setItem(collectionKey, {"data" : models, "expirationDate" : value.expirationDate})
    .always ->
      deferred.resolve()
  .fail ->
    # The model doesn't exist
    deferred.resolve()

  return deferred

# Remove the model from all his parents cache
removeFromParentsCache = (ctx, model) ->
  deferred = $.Deferred()

  parentKeys = model.getParentKeys()
  return deferred.resolve() if parentKeys.length is 0

  deferredArray = _.map(parentKeys, (parentKey)->
    removeFromCollectionCache(ctx, parentKey, model)
    )
  $.when.apply($, deferredArray).then(
    -> deferred.resolve()
    -> deferred.reject())

  return deferred


# Remove the model from cache and parent collections cache
removeFromCache = (ctx, model) ->
  deferred = $.Deferred()

  Utils.store.removeItem(model).always ->
    removeFromParentsCache(ctx, model).always -> deferred.resolve()

  return deferred


# Update / add the value of model attributes into the collection
updateCollectionCache = (ctx, collectionKey, model) ->
  deferred = $.Deferred()

  Utils.store.getItem(collectionKey)
  .done (value) ->
    models = value.data
    parentModel = _.findWhere(models, "id": model.get('id'))
    if parentModel?
      # Update the model
      _.extend(parentModel, model.attributes)
    else
      # Add the model
      models.unshift(model.attributes)
    Utils.store.setItem(collectionKey, {"data" : models, "expirationDate": 0})
    .always ->
      deferred.resolve()
  .fail ->
    # Create the collection in cache and add the model
    Utils.store.setItem(collectionKey, {"data" : [model.attributes], "expirationDate": 0})
    .done ->
      deferred.resolve()
    .fail ->
      deferred.reject()

  return deferred


# Update /  add the model to parents collections
updateParentsCache = (ctx, model) ->
  deferred = $.Deferred()

  return deferred.resolve()  if model instanceof Backbone.Collection
  parentKeys = model.getParentKeys()
  return deferred.resolve() if parentKeys.length is 0

  deferredArray = _.map(parentKeys, (parentKey) ->
    # <<<<< TODO ADD filter >>>>>
    updateCollectionCache(ctx, parentKey, model)
  )
  $.when(deferredArray).then(
    -> deferred.resolve()
    -> deferred.reject())

  return deferred


# Update / add the model to cache and parents collections
updateCache = (ctx, model, data) ->

  deferred = $.Deferred()
  return deferred.resolve() if not model.cache.enabled

  expiredDate = (new Date()).getTime() + model.cache.ttl * 1000

  if model instanceof Backbone.Model and not model.get('id')?
    ctx._offlineModels = Utils.addWithoutDuplicates(ctx._offlineModels, model)
    updateParentsCache(ctx, model).always -> deferred.resolve()
  else
    if model instanceof Backbone.Model
      data ?= model.attributes

    else if model instanceof Backbone.Collection
      data ?= _.map(model.models, (m) -> m.attributes)

    else
      console.warn "Wrong instance for ", model
      return deferred.reject()

    Utils.store.setItem(model.getKey(), {"data" : data, "expirationDate": expiredDate})
    .done ->
        console.log "Succeed cache write"
        updateParentsCache(ctx, model)
        .always ->
          deferred.resolve()
    .fail ->
        console.log "fail cache write"
        deferred.reject()


  return deferred


# Remove the model from offlines models
removePendingModel = (ctx, model) ->
  return if not model instanceof Backbone.Model
  ctx._offlineModels = _.filter(ctx._offlineModels, (m) -> m.get('_pending_id') isnt model.get('_pending_id'))


###
  ------- Let's create Mnemosyne ! -------
###

defaultOptions =
  forceRefresh: no

defaultCacheOptions =
  enabled : no
  ttl     : 0 # seconds
  allowExpiredCache : yes

module.exports = class Mnemosyne

  _requestManager: null
  _connectionManager: null

  # Contains all offlines models
  _offlineModels: []

  _context = null
  constructor: ->
    @_connectionManager = new ConnectionManager()
    @_requestManager    = new RequestManager
      onSynced  : (model, method, value) ->
        return if model.isSynced()
        if method isnt 'delete'
          updateCache(_context, model, value)

        # Remove the model from offline models and collection
        removePendingModel(_context, model)
        model.finishSync()

      onPending  : (model, method) ->
        return if model.isPending()
        if method isnt 'delete'
          updateCache(_context, model)

        # Add the model to offline models
        if not model.get('id')?
          _context._offlineModels = Utils.addWithoutDuplicates(_context._offlineModels, model)

        model.pendingSync()

      onCancelled : (model) ->
        return if model.isUnsynced()
        if model instanceof Backbone.Model
          # Remove the model from offline models and collection
          removePendingModel(_context, model)

        model.unsync()

    _context = @


  ###
    Set the value of key, model or collection in cache.
    If `key` parameter is a model, parent collections will be updated

    return a Deferred
  ###
  cacheWrite : (key, value) ->
    if key instanceof Backbone.Model or key instanceof Backbone.Collection
      model = key
      model.cache = _.defaults(model.cache or {}, defaultCacheOptions)
      return updateCache(_context, model)
    return Utils.store.setItem(key, value)


  ###
    Get the value of a key, model or collection in cache.

    return a Deferred
  ###
  cacheRead  : (key) ->
    if key instanceof Backbone.Model or key instanceof Backbone.Collection
      model = key
      deferred = $.Deferred()
      return deferred.reject() if typeof model.getKey isnt 'function'
      Utils.store.getItem(model.getKey())
      .done (value) -> deferred.resolve(value.data)
      .fail -> deferred.reject()
      return deferred
    return Utils.store.getItem(key)


  ###
    Remove a value, model or a collection from cache.

    return a Deferred
  ###
  cacheRemove: (key) ->
    if key instanceof Backbone.Model or key instanceof Backbone.Collection
      model = key
      return removeFromCache(_context, model)
    return Utils.store.removeItem(key)


  ###
    Clear the entire cache, deleting all pending requests

    return a Deferred
  ###
  cacheClear: ->
    @clear()
    return Utils.store.clear();


  ###
    return an Array of all pending requests
      (see RequestManager doc for `request` object)
  ###
  getPendingRequests: ->
    _context._requestManager.getPendingRequests()


  ###
    Retry the synchronisation setting the timeout to the lowest value
  ###
  retrySync: ->
    _context._requestManager.retrySync()


  ###
    Cancel the pending request corresponding to the `key` parameter
  ###
  cancelPendingRequest: (key) ->
    request = @pendingRequests.retrieveItem(key)
    return if not request?
    cancelRequest(@, request)


  ###
    Cancel all pending requests
  ###
  clear: ->
    _context._offlineModels = []
    _context._requestManager.clear()


  ###
    Overrides the Backbone.sync method
  ###
  sync: (method, model, options = {}) ->
    deferred    = $.Deferred()
    options     = _.defaults(options, defaultOptions)
    model.cache = _.defaults(model.cache or {}, defaultCacheOptions)

    console.log "\n" + model.getKey()

    model.beginSync()
    switch method
      when 'read'
        read(_context, model, options)
        .done (data=[]) ->
          options.success?(data, 'success', null)
          model.finishSync()
          deferred.resolve(data)
        .fail ->
          deferred.reject.apply this, arguments
          model.unsync()

      when 'delete'
        removePendingModel(_context, model)
        removeFromCache(_context, model)
        deferred = _context._requestManager.sync(method, model, options)

      else #update - create
        deferred = _context._requestManager.sync(method, model, options)

    return deferred


  ###
    Allow you to register a callback on severals events
    The `key` is to provide easier unsubcription when using
    anonymous function.
  ###
  subscribe: (event, key, callback)->
    _context._connectionManager.subscribe(event, key, callback)


  ###
    Allow you to unregister a callback for a given event-key
  ###
  unsubscribe: (event, key) ->
    _context._connectionManager.unsubscribe(event, key)


  ###
    return a boolean
  ###
  isOnline: -> _context._connectionManager.isOnline()


  # Export sync machine
  @SyncMachine = SyncMachine

class MnemosyneModel

  getPendingId: ->
    return @get('_pending_id')

  getParentKeys: -> []

  sync: -> Mnemosyne.prototype.sync.apply this, arguments

class MnemosyneCollection

  sync: -> Mnemosyne.prototype.sync.apply this, arguments

_destroy = Backbone.Model.prototype.destroy
Backbone.Model.prototype.destroy = ->
  _isNew = this.isNew
  this.isNew = -> false
  ret = _destroy.apply this, arguments
  this.isNew = _isNew
  return ret

_.extend Backbone.Model.prototype, SyncMachine
_.extend Backbone.Model.prototype, MnemosyneModel.prototype

_.extend Backbone.Collection.prototype, SyncMachine
_.extend Backbone.Collection.prototype, MnemosyneCollection.prototype
