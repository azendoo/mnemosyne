RequestManager = require "../app/request_manager"
SyncMachine    = require "../app/sync_machine"
# Backbone = require "backbone"
# _        = require "underscore"


###
  TODO
  * set db infos
  * documentation
###


###
  ------- Private methods -------
###
store = {}
store.getItem = (key) ->
  value = localStorage.getItem(key)
  if value?
    return $.Deferred().resolve(JSON.parse(value))
  return $.Deferred().reject()


store.setItem = (key, value) ->
  localStorage.setItem(key, JSON.stringify(value))
  return $.Deferred().resolve()


store.clear = ->
  localStorage.clear()
  return $.Deferred().resolve()


read = (ctx, model, options, deferred) ->

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


cacheRead = (ctx, model, options, item, deferred) ->
  # -- Cache expired

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
    options.success?(fallbackItem.value, 'success', null)
    deferred.resolve(fallbackItem.value)
    model.finishSync()
    options.silent = true

  Backbone.sync('read', model, options)
  .done ->
    console.log "Succeed sync from server"
    model.attributes = arguments[0]
    updateCache(model)
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

  store.getItem(key)
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


updateParentCache = (model) ->
  deferred = $.Deferred()

  # return deferred.resolve()  if model instanceof Backbone.Collection
  return deferred.resolve()  if model.models? or not model.getParentKey?()
  console.log "Updating parent cache"
  parentKey = model.getParentKey()
  load(parentKey)
  .done (item) ->
    models = item.value
    if model.isNew()
      # Implements 'equals' method for each model ?
      console.warn "#{model.prototype.name} should implements 'equals' method"
    else
      parentModel = _.findWhere(models, "id": model.get('id'))
      if parentModel?
        _.extend(parentModel, model.attributes)
      else
        models.unshift(model.attributes)
    store.setItem(parentKey, {"value" : models, "expirationDate": item.expiredDate})
    .always ->
      deferred.resolve()
  .fail -> deferred.reject()

  return deferred

updateCache = (model) ->
  deferred = $.Deferred()

  expiredDate = (new Date()).getTime() + model.cache.ttl * 1000
  console.log "Try to write cache -- expires at #{expiredDate}"
  # store.setItem(model.getKey(), {'value' : model, 'expirationDate': expiredDate})

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

  store.setItem(model.getKey(), {"value" : value, "expirationDate": expiredDate})
  .then(
    ->
      console.log "Succeed cache write"
      updateParentCache(model)
      .always ->
        deferred.resolve.apply(this, arguments)
    ->
      console.log "fail cache write"
      deferred.reject.apply(this, arguments)
  )

  return deferred


serverWrite = (ctx, method, model, options, deferred ) ->
  console.log "serverWrite"

  updateCache(model)
  .done ->
    # register event to trigger the cache update
    model.off('mnemosyne:writeCache')
    model.on('mnemosyne:writeCache', -> updateCache(model))
    ctx.safeSync(method, model, options)
    .done ->
      deferred.resolve.apply this, arguments
    .fail ->
      deferred.reject.apply this, arguments
  .fail ->
    console.log "fail"
    deferred.reject.apply this, arguments
    model.unsync()
    store.removeItem(model.getKey())


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



###
  ------- Public methods -------
###

defaultOptions =
  forceRefresh: no

defaultCacheOptions =
  ttl               : 600 # 10min
  enabled           : no
  allowExpiredCache : yes


module.exports = class Mnemosyne extends RequestManager

  _context = null
  constructor: ->
    super
    _context = @


  cacheWrite : (model) ->
    model.cache = _.defaults(model.cache or {}, defaultCacheOptions)
    updateCache(model)


  cacheRead  : (key) ->
    deferred = $.Deferred()
    store.getItem(key)
    .done (item) ->
      deferred.resolve(item.value)
    .fail -> deferred.reject()

    return deferred


  cacheRemove: (key) ->
    return store.removeItem(key)


  clearCache: ->
    return store.clear();

  ###
    Overrides the Backbone.sync method
  ###
  sync: (method, model, options = {}) ->
    # #console.log "[.] sync #{method}, #{model?}, #{model.cache.enabled}"
    options = _.defaults(options, defaultOptions)
    model.cache = _.defaults(model.cache or {}, defaultCacheOptions)
    deferred = $.Deferred()

    console.log "\n" + model.getKey()

    model.beginSync()
    switch method
      when 'read'
        read(_context, model, options, deferred)
      else
        serverWrite(_context, method, model, options, deferred)

    return deferred

  @SyncMachine = SyncMachine



mnemosyne = new Mnemosyne()
Backbone.Model = class Model extends Backbone.Model
  initialize: ->
    super
    _.extend this, SyncMachine

  sync: -> mnemosyne.sync.apply this, arguments
  destroy: ->
    if @isNew()
      @cancelPendingRequest(@getKey())
    else
      super

Backbone.Collection = class Collection extends Backbone.Collection
  initialize: ->
    super
    _.extend this, SyncMachine

  sync: -> mnemosyne.sync.apply this, arguments
  destroy: ->
    if @isNew()
      @cancelPendingRequest(@getKey())
    else
      super

Mnemosyne.Model = Backbone.Model
Mnemosyne.Collection = Backbone.Collection
