RequestManager = require "../app/request_manager"
SyncMachine    = require "../app/sync_machine"
Utils          = require "../app/utils"
debug          = Utils.debug
# Backbone = require "backbone"
# _        = require "underscore"

MNEMOSYNE_DB_VERSION = 1

# Check if the version has been updated, wipeCache in this case
checkVersion = (ctx) ->
  Utils.store.getItem("MNEMOSYNE_DB_VERSION")
  .done (previousBaseVersion) ->
    wipeCache(ctx) if previousBaseVersion < MNEMOSYNE_DB_VERSION
  .fail -> wipeCache(ctx)



# Init the request object
initRequest = (method, model, options) ->
  if model instanceof Backbone.Model and not model.get('id')
    model.attributes['pending_id'] = new Date().getTime()
  enabled = model.cache.enabled
  enabled = false if options.data?.page > 1
  request =
    model: model
    options: options
    method: method
    # Lock important values to avoid conflicts on pagination
    key  : model.getKey()
    url  : _.result(model, 'url')
    cacheEnabled: enabled

  return request


# Empty the database saving and restoring protected keys list
wipeCache= (ctx) ->
  console.log("Mnemosyne: wipe cache")
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
        Utils.store.setItem("MNEMOSYNE_DB_VERSION", MNEMOSYNE_DB_VERSION)
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

  serverRead(ctx, request)
  .done ->
    debug("read","success")
    deferred.resolve.apply this, arguments

  .fail ->
    debug("read","fail")
    args = arguments
    ctx.cacheRead(request.key)
    .done -> deferred.resolve.apply this, arguments
    .fail -> deferred.reject.apply this, args

  return deferred


# Sync `READ` the model with server
serverRead = (ctx, request) ->
  Backbone.sync('read', request.model, request.options)
  .done (value)->
    debug("serverRead", "success")
    addToCache(ctx, request, value)

  .fail -> debug("serverRead", "fail")
  .always -> request.model.trigger 'sync:args', arguments[0], arguments[1], arguments[2]


# Remove the value of model attributes from the collection
removeFromCollectionCache = (ctx, request, collectionKey) ->
  deferred = $.Deferred()
  model = request.model

  Utils.store.getItem(collectionKey)
  .done (value) ->
    models = value
    if model.get('pending_id')
      models = _.filter(models, (m) -> m.pending_id isnt model.get('pending_id'))
    if model.get('id')
      models = _.filter(models, (m) -> m.id isnt model.get('id'))
    Utils.store.setItem(collectionKey, models)
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
      removeFromCollectionCache(ctx, request, parentKey.key)
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
    Utils.store.removeItem(request.key).always ->
      removeFromParentsCache(ctx, request).always -> deferred.resolve()

  return deferred


# Update / add the value of model attributes into the collection
updateCollectionCache = (ctx, request, collectionKey) ->
  deferred = $.Deferred()
  model = request.model

  Utils.store.getItem(collectionKey)
  .done (value) ->
    models = value
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
    Utils.store.setItem(collectionKey, models)
    .done -> deferred.resolve()
    .fail ->
      wipeCache(ctx)
      deferred.reject()

  .fail ->
    # Create the collection in cache and add the model
    Utils.store.setItem(collectionKey, [model.attributes])
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
  return deferred.resolve() if not request.cacheEnabled

  if model instanceof Backbone.Model
    data ?= model.attributes

  else if model instanceof Backbone.Collection
    data ?= _.map(model.models, (m) -> m.attributes)
    if request.options.data?.page > 1
      console.warn 'Attempting to save page > 1'
      return deferred.resolve()

  else
    console.warn "Wrong instance for ", model
    return deferred.reject()

  Utils.store.setItem(request.key, data)
  .done ->
    debug("addToCache", "success")
    updateParentsCache(ctx, request)
    .always ->
      deferred.resolve()
  .fail ->
    debug("addToCache", "fail")
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

module.exports = class Mnemosyne

  _requestManager: null
  _context = null
  constructor: (options={}) ->
    @protectedKeys = options.protectedKeys or []
    @_requestManager = new RequestManager
      onSynced  : (request, method, data) ->
        model = request.model
        return if model.isSynced()
        # Remove the pending model
        if method is 'create'
          removeFromCache(_context, request).always ->
            delete model.attributes['pending_id'] if model instanceof Backbone.Model
            request.key = model.getKey()
            addToCache(_context, request, data)

        else if method isnt 'delete'
            addToCache(_context, request, data)

        model.finishSync()

      onPending  : (request, method) ->
        model = request.model
        return if model.isPending()
        if method isnt 'delete'
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
    checkVersion(_context)


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
      key = key.getKey()
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

    model.beginSync()
    request = initRequest(method, model, options)
    debug("sync", request.key)
    switch method
      when 'read'
        read(_context, request)
        .done ->
          options.success?.apply this, arguments
          model.finishSync()
          deferred.resolve.apply this, arguments
        .fail ->
          model.unsync()
          deferred.reject.apply this, arguments

      when 'delete'
        removeFromCache(_context, request)
        deferred = _context._requestManager.sync(request)

      else #update - create
        deferred = _context._requestManager.sync(request)

    return deferred

  # Export sync machine
  @SyncMachine = SyncMachine

class MnemosyneModel

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
