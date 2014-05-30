MagicQueue = require "../app/magic_queue"
# localforage = require "localforage"
# Backbone = require "backbone"
# _        = require "underscore"

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

  If there is a delete on a create, cancel the request. and valid the delete
  If there is a delete on an update, only send the delete the delete

  Manage status code errors to cancel the request

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
  deferred = $.Deferred()
  return deferred.reject() if not request?

  method = getMethod(request);
  options = request.methods[method]

  ctx.pendingRequests.addTail(request.key, request)
  Backbone.sync(method, request.model, options)
  .done ->
    ctx.pendingRequests.retrieveItem(request.key)
    deferred.resolve.apply(this, arguments)
    request.model.trigger(ctx.eventMap['synced'])
  .fail (error) ->
    deferred.resolve(request.model.attributes)
    request.model.trigger(ctx.eventMap['pending'])
    if (not ctx.timeout?)
      consume(ctx)

  return deferred


consume = (ctx) ->

  request = ctx.pendingRequests.getHead()
  # console.log ctx.pendingRequests.orderedKeys
  if (not request?)
    resetTimer(ctx)
    return

  method = getMethod(request);
  options = request.methods[method]

  Backbone.sync(method, request.model, options)
  .done ->
    ctx.pendingRequests.retrieveHead()
    ctx.interval = MIN_INTERVAL
    request.model.trigger(ctx.eventMap['synced'])
  .fail (error) ->
    ctx.pendingRequests.rotate()
    if ctx.interval < MAX_INTERVAL
      ctx.interval = ctx.interval * 2
    request.model.trigger(ctx.eventMap['pending'])
  .always ->
    ctx.timeout  = setTimeout( (-> consume(ctx) ), ctx.interval)


# TODO manage connection on mobile devices
isConnected= ->
  return window.navigator.onLine

# Optimize request avoiding to send some useless data
smartRequest= (ctx, request) ->
  # console.log "--smart--", request.methods
  if request.methods['destroy']? and request.methods['create']?
    ctx.pendingRequests.retrieveItem(request.key)
    return null
  if (request.methods['create']? or request.methods['destroy']?) and request.methods['update']?
    delete request.methods['update']
    return request

  return request

getMethod= (request) ->
  if request.methods['create']
    return 'create'

  else if request.methods['update']
    return 'udpate'

  else if request.methods['destroy']
    return 'destroy'

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
    # Is there allready some pending request for this model?
    request = @pendingRequests.getItem(model.getKey())
    request ?= {}
    request.methods  ?= {}

    request.model   = model
    request.methods[method] = options
    request.key     = model.getKey()

    request = smartRequest(@, request)

    return pushRequest(@, request)
