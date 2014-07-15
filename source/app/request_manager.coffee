MagicQueue = require "../app/magic_queue"
Utils      = require "../app/utils"

# localforage = require "localforage"
# Backbone = require "backbone"
# _        = require "underscore"

# TODO add 'patch' support

MAX_INTERVAL= 2000  # 2 seconds
MIN_INTERVAL= 125   # 125ms


# Helper to get the first action to perform
getMethod= (request) ->
  if request.methods['create']
    return 'create'
  else if request.methods['update']
    return 'update'
  else if request.methods['delete']
    return 'delete'
  else
    return null


# Helper to know if the request is empty, ie all actions have been performed
isRequestEmpty = (request) ->
  return Object.keys(request.methods).length is 0


# Store all needed information into a request object
initRequest = (ctx, method, model, options) ->
  # Is there allready some pending request for this model?
  request = ctx.pendingRequests.getItem(model.getKey()) or {"methods": {}}
  request.model   = model
  request.key     = model.getKey()
  request.url     = _.result(model, 'url')
  request.cache   = model.cache
  request.parentKeys      = model.getParentKeys()
  request.methods[method] = options
  pendingId = request.model.get('pending_id')
  request.model.set('pending_id', new Date().getTime()) if not pendingId?
  request.deferred ?= $.Deferred()
  return optimizeRequest(ctx, request)


clearTimer = (ctx) ->
  clearTimeout(ctx.timeout)
  ctx.timeout  = null
  ctx.interval = MIN_INTERVAL


enqueueRequest = (ctx, request) ->
  ctx.pendingRequests.addTail(request.key, request)
  if ctx.timeout is null
    consumeRequests(ctx)


consumeRequests = (ctx) ->
  request = ctx.pendingRequests.getHead()
  if not request?
    clearTimer(ctx)
    return

  ctx.timeout = setTimeout(
    ->
      sendRequest(ctx, request)
    ctx.interval)


onSendFail = (ctx, request, error) ->
  if ctx.interval < MAX_INTERVAL
    ctx.interval = ctx.interval * 2

  if request.cache.enabled
    status = error.readyState
    # Cancel the request when on 4xx and 5xx status code
    # switch status
    #   when 4, 5
    #     ctx.callbacks.onCancelled(request.model)
    #     console.log 'rejected -- ', status
    #     request.deferred?.reject()
    #   else
    enqueueRequest(ctx, request)
    ctx.callbacks.onPending(request.model)
    request.deferred?.resolve(request.model.attributes)
  else
    ctx.callbacks.onCancelled(request.model)
    request.deferred?.reject()

  consumeRequests(ctx)


onSendSuccess = (ctx, request, method, value) ->
  delete request.methods[method]
  ctx.interval = MIN_INTERVAL
  if isRequestEmpty(request)
    ctx.pendingRequests.retrieveItem(request.key)
    ctx.callbacks.onSynced(request.model, value, method)
  else
    enqueueRequest(ctx, ctx.pendingRequests.retrieveItem(request.key))
  consumeRequests(ctx)


# Try to send request, if fail, push in queue and try again later
sendRequest = (ctx, request) ->
  deferred = request.deferred

  if not Utils.isConnected()
    onSendFail(ctx, request, 0)
    return

  else
    # Save and clean pending id before sync
    pendingId = request.model.attributes["_pending_id"]
    delete request.model.attributes["_pending_id"]

    method  = getMethod(request)
    if not method?
      onSendSuccess(ctx, request, method)
      return deferred?.resolve.apply(this, arguments) if isRequestEmpty(request)

    options = request.methods[method]

    Backbone.sync(method, request.model, options)
    .done (value) ->
      onSendSuccess(ctx, request, method, value)
      deferred?.resolve.apply(this, arguments) if isRequestEmpty(request)

    .fail (error) ->
      request.model.attributes["_pending_id"] = pendingId
      onSendFail(ctx, request, error)

  return deferred


# Make the request fit avoiding useless actions such as [create -> delete]
optimizeRequest = (ctx, request) ->
  if request.methods['delete']? and request.methods['create']?
    request.methods = {}
    return request

  if (request.methods['create']? or request.methods['delete']?) and request.methods['update']?
    delete request.methods['update']
    return request

  return request


defaultCallbacks =
  onSynced    : ->
  onPending   : ->
  onCancelled : ->


module.exports = class RequestManager

  # You can give 3 differents callbacks: `onSynced`, `onPending`
  # and `onCancelled`, they all are called with the model
  constructor: (@callbacks={}) ->
    _.defaults(@callbacks, defaultCallbacks)

    onRestore = (request) ->
      request.model = new Backbone.Model(request.model)
      request.model.getKey = -> request.key
      request.model.getParentKeys = -> request.parentKeys
      request.model.url = -> request.url
      return request

    @pendingRequests = new MagicQueue(undefined, onRestore)
    @retrySync()


  # Return and array containing all pending requests
  getPendingRequests: ->
    return @pendingRequests.getQueue()


  # Reset the timer and retry to sync
  retrySync: ->
    clearTimer(@)
    consumeRequests(@)


  cancelPendingRequest: (key) ->
    request = @pendingRequests.retrieveItem(key)
    return if not request?
    @callbacks.onCancelled(request.model)


  # Cancel all pending requests
  clear: ->
    clearTimer(@)
    try
      for request in @pendingRequests.getQueue()
        @callbacks.onCancelled(request.model)
    catch e
      console.warn "Bad content found into mnemosyne magic queue", e
    @pendingRequests.clear()


  sync: (method, model, options = {}) ->
    request = initRequest(@, method, model, options)
    enqueueRequest(@, request)
    return request.deferred
