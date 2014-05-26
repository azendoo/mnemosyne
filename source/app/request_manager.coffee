MagicQueue = require "../app/magic_queue"
localforage = require "localforage"
Backbone    = require "backbone"

###
  TODO
  * limit the number of pending requests ?
  * manage the database limit
  * documentation
  * set models status according to events, and update the cache
  * manage connectivity
  * request db persistence
  * set default values for MAX et MIN interval
  * manage concurrent call to consume
###

defaultEventMap =
  'syncing'     : 'syncing'
  'pending'     : 'pending'
  'synced'      : 'synced'
  'unsynced'    : 'unsynced'

MAX_INTERVAL= 64000 # 64 seconds
MIN_INTERVAL= 250   # 250ms

###
  ------- Private methods -------
###

resetTimer = (ctx) ->
  clearTimeout(ctx.timeout)
  ctx.timeout = null
  ctx.interval = MIN_INTERVAL


cancelRequest = (ctx, request) ->
  request.model.trigger(ctx.eventMap['unsynced'])


pushRequest = (ctx, request) ->
  return if not request?

  ctx.pendingRequests.addHead(request.key, request)
  resetTimer(ctx)

  return consume(ctx)


consume = (ctx) ->
  deferred = $.Deferred()

  request = ctx.pendingRequests.retrieveHead()
  return deferred.reject() if not request?
  Backbone.sync(request.method, request.model, request.options)
  .done ->
    request.model.trigger(ctx.eventMap['synced'])
    ctx.interval = MIN_INTERVAL
  .fail (error) ->
    ctx.pendingRequests.addTail(request.key, request)
    request.model.trigger(ctx.eventMap['pending'])
    if ctx.interval < MAX_INTERVAL
      ctx.interval = ctx.interval * 2
  .always ->
    ctx.timeout  = setTimeout( (-> consume(ctx) ), ctx.interval)
    deferred.resolve.apply(this, arguments)

  return deferred



###
  ------- Public methods -------
###

module.exports = class RequestManager


  ###
    request:
      method
      model
      options
      key
  ###

  constructor: (eventMap = {}) ->
    @eventMap = _.extend(defaultEventMap, eventMap)
    @pendingRequests = new MagicQueue()
    resetTimer(@)


  clear: ->
    @pendingRequests.getQueue().map((request) => cancelRequest(@, request))
    resetTimer(@)
    @pendingRequests.clear()


  getPendingRequests: ->
    return @pendingRequests.getQueue()


  retrySync: ->
    resetTimer(@)
    consume(@)


  cancelPendingRequest: (key) ->
    request = @pendingRequests.retrieveItem(key)
    return if not request?
    cancelRequest(@, request)


  safeSync: (method, model, options = {}) ->
    request = {}
    request.method  = method
    request.model   = model
    request.options = options
    request.key     = model.getKey()

    return pushRequest(@, request)
