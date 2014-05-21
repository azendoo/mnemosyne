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
  * use event map
  * set default values for MAX et MIN interval
  * manage concurrent call to consume
###

store = localforage
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

cancelRequest = (ctx, request) ->
  request.model.trigger(ctx.eventMap['unsynced'])
  store.removeItem(request.key)


pushRequest = (ctx, request) ->
  return if not request?

  ctx.pendingRequests.addHead(request)
  clearTimeout(ctx.timeout)
  ctx.timeout = null
  ctx.interval = MIN_INTERVAL

  return consume(ctx)


consume = (ctx) ->
  deferred = $.Deferred()

  req = ctx.pendingRequests.retrieveHead()
  return deferred.reject() if not req?

  Backbone.sync(req.method, req.model, req.options)
  .done ->
    request.model.trigger('synced')
    deferred.resolve.apply(this, arguments)
    ctx.interval = MIN_INTERVAL
  .fail ->
    ctx.pendingRequests.addTail(req.key, request)
    request.model.trigger('pending')
    if ctx.interval < MAX_INTERVAL
      ctx.interval = ctx.interval * 2
    deferred.reject.apply(this, arguments)
  .always ->
    ctx.timeout  = setTimeout( (-> consume(ctx) ), ctx.interval)

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
    @interval = MIN_INTERVAL

  clear: ->
    @pendingRequests.getQueue().map((request) => cancelRequest(@, request))
    @interval = MIN_INTERVAL
    clearTimeout(@timeout)
    @timeout = null
    @pendingRequests.clear()


  getPendingRequests: ->
    return @pendingRequests.getQueue()


  retrySync: ->
    return if @pendingRequests.isEmpty()
    @interval = MIN_INTERVAL
    consume(@)


  cancelPendingRequest: (key) ->
    request = @pendingRequests.remove(key)
    return if not request?
    cancelRequest(@, request)


  safeSync: (method, model, options = {}) ->
    request = {}
    request.method  = method
    request.model   = model
    request.options = options
    request.key     = model.getKey()

    return pushRequest(@, request)
