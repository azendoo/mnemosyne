RequestManager = require "./request_manager"

###
  TODO
  * set db infos
  * extend public methods of RequestManager
  * documentation
###


###
  ------- Private methods -------
###
store = localforage

defaultOptions =
  forceRefresh: no
  invalidCache: no
  ttl  : 600 * 1000 #10min


read = (ctx, model, options, deferred) ->
  load(ctx, key)
  .done (item) ->
    cacheRead(ctx, model, options, item, deferred)
  .fail ->
    serverRead(ctx, model, options, null, deferred)


cacheRead = (ctx, model, options, item, deferred) ->
  # -- Cache expired
  if options.forceRefresh or item.expirationDate < (new Date).getTime()
    serverRead(ctx, model, options, item, deferred)

  # -- Cache valid
  else
    options.success?(item.value, 'success', null)
    model.trigger(ctx.eventMap['synced'])
    deferred?.resolve(item.value)

    # -- silent server update
    if model.constants.silent
      options.silent = true
      serverRead(ctx, model, options, item, null)


serverRead = (ctx, model, options, fallbackItem, deferred) ->
  Backbone.sync(method, model, options)
  .done ->
    cacheWrite(ctx, model)
    model.trigger(ctx.eventMap['synced'])
    deferred.resolve.apply(this, arguments)
  .fail =>
    if value? and model.constants.allowExpiredCache
      model.trigger(ctx.eventMap['cacheSynced'])
    else
    model.trigger(ctx.eventMap['unsynced'])
    deferred.reject.apply(this, arguments)


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
    deferred.reject()

  ttl         = model.constants.ttl or @_DEFAULT_EXPIRATION_TIME
  expiredDate = (new Date()).getTime() + ttl * 1000

  store.setItem(key, {'value' : value, 'expirationDate': expiredDate})
  .then(
    ->
      deferred.resolve.apply(this, arguments)
    ->
      deferred.reject.apply(this, arguments)
  )

  return deferred


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
wrapPromise: (promise) ->
  deferred = $.Deferred()
  promise.then(
    ->
      deferred.resolve.apply(this, arguments)
    ->
      deferred.reject.apply(this, arguments)
    )
  return deferred



###
  ------- Public methods -------
###

module.exports = class Mnemosyne extends RequestManager

  ###
    Clear the cache. Cancel all pending requests.
  ###
  clear: ->
    super
    return _wrapPromise @_store.clear.apply(this, arguments)


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
    options = _.extend(defaultOptions, options)
    deferred = $.Deferred()

    model.trigger(@eventMap['syncing'])
    switch method
      when 'read'
        read(@, model, options, deferred)
      else
        serverSync(@, method, model, options, null, deferred)

    return deferred
