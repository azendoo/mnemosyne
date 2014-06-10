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
  * request db persistence
  * Discuss about the status 4XX and 5XX
###


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
  request.model.unsync()


pushRequest = (ctx, request) ->
  deferred = $.Deferred()
  return deferred.reject() if not request?
  ctx.pendingRequests.addTail(request.key, request)

  method = getMethod(request);
  options = request.methods[method]

  if (not isConnected())
    console.log '[pushRequest] -- not connected. Push request in queue'
    request.model.pendingSync()
    if (not ctx.timeout?)
      consume(ctx)
    return deferred.resolve(request.model.attributes)

  console.log '[pushRequest] -- Try sync'

  Backbone.sync(method, request.model, options)
  .done ->
    console.log '[pushRequest] -- Sync success'
    # TODO use localforage

    localStorage.removeItem(request.key)
    ctx.pendingRequests.retrieveItem(request.key)
    deferred.resolve.apply(this, arguments)
    request.model.finishSync()
  .fail (error) ->
    console.log '[pushRequest] -- Sync failed'

    deferred.resolve(request.model.attributes)
    request.model.pendingSync()
    if (not ctx.timeout?)
      consume(ctx)

  return deferred


consume = (ctx) ->

  request = ctx.pendingRequests.getHead()
  if (not request?)
    console.log '[consume] -- done! 0 pending'
    resetTimer(ctx)
    return

  if (not isConnected())
    if ctx.interval < MAX_INTERVAL
      ctx.interval = ctx.interval * 2
    console.log '[consume] -- not connected, next try in ', ctx.interval
    return ctx.timeout  = setTimeout( (-> consume(ctx) ), ctx.interval)

  method  = getMethod(request);
  options = request.methods[method]

  console.log '[consume] -- try sync ', method

  Backbone.sync(method, request.model, options)
  .done ->
    console.log '[consume] --Sync success'

    ctx.pendingRequests.retrieveHead()
    ctx.interval = MIN_INTERVAL
    request.model.finishSync()
  .fail (error) ->
    console.log '[consume] -- Sync failed', error

    status = error.readyState
    switch status
      when 4, 5
        ctx.pendingRequests.retrieveHead()
        request.model.unsync()

      else ctx.pendingRequests.rotate()

    if ctx.interval < MAX_INTERVAL
      ctx.interval = ctx.interval * 2
  .always ->
    ctx.timeout  = setTimeout( (-> consume(ctx) ), ctx.interval)


# TODO manage connection on mobile devices
isConnected= ->
  return window.navigator.onLine

# Optimize request avoiding to send some useless data
# TODO add 'patch':  'PATCH',

smartRequest= (ctx, request) ->
  # console.log "--smart--", request.methods
  if request.methods['delete']? and request.methods['create']?
    ctx.pendingRequests.retrieveItem(request.key)
    return null
  if (request.methods['create']? or request.methods['delete']?) and request.methods['update']?
    delete request.methods['update']
    return request

  return request

getMethod= (request) ->
  if request.methods['create']
    return 'create'

  else if request.methods['update']
    return 'udpate'

  else if request.methods['delete']
    return 'delete'

  else
    console.error "No method found !", request

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

  constructor: ->
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

    model.beginSync()

    return pushRequest(@, request)
