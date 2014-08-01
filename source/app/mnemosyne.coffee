RequestManager = require "../app/request_manager"
SyncMachine    = require "../app/sync_machine"
Utils          = require "../app/utils"
ConnectionManager = require "../app/connection_manager"
# Backbone = require "backbone"
# _        = require "underscore"


getModelKey = (model) ->
  if model instanceof Backbone.Collection
    key = model.getKey?()
    getKey = -> key

  else if typeof model.getKey is 'function'
    getKey = ->
      if id = model.get('id')
        model.getKey() + "/#{id}"
      else
        model.getKey() + "/#{model.get('pending_id')}"
  else
    getKey = ->
      model.get('id')

  return getKey

# Init the request object
initRequest = (method, model, options) ->
  request =
    model: model
    options: options
    method: method
    # Lock important values to avoid conflicts on pagination
    key  : getModelKey(model)
    url  : _.result(model, 'url')

  return request


# Empty the database saving and restoring protected keys list
wipeCache= (ctx) ->
  deferred = $.Deferred()
  backup = []
  deferredArray = _.map(ctx.protectedKeys, (protectedKey) ->
    deferred = $.Deferred()
    Utils.store.getItem(protectedKey)
    .done (val) ->
      backup.push({value: val, key: protectedKey})
    .always ->
      deferred.resolve()
    return deferred
    )
  $.when(deferredArray).then(
    ->
      Utils.store.clear()
      .done ->
        for val in backup
          Utils.store.setItem(val.key, val.value)
        deferred.resolve()
      .fail ->
        console.error 'Fail to clear cache'
        deferred.reject()

  )
  return deferred


# Read the value from cache / server depending on conditions
read = (ctx, request) ->
  deferred = $.Deferred()
  model = request.model

  if not model.cache.enabled
    return serverRead(ctx, request, deferred)

  Utils.store.getItem(request.key())
  .done (value) ->
    validCacheValue(ctx, request, value, deferred)
  .fail ->
    serverRead(ctx, request, deferred)

  return deferred


# Decide to use or update the value depending on
# value.expirationDate, options.forceRefresh, and model.cache.allowExpiredCache
validCacheValue = (ctx, request, value, deferred) ->
  model = request.model
  if request.options.forceRefresh
    return serverRead(ctx, request, deferred)

  # -- Cache expired
  else if value.expirationDate < new Date().getTime()
    console.debug 'cache expired'
    if model.cache.allowExpiredCache and value?
      deferred.resolve(value.data)
    # Try to sync with server
    return serverRead(ctx, request, deferred)

  # -- Cache valid
  else
    console.debug ' cache valid'
    return deferred.resolve(value.data)


# Sync `READ` the model with server
serverRead = (ctx, request, deferred) ->
  console.log "Sync from server"

  if not Utils.isConnected()
    console.log 'No connection'
    if request.model instanceof Backbone.Collection
      return deferred.reject()
    else
      return deferred.reject()

  Backbone.sync('read', request.model, request.options)
  .done (data)->
    console.log "Succeed sync from server"
    addToCache(ctx, request, data).always -> deferred.resolve(data)

  .fail (error) ->
    console.log "Fail sync from server", arguments
    deferred.reject.apply(this, arguments)


# Remove the value of model attributes from the collection
removeFromCollectionCache = (ctx, request, collectionKey) ->
  deferred = $.Deferred()
  model = request.model

  Utils.store.getItem(collectionKey)
  .done (value) ->
    models = value.data
    if model.get('pending_id')
      models = _.filter(models, (m) -> m.pending_id isnt model.get('pending_id'))
    if model.get('id')
      models = _.filter(models, (m) -> m.id isnt model.get('id'))
    Utils.store.setItem(collectionKey, {"data" : models, "expirationDate" : value.expirationDate})
    .done -> deferred.resolve()
    .fail -> onDataBaseError(ctx)
  .fail ->
    # The model doesn't exist
    deferred.resolve()

  return deferred

# Remove the model from all his parents cache
removeFromParentsCache = (ctx, request) ->
  deferred = $.Deferred()

  parentKeys = request.model.getParentKeys?() or []
  return deferred.resolve() if parentKeys.length is 0

  deferredArray = _.map(parentKeys, (parentKey)->
    if typeof parentKey is 'string'
      removeFromCollectionCache(ctx, request, parentKey)
    else
      removeFromCollectionCache(ctx, request, parentKey.key())
    )
  $.when.apply($, deferredArray).then(
    -> deferred.resolve()
    -> deferred.reject())

  return deferred


# Remove the model from cache and parent collections cache
removeFromCache = (ctx, request) ->
  deferred = $.Deferred()
  model = request.model
  if model instanceof Backbone.Collection
    Utils.store.removeItem(model.getKey())
    .always -> deferred.resolve()
  else
    baseKey = model.getKey()
    Utils.store.removeItem(baseKey + "/#{model.get('pending_id')}").always ->
      Utils.store.removeItem(baseKey + "/#{model.get('id')}").always ->
        removeFromParentsCache(ctx, request).always -> deferred.resolve()

  return deferred


# Update / add the value of model attributes into the collection
updateCollectionCache = (ctx, request, collectionKey) ->
  deferred = $.Deferred()
  model = request.model

  Utils.store.getItem(collectionKey)
  .done (value) ->
    models = value.data
    if model.get('pending_id')
      parentModel = _.findWhere(models, "pending_id": model.get('pending_id'))
    else
      parentModel = _.findWhere(models, "id": model.get('id'))

    if parentModel?
      # Update the model
      _.extend(parentModel, model.attributes)
    else
      # Add the model
      models.unshift(model.attributes)
    Utils.store.setItem(collectionKey, {"data" : models, "expirationDate": 0})
    .done -> deferred.resolve()
    .fail ->
      wipeCache(ctx)
      deferred.reject()

  .fail ->
    # Create the collection in cache and add the model
    Utils.store.setItem(collectionKey, {"data" : [model.attributes], "expirationDate": 0})
    .done -> deferred.resolve()
    .fail ->
      wipeCache(ctx)
      deferred.reject()

  return deferred


# Update /  add the model to parents collections
updateParentsCache = (ctx, request) ->
  deferred = $.Deferred()

  return deferred.resolve()  if request.model instanceof Backbone.Collection
  parentKeys = request.model.getParentKeys?() or []
  return deferred.resolve() if parentKeys.length is 0

  deferredArray = _.map(parentKeys, (parentKey) ->
    if typeof parentKey is 'string'
        updateCollectionCache(ctx, request, parentKey)
    else if parentKey.filter?(request.model)
      updateCollectionCache(ctx, request, parentKey.key)
    else
      removeFromCollectionCache(ctx, request, parentKey.key)
    )
  $.when(deferredArray).then(
    -> deferred.resolve()
    -> deferred.reject())

  return deferred


# Update / add the model / collection to cache and parents collections
addToCache = (ctx, request, data) ->
  deferred = $.Deferred()
  model = request.model
  return deferred.resolve() if not model.cache.enabled

  expiredDate = (new Date()).getTime() + model.cache.ttl * 1000

  if model instanceof Backbone.Model
    data ?= model.attributes

  else if model instanceof Backbone.Collection
    data ?= _.map(model.models, (m) -> m.attributes)

  else
    console.warn "Wrong instance for ", model
    return deferred.reject()

  Utils.store.setItem(request.key(), {"data" : data, "expirationDate": expiredDate})
  .done ->
    console.log "Succeed cache write"
    updateParentsCache(ctx, request)
    .always ->
      deferred.resolve()
  .fail ->
    wipeCache(ctx)
    deferred.reject()

  return deferred


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

  _context = null
  constructor: (options={}) ->
    @protectedKeys = options.protectedKeys or []
    @_connectionManager = new ConnectionManager()
    @_requestManager    = new RequestManager
      onSynced  : (request, data) ->
        model = request.model
        return if model.isSynced()
        # Remove the pending model
        if request.method is 'create'
          removeFromCache(_context, request).always ->
            delete model.attributes['pending_id'] if model instanceof Backbone.Model
            addToCache(_context, request, data)

        else if request.method isnt 'delete'
            addToCache(_context, request, data)

        model.finishSync()

      onPending  : (request) ->
        model = request.model
        return if model.isPending()
        if request.method isnt 'delete'
          addToCache(_context, request)

        model.pendingSync()

      onCancelled : (request) ->
        model = request.model
        return if model.isUnsynced()
        if model instanceof Backbone.Model and not model.get('id')
          # Remove the model from offline models and collection
          removeFromCache(_context, request)

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
      request = initRequest(null, model, {})
      return addToCache(_context, request)
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
      Utils.store.getItem(getModelKey(model)())
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
      equest = initRequest(null, model, {})
      return removeFromCache(_context, request)
    return Utils.store.removeItem(key)


  ###
    Clear the entire cache, deleting all pending requests

    return a Deferred
  ###
  cacheClear: ->
    @cancelAllPendingRequests()
    return wipeCache(_context)


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
  cancelAllPendingRequests: ->
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
    request = initRequest(method, model, options)
    switch method
      when 'read'
        read(_context, request)
        .done (data=[]) ->
          options.success?(data, 'success', null)
          model.finishSync()
          deferred.resolve(data)
        .fail ->
          model.unsync()
          deferred.reject.apply this, arguments

      when 'delete'
        removeFromCache(_context, request)
        deferred = _context._requestManager.sync(request)

      else #update - create
        deferred = _context._requestManager.sync(request)

    return deferred


  ###
    Allow you to register a callback on severals events
    The `key` is to provide easier unsubcription when using
    anonymous function.
  ###
  subscribe: (event, key, callback)->
    _context._connectionManager.subscribe(event, key, callback)


  ###
    Allow you to unregister a callback for a given key
  ###
  unsubscribe: (key) ->
    _context._connectionManager.unsubscribe(event, key)


  ###
    return a boolean
  ###
  isOnline: -> _context._connectionManager.isOnline()


  # Export sync machine
  @SyncMachine = SyncMachine

class MnemosyneModel

  getPendingId: ->
    return @get('pending_id')

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
