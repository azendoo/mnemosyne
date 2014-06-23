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

  if typeof model.getKey isnt 'function' or not model.cache.enabled
    console.log "Cache forbidden"
    return serverRead(ctx, model, options, null, deferred)

  console.log "Try loading value from cache"
  Utils.store.getItem(model.getKey())
  .done (value) ->
    console.log "Succeed to read from cache"
    cacheRead(ctx, model, options, value, deferred)
  .fail ->
    console.log "Fail to read from cache"
    serverRead(ctx, model, options, null, deferred)

  return deferred


cacheRead = (ctx, model, options, value, deferred) ->
  # -- Cache expired

  # DEBUG
  if model instanceof Backbone.Collection
    _.map(model.parse(value.data), (element) -> console.warn('New model read in cache !') if not element.id?)

  if options.forceRefresh or value.expirationDate < new Date().getTime()
    console.log "-- cache expired"
    serverRead(ctx, model, options, value.data, deferred)

  # -- Cache valid
  else
    console.log "-- cache valid"
    deferred.resolve(value.data)


serverRead = (ctx, model, options, fallbackItem, deferred) ->
  console.log "Sync from server"

  # Return cache data and update silently the cache
  if fallbackItem? and model.cache.allowExpiredCache and not options.forceRefresh
    deferred.resolve(fallbackItem)
    options.silent = true

  if not Utils.isConnected()
    console.log 'No connection'
    if model instanceof Backbone.Collection
      return deferred.resolve([])
    else
      return deferred.reject()

  Backbone.sync('read', model, options)
  .done (value)->
    console.log "Succeed sync from server"
    updateCache(ctx, model, value)
    .always ->
      if deferred.state() isnt "resolved"
        deferred.resolve(value)
  .fail (error) ->
    console.log "Fail sync from server"
    if deferred.state() isnt "resolved"
      deferred.reject.apply(this, arguments)


removeFromParentCache = (ctx, model) ->
  deferred = $.Deferred()

  # DEBUG
  if model instanceof Backbone.Collection
    console.warn 'removeParentFromCache: collection as argument !'
    return deferred.resolve()

  # DEBUG
  if not model.get('id')?
    console.warn 'removeParentFromCache: model is new !'
    return deferred.resolve()

  parentKeys = model.getParentKeys()

  deferredArray = _.map(parentKeys, (parentKey)->
    _deferred = $.Deferred()
    Utils.store.getItem(parentKey)
    .done (value) ->
      models = value.data
      models = _.filter(models, (m) -> m.id isnt model.get('id'))
      Utils.store.setItem(parentKey, {"data" : models, "expirationDate" : value.expirationDate})
      .always ->
        _deferred.resolve()
    .fail ->
      # The model doesn't exist
      _deferred.resolve()
    )
  $.when.apply($, deferredArray).then(
    -> deferred.resolve()
    -> deferred.reject())

  return deferred


removeFromCache = (ctx, model) ->
  deferred = $.Deferred()

  Utils.store.removeItem(model).always ->
    removeFromParentCache(ctx, model).always -> deferred.resolve()

  return deferred


updateParentCache = (ctx, model) ->
  deferred = $.Deferred()

  # return deferred.resolve()  if model instanceof Backbone.Collection
  return deferred.resolve()  if model instanceof Backbone.Collection or typeof model.getParentKeys isnt 'function'
  parentKeys = model.getParentKeys()

  deferredArray = _.map(parentKeys, (parentKey)->
    _deferred = $.Deferred()
    console.log "Updating parent cache [#{parentKey}]"
    if not model.get('id')?
      # just add to unsynced models and collections
      ctx._offlineCollections[parentKey] ?= []
      ctx._offlineCollections[parentKey] = Utils.addWithoutDuplicates(ctx._offlineCollections[parentKey], model)
      console.debug 'model set'
      _deferred.resolve()
    else
      Utils.store.getItem(parentKey)
      .done (value) ->
        models = value.data
        parentModel = _.findWhere(models, "id": model.get('id'))
        if parentModel?
          _.extend(parentModel, model.attributes)
        else
          models.unshift(model.attributes)
        Utils.store.setItem(parentKey, {"data" : models, "expirationDate": 0})
        .always ->
          _deferred.resolve()
      .fail ->
        # Create the collection in cache
        Utils.store.setItem(parentKey, {"data" : [model], "expirationDate": 0})
        .done ->
          _deferred.resolve()
        .fail ->
          _deferred.reject()

    return _deferred

    )
  $.when(deferredArray).then(
    -> deferred.resolve()
    -> deferred.reject())

  return deferred


updateCache = (ctx, model, data) ->

  deferred = $.Deferred()
  return deferred.resolve() if not model.cache.enabled

  expiredDate = (new Date()).getTime() + model.cache.ttl * 1000
  console.log "Try to write cache -- expires at #{expiredDate}"

  if model instanceof Backbone.Model and not model.get('id')?
    ctx._offlineModels = Utils.addWithoutDuplicates(ctx._offlineModels, model)
    deferred.resolve()
  else
    if model instanceof Backbone.Model
      data ?= model.attributes

    else if model instanceof Backbone.Collection
      data ?= _.map(model.models, (m) -> m.attributes)
      # DEBUG
      _.map(model.parse(data), (element) ->
        if not element.id?
          console.warn('New model in cache !')
          console.warn('\tmodel ',model)
          console.warn('\tdata ',data)
          console.warn('\telement ',element)
          )

    else
      console.warn "Wrong instance for ", model
      return deferred.reject()

    Utils.store.setItem(model.getKey(), {"data" : data, "expirationDate": expiredDate})
    .done ->
        console.log "Succeed cache write"
        updateParentCache(ctx, model)
        .always ->
          deferred.resolve()
    .fail ->
        console.log "fail cache write"
        deferred.reject()


  return deferred


serverWrite = (ctx, method, model, options, deferred ) ->
  console.log "serverWrite"

  updateCache(ctx, model)
  .done ->
    ctx._requestManager.sync(method, model, options)
    .done (value)->
      deferred.resolve.apply this, arguments
    .fail ->
      deferred.reject.apply this, arguments
  .fail ->
    console.log "fail"
    model.unsync()
    deferred.reject.apply this, arguments
    Utils.store.removeItem(model.getKey())


removePendingModel = (ctx, model) ->
  return if not model instanceof Backbone.Model
  ctx._offlineModels = _.filter(ctx._offlineModels, (m) -> m.get('_pending_id') isnt model.get('_pending_id'))
  parentKeys = model.getParentKeys()
  parentKeys ?= []
  for key in parentKeys
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
  _offlineModels: []

  _context = null
  constructor: ->
    @_requestManager = new RequestManager
      onSynced  : (model, value, method) ->
        if method isnt 'delete'
          updateCache(_context, model, value)

        # Remove the model from offline models and collection
        removePendingModel(_context, model)
        model.finishSync()
        console.log 'synced'

      onPending   : (model) ->
        # Add the model to offline models
        if not model.get('id')?
          _context._offlineModels = Utils.addWithoutDuplicates(_context._offlineModels, model)

          #Add the model to offline parent collection
          if typeof model.getParentKeys is 'function'
            parentKeys = model.getParentKeys()
            parentKeys ?= []
            for parentKey in parentKeys
              _context._offlineCollections[parentKey] = Utils.addWithoutDuplicates(_context._offlineCollections[parentKey], model)
        model.pendingSync()
        console.log 'pending'


      onCancelled : (model) ->
        if model instanceof Backbone.Model
          # DEBUG
          if not model.get('id')?
            console.warn "Model has not been updated yet !"

            # Remove the model from offline models and collection
            removePendingModel(_context, model)
          else
            console.log "TODO rollback"
        model.unsync()
        console.log 'unsynced'


    _context = @


  cacheWrite : (key, value) ->
    if key instanceof Backbone.Model or key instanceof Backbone.Collection
      model = key
      model.cache = _.defaults(model.cache or {}, defaultCacheOptions)
      return updateCache(_context, model)
    return Utils.store.setItem(key, value)


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


  cacheRemove: (key) ->
    if key instanceof Backbone.Model or key instanceof Backbone.Collection
      model = key
      return removeFromCache(_context, model)
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
        .done (data) ->
          data ?= []
          #Let's see if there are some pending models to prepend to the collection
          if model instanceof Backbone.Collection
            collection = model
            models = _context._offlineCollections[collection.getKey()]
            if models?
              for offlineModel in models
                data.unshift(offlineModel.attributes)
          options.success?(data, 'success', null)
          deferred.resolve(data)
          model.finishSync()
        .fail ->
          if model instanceof Backbone.Collection
            data = []
            collection = model
            models = _context._offlineCollections[collection.getKey()]
            if models?
              for offlineModel in models
                data.unshift(offlineModel.attributes)
              options.success?(data, 'success', null)
              deferred.resolve(data)
              model.finishSync()
              return

          deferred.reject.apply this, arguments
          model.unsync()
      when 'delete'
        removePendingModel(_context, model)
        removeFromCache(_context, model)
        _context._requestManager.sync(method, model, options)
        .done (data)->
          deferred.resolve.apply this, arguments
        .fail ->
          deferred.reject.apply this, arguments
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
