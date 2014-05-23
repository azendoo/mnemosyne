RequestManager = require "../app/request_manager"
localforage    = require "localforage"

###
  TODO
  * set db infos
  * documentation
  * manage default options
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


defaultOptions =
  forceRefresh: no
  invalidCache: no

defaultConstants =
  ttl : 600 * 1000 # 10min
  cache : true
  allowExpiredCache :true




read = (ctx, model, options, deferred) ->

  if not model.getKey?()? or not model.constants.cache
    console.log "Cache forbidden"
    return serverRead(ctx, model, options, null, deferred)

  console.log "Try loading value from cache"
  load(ctx, model.getKey())
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
    model.trigger(ctx.eventMap['synced'])


serverRead = (ctx, model, options, fallbackItem, deferred) ->
  console.log "Sync from server"

  Backbone.sync('read', model, options)
  .done ->
    console.log "Succeed sync from server"
    cacheWrite(ctx, model)
    .always ->
      model.trigger(ctx.eventMap['synced'])
      deferred.resolve.apply(this, arguments)
  .fail (error) ->
    console.log "Fail sync from server"
    if fallbackItem? and model.constants.allowExpiredCache
      options.success?(fallbackItem.value, 'success', null)
      deferred?.resolve(fallbackItem.value)
      model.trigger(ctx.eventMap['synced'])
    else
      deferred.reject.apply(this, arguments)
      model.trigger(ctx.eventMap['unsynced'])


load = (ctx, key) ->
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


cacheWrite = (ctx, model) ->
  deferred = $.Deferred()

  if not model.getKey?()? or not model.constants.cache
    return deferred.reject()

  expiredDate = (new Date()).getTime() + model.constants.ttl
  console.log "Try to write cache"
  # store.setItem(model.getKey(), {'value' : model, 'expirationDate': expiredDate})
  store.setItem(model.getKey(), {value : model, expirationDate: expiredDate})
  .then(
    ->
      console.log "Succeed cache write"
      deferred.resolve.apply(this, arguments)
    ->
      console.log "fail cache write"
      deferred.reject.apply(this, arguments)
  )

  return deferred


serverWrite = (ctx, method, model, options, deferred ) ->
  ctx.safeSync(method, model, options)
  .done ->
    deferred.resolve.apply this, arguments
  .fail ->
    deferred.reject.apply this, arguments


###
  Set the expiration date to 0
  TODO put this method public ?
###
invalidCache: (key, deferred) ->
  deferred ?= $.Deferred()
  if not key?
    return deferred.reject()

  set_item_failure = ->
    deferred.reject()

  set_item_success = ->
    if model.collection?
      invalidCache(model.collection.getKey?(), deferred)
    else
      deferred.resolve()

  store.getItem(key).then(
    (item) =>
      if not item?
        return deferred.resolve()
      store.setItem(key, {value: item.value, expiration_date: 0})
      .then(set_item_success, set_item_failure)
    ->
      # Object not saved in cache
      deferred.resolve()
    )

  return deferred


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


module.exports = class Mnemosyne extends RequestManager

  _context = null
  constructor: ->
    super
    _context = @

  cacheWrite : (model) ->
    model.constants = _.defaults(model.constants or {}, defaultConstants)
    cacheWrite(_context, model)

  cacheRead  : (key) ->
    deferred = $.Deferred()
    store.getItem(key)
    .done (item) ->
      deferred.resolve(item.value)
    .fail -> deferred.reject()

    return deferred


  ###
    Clear the cache. Cancel all pending requests.
  ###
  clear: ->
    super
    return store.clear()

  ###
    Overrides the Backbone.sync method
    var methodMap = {
    'create': 'POST',
    'update': 'PUT',
    'patch':  'PATCH',
    'delete': 'DELETE',
    'read':   'GET'
    };
  ###
  sync: (method, model, options = {}) ->
    # #console.log "[.] sync #{method}, #{model?}, #{model.constants.cache}"
    options = _.defaults(options, defaultOptions)
    model.constants = _.defaults(model.constants or {}, defaultConstants)
    deferred = $.Deferred()

    model.trigger(_context.eventMap['syncing'])
    switch method
      when 'read'
        read(_context, model, options, deferred)
      else
        serverWrite(_context, method, model, options, deferred)

    return deferred
