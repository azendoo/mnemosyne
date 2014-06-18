RequestManager = require "../app/request_manager"
SyncMachine    = require "../app/sync_machine"
Utils          = require "../app/utils"
# Backbone = require "backbone"
# _        = require "underscore"



###
  ------- Private methods -------
###

read = (ctx, model, options) ->
  deferred = $.Deferred()

  if not model.getKey?()? or not model.cache.enabled
    console.log "Cache forbidden"
    return serverRead(ctx, model, options, null, deferred)

  console.log "Try loading value from cache"
  load(model.getKey())
  .done (item) ->
    console.log "Succeed to read from cache"
    cacheRead(ctx, model, options, item, deferred)
  .fail ->
    console.log "Fail to read from cache"
    serverRead(ctx, model, options, null, deferred)

  return deferred


cacheRead = (ctx, model, options, item, deferred) ->
  # -- Cache expired

  # DEBUG
  if Utils.isCollection(model)
    _.map(item.value, (element) -> console.warn('New model read in cache !') if not element.id?)

  if options.forceRefresh or item.expirationDate < new Date().getTime()
    console.log "-- cache expired"
    serverRead(ctx, model, options, item, deferred)

  # -- Cache valid
  else
    console.log "-- cache valid"
    options.success?(item.value, 'success', null)
    deferred?.resolve(item.value)
    model.finishSync()


serverRead = (ctx, model, options, fallbackItem, deferred) ->
  console.log "Sync from server"

  # Return cache data and update silently the cache
  if fallbackItem? and model.cache.allowExpiredCache and not options.forceRefresh
    # options.success?(fallbackItem.value, 'success', null)
    deferred.resolve(fallbackItem.value)
    model.finishSync()
    options.silent = true

  if not Utils.isConnected()
    model.finishSync()
    console.log 'No connection'
    if Utils.isCollection(model)
      return deferred.resolve([])
    else
      return deferred.reject()

  Backbone.sync('read', model, options)
  .done ->
    console.log "Succeed sync from server"
    model.attributes = arguments[0]
    updateCache(ctx, model)
    .always ->
      if deferred.state() isnt "resolved"
        model.finishSync()
        deferred.resolve.apply(this, arguments)
  .fail (error) ->
    console.log "Fail sync from server"
    if deferred.state() isnt "resolved"
      deferred.reject.apply(this, arguments)
      model.unsync()


load = (key) ->
  deferred = $.Deferred()

  Utils.store.getItem(key)
  .then(
    (item) ->
      if _.isEmpty(item) or not item.value?
        deferred.reject()
      else
        deferred.resolve(item)
    ->
      deferred.reject()
    )

  return deferred



removeFromParentCache = (ctx, model) ->
  deferred = $.Deferred()

  # DEBUG
  if Utils.isCollection(model)
    console.warn 'removeParentFromCache: collection as argument !'
    return deferred.resolve()

  if model.isNew()
    console.warn 'removeParentFromCache: model is new !'
    return deferred.resolve()

  parentKey = model.getParentKey()

  load(parentKey)
  .done (item) ->
    models = item.value
    models = _.filter(models, (m) -> m.id isnt model.get('id'))
    Utils.store.setItem(parentKey, {"value" : models, "expirationDate" : item.expirationDate})
    .always ->
      deferred.resolve()
  .fail ->
    # The model doesn't exist
    deferred.resolve()

  return deferred

updateParentCache = (ctx, model) ->
  deferred = $.Deferred()

  # return deferred.resolve()  if model instanceof Backbone.Collection
  return deferred.resolve()  if Utils.isCollection(model) or typeof model.getParentKey isnt 'function'
  parentKey = model.getParentKey()
  console.log "Updating parent cache [#{parentKey}]"

  # Don't update cache, just add/update pending models
  if model.isNew()
    # just add to unsynced models and collections
    ctx._offlineCollections[parentKey] ?= []
    ctx._offlineCollections[parentKey] = Utils.addWithoutDuplicates(ctx._offlineCollections[parentKey], model)
    deferred.resolve()
  else
    load(parentKey)
    .done (item) ->
      models = item.value
      parentModel = _.findWhere(models, "id": model.get('id'))
      if parentModel?
        _.extend(parentModel, model.attributes)
      else
        models.unshift(model.attributes)
      Utils.store.setItem(parentKey, {"value" : models, "expirationDate": 0})
      .always ->
        deferred.resolve()
    .fail ->
      # Create the collection in cache
      Utils.store.setItem(parentKey, {"value" : [model], "expirationDate": 0})
      deferred.resolve()

  return deferred


updateCache = (ctx, model) ->
  deferred = $.Deferred()

  expiredDate = (new Date()).getTime() + model.cache.ttl * 1000
  console.log "Try to write cache -- expires at #{expiredDate}"

  value = null
  # if model instanceof Backbone.Model
  if not model.models?
    value = model.attributes
  # else if model instanceof Backbone.Collection
   else if model.models?
    value = _.map(model.models, (m) -> m.attributes)
  else
    console.warn "Wrong instance for ", model
    return deferred.reject()

  if Utils.isModel(model) and model.isNew()
    ctx._offlineModels = Utils.addWithoutDuplicates(ctx._offlineModels, model)
    deferred.resolve()
  else
    # DEBUG
    if Utils.isCollection(model)
      _.map(value, (element) -> console.warn('New model in cache !') if not element.id?)


    Utils.store.setItem(model.getKey(), {"value" : value, "expirationDate": expiredDate})
    .then(
      ->
        console.log "Succeed cache write"
        updateParentCache(ctx, model)
        .always ->
          deferred.resolve()
      ->
        console.log "fail cache write"
        deferred.reject()
    )

  return deferred


serverWrite = (ctx, method, model, options, deferred ) ->
  console.log "serverWrite"

  updateCache(ctx, model)
  .done ->
    ctx._requestManager.safeSync(method, model, options)
    .done (value)->
      deferred.resolve.apply this, arguments
    .fail ->
      deferred.reject.apply this, arguments
  .fail ->
    console.log "fail"
    model.unsync()
    deferred.reject.apply this, arguments
    Utils.store.removeItem(model.getKey())


###
  Wrap promise using jQuery Deferred
###
wrapPromise = (ctx, promise) ->
  deferred = $.Deferred()
  promise.then(
    ->
      deferred.resolve()
    ->
      deferred.reject()
    )
  return deferred

removePendingModel = (ctx, model) ->
  ctx._offlineModels = _.filter(ctx._offlineModels, (m) -> m.get('_pending_id') isnt model.get('_pending_id'))
  key = model.getParentKey()
  ctx._offlineCollections[key] = _.filter(ctx._offlineCollections[key], (m) -> m.get('_pending_id') isnt model.get('_pending_id'))



###
  ------- Public methods -------
###

defaultOptions =
  forceRefresh: no

defaultCacheOptions =
  ttl               : 0 # seconds
  enabled           : no
  allowExpiredCache : yes


module.exports = class Mnemosyne

  _requestManager: null

  # Contains all models to append to collections
  _offlineCollections: {}

  # Contains all offlines models
  _offlineModels: {}

  _context = null
  constructor: ->
    @_requestManager = new RequestManager
      onSynced    : (model) ->
        if Utils.isModel(model)
          # DEBUG
          if model.isNew()
            console.warn "Model has not been updated yet !"

          #Add model to parent collection cache
          updateParentCache(_context, model)

          # Remove the model from offline models and collection
          removePendingModel(_context, model)
        model.finishSync()
        console.log 'synced'

      onPending   : (model) ->
        # Add the model to offline models
        _context._offlineModels = Utils.addWithoutDuplicates(_context._offlineModels, model)

        #Add the model to offline parent collection
        if model.getParentKey()?
          _context._offlineCollections[model.getParentKey()] = Utils.addWithoutDuplicates(_context._offlineCollections[model.getParentKey()], model)
        model.pendingSync()
        console.log 'pending'


      onCancelled : (model) ->
        if Utils.isModel(model)
          # DEBUG
          if model.isNew()
            console.warn "Model has not been updated yet !"

            # Remove the model from offline models and collection
            removePendingModel(_context, model)
          else
            console.log "TODO rollback"
        model.unsync()
        console.log 'unsynced'


    _context = @


  cacheWrite : (model) ->
    model.cache = _.defaults(model.cache or {}, defaultCacheOptions)
    updateCache(_context, model)


  cacheRead  : (key) ->
    deferred = $.Deferred()
    Utils.store.getItem(key)
    .done (item) ->
      deferred.resolve(item.value)
    .fail -> deferred.reject()

    return deferred


  cacheRemove: (key) ->
    return Utils.store.removeItem(key)


  cacheClear: ->
    return Utils.store.clear();


  getPendingRequests: ->
    _context._requestManager.getPendingRequests()


  retrySync: ->
    _context._requestManager.retrySync()


  cancelPendingRequest: (key) ->
    request = @pendingRequests.retrieveItem(key)
    return if not request?
    cancelRequest(@, request)


  clear: ->
    _context._offlineCollections = {}
    _context._offlineModels = []
    _context._requestManager.clear()


  ###
    Overrides the Backbone.sync method
  ###
  sync: (method, model, options = {}) ->
    # #console.log "[.] sync #{method}, #{model?}, #{model.cache.enabled}"
    options     = _.defaults(options, defaultOptions)
    model.cache = _.defaults(model.cache or {}, defaultCacheOptions)
    deferred    = $.Deferred()

    console.log "\n" + model.getKey()

    model.beginSync()
    switch method
      when 'read'
        read(_context, model, options)
        .done (value) ->
          #Let's see if there are some pending models to prepend to the collection
          if Utils.isCollection(model)
            collection = model
            models = _context._offlineCollections[collection.getKey()]
            if models?
              for offlineModel in models
                value.unshift(offlineModel.attributes)
          options.success?(value, 'success', null)
          deferred.resolve(value)
        .fail ->
          if Utils.isCollection(model)
            value = []
            collection = model
            models = _context._offlineCollections[collection.getKey()]
            if models?
              for offlineModel in models
                value.unshift(offlineModel.attributes)
            options.success?(value, 'success', null)
          deferred.reject.apply this, arguments
      when 'delete'
        model.on 'synced', ->
          # Remove the model from offline models and collection
          removePendingModel(_context, model)
          removeFromParentCache(_context, model)

        serverWrite(_context, method, model, options, deferred)
      else
        serverWrite(_context, method, model, options, deferred)

    return deferred

  @SyncMachine = SyncMachine


class MnemosyneModel

  getPendingId: ->
    return @get('_pending_id')

  sync: -> Mnemosyne.prototype.sync.apply this, arguments

class MnemosyneCollection
  sync: -> Mnemosyne.prototype.sync.apply this, arguments


_.extend Backbone.Model.prototype, SyncMachine
_.extend Backbone.Model.prototype, MnemosyneModel.prototype

_.extend Backbone.Collection.prototype, SyncMachine
_.extend Backbone.Collection.prototype, MnemosyneCollection.prototype
