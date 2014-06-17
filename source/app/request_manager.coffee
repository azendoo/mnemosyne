MagicQueue = require "../app/magic_queue"
Utils      = require "../app/utils"

# localforage = require "localforage"
# Backbone = require "backbone"
# _        = require "underscore"


MAX_INTERVAL= 64000 # 64 seconds
MIN_INTERVAL= 250   # 250ms


resetTimer = (ctx) ->
  clearTimeout(ctx.timeout)
  ctx.timeout  = null
  ctx.interval = MIN_INTERVAL


pushRequest = (ctx, request) ->
  deferred = $.Deferred()
  return deferred.reject() if not request?
  ctx.pendingRequests.addTail(request.key, request)

  method = getMethod(request)
  options = request.methods[method]

  # DEBUG
  pendingId = request.model.get('_pending_id')
  if pendingId?
    console.warn "[pushRequest] -- pendingId already set!!"

  if (not Utils.isConnected())
    console.log '[pushRequest] -- not connected. Push request in queue'
    ctx.callbacks.onPending(request.model)
    if (not ctx.timeout?)
      consume(ctx)
    return deferred.resolve(request.model.attributes)

  console.log '[pushRequest] -- Try sync'

  Backbone.sync(method, request.model, options)
  .done ->
    console.log '[pushRequest] -- Sync success'

    removeMethod(request, method)
    if isRequestEmpty(request)
      ctx.pendingRequests.retrieveItem(request.key)
      deferred.resolve.apply(this, arguments)
      ctx.callbacks.onSynced(request.model)

  .fail (error) ->
    console.log '[pushRequest] -- Sync failed'

    # Attach a pending id
    request.model.attributes._pending_id = new Date().getTime()
    deferred.resolve(request.model.attributes)
    ctx.callbacks.onPending(request.model)
    if (not ctx.timeout?)
      consume(ctx)

  return deferred


consume = (ctx) ->

  request = ctx.pendingRequests.getHead()
  if (not request?)
    console.log '[consume] -- done! 0 pending'
    resetTimer(ctx)
    return

  if (not Utils.isConnected())
    if ctx.interval < MAX_INTERVAL
      ctx.interval = ctx.interval * 2
    console.log '[consume] -- not connected, next try in ', ctx.interval
    return ctx.timeout  = setTimeout( (-> consume(ctx) ), ctx.interval)

  method  = getMethod(request);
  options = request.methods[method]
  pendingId = request.model.get('_pending_id')

  # Clean attributes before sync
  delete request.model.attributes._pending_id

  console.log '[consume] -- try sync ', method

  Backbone.sync(method, request.model, options)
  .done ->
    console.log '[consume] -- Sync success'

    removeMethod(request, method)
    if isRequestEmpty(request)
      ctx.pendingRequests.retrieveHead()
      deferred.resolve.apply(this, arguments)
      ctx.callbacks.onSynced(request.model)

    ctx.interval = MIN_INTERVAL

  .fail (error) ->
    console.log '[consume] -- Sync failed', error

    status = error.readyState
    switch status
      when 4, 5
        ctx.pendingRequests.retrieveHead()
        ctx.callbacks.onCancelled(request.model)

      else
        request.model.attributes._pending_id = pendingId
        ctx.pendingRequests.rotate()

    if ctx.interval < MAX_INTERVAL
      ctx.interval = ctx.interval * 2
  .always ->
    ctx.timeout  = setTimeout( (-> consume(ctx) ), ctx.interval)


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


removeMethod = (request, method) ->
  delete request.methods[method]


isRequestEmpty = (request) ->
  return Object.keys(request.methods).length is 0


getMethod= (request) ->
  if request.methods['create']
    return 'create'

  else if request.methods['update']
    return 'update'

  else if request.methods['delete']
    return 'delete'

  else
    console.error "No method found !", request


defaultCallbacks =
  onSynced    : ->
  onPending   : ->
  onCancelled : ->

module.exports = class RequestManager

  constructor: (@callbacks={}) ->
    _.defaults(@callbacks, defaultCallbacks)
    @pendingRequests = new MagicQueue()
    resetTimer(@)


  clear: ->
    @pendingRequests.getQueue().map((request) => @callbacks.onCancelled(request.model))
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
    @callbacks.onCancelled(request.model)


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
