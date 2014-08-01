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
requestsEmpty = (request) ->
  return Object.keys(request.methods).length is 0


# Store all needed information into a request object
initRequest = (ctx, req) ->
  req.key ?= -> req.model.getKey() + "/#{req.model.get('id')}"
  req.options ?= {}
  # Is there allready some pending request for this model?
  if request = ctx.pendingRequests.getItem(req.key())
    request.methods[req.method] = req.options
    pendingId = request.model.attributes['pending_id']
    request.model = req.model
    request.deferred = $.Deferred() if request.deferred.state() isnt 'pending'
    if not req.model.get('id')?
      req.model.attributes['pending_id'] = pendingId or new Date().getTime()
    return optimizeRequest(ctx, request)
  else
    req.parentKeys = req.model.getParentKeys()
    req.model.attributes['pending_id'] ?= new Date().getTime() if not req.model.get('id')
    req.deferred = $.Deferred()
    req.methods  = {}
    req.methods[req.method] = req.options

    return req


clearTimer = (ctx) ->
  clearTimeout(ctx.timeout)
  ctx.timeout  = null
  ctx.interval = MIN_INTERVAL


enqueueRequest = (ctx, request) ->
  ctx.pendingRequests.retrieveItem(request.key())
  if request? and not requestsEmpty(request)
    ctx.pendingRequests.addTail(request.key(), request)

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


onSendFail = (ctx, request, method, error) ->
  model = request.model
  if ctx.interval < MAX_INTERVAL
    ctx.interval = ctx.interval * 2

  console.debug 'onSendFail', request

  cancelRequest = ->
    ctx.callbacks.onCancelled(
      model: model
      key  : request.key
      method: method
    )
    request.deferred.reject()

  if model.cache.enabled
    status = error.readyState
    switch status
      when 4, 5
        cancelRequest()
      else
        enqueueRequest(ctx, request)
        ctx.callbacks.onPending(
          model: model
          key: request.key
          method: method
        )
        request.deferred.resolve(model.attributes)
  else
    cancelRequest()

  consumeRequests(ctx)


onSendSuccess = (ctx, request, method, data) ->
  model = request.model
  delete request.methods[method]
  ctx.interval = MIN_INTERVAL
  if requestsEmpty(request)
    ctx.pendingRequests.retrieveItem(request.key())
    ctx.callbacks.onSynced({model: model, cache: model.cache, method: method, key: request.key}, data)
    request.deferred.resolve(data)
  else
    enqueueRequest(ctx, request)
  consumeRequests(ctx)


# Try to send request, if it fails, push in queue and try again later
sendRequest = (ctx, request) ->
  method  = getMethod(request)
  model = request.model

  # -- DEBUG --
  if not method?
    console.warn "DEBUG -- no method in sendRequest"
    ctx.pendingRequests.retrieveItem(request.key())
    return request.deferred.resolve() if requestsEmpty(request)

  if not Utils.isConnected()
    onSendFail(ctx, request, method, 0)
    return

  else
    # Save and clean pending id before sync
    pendingId = model.attributes["pending_id"]
    delete model.attributes["pending_id"]

    options = request.methods[method]

    Backbone.sync(method, model, options)
    .done (data) ->
      # Restore pending id
      model.attributes["pending_id"] = pendingId
      onSendSuccess(ctx, request, method, data)

    .fail (error) ->
      model.attributes["pending_id"] = pendingId
      onSendFail(ctx, request, method, error)


# Make the request fit avoiding useless actions such as [create -> delete]
optimizeRequest = (ctx, request) ->
  if request.methods['create']? and request.methods['delete']?
    request.methods = {}

  else if (request.methods['create']? or request.methods['delete']?) and request.methods['update']?
    delete request.methods['update']

  return request


defaultCallbacks =
  onSynced    : ->
  onPending   : ->
  onCancelled : ->


module.exports = class RequestManager

  # You can give 3 differents callbacks: `onSynced`, `onPending`
  # and `onCancelled`
  constructor: (@callbacks={}) ->
    _.defaults(@callbacks, defaultCallbacks)

    onRestore = (request) ->
      request.model = new Backbone.Model(request.model)
      request.model.getKey = -> request.key()
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
    @callbacks.onCancelled(
      model: request.model
      key  : request.key
      cache: request.model.cache
    )


  # Cancel all pending requests
  clear: ->
    clearTimer(@)
    try
      for request in @pendingRequests.getQueue()
        @callbacks.onCancelled(
          model: request.model
          key  : request.key
          cache: request.model.cache
        )
    catch e
      console.warn "Bad content found into mnemosyne magic queue", e
    @pendingRequests.clear()


  sync: (request) ->
    method = request.method
    request = initRequest(@, request)
    model = request.model
    if requestsEmpty(request)
      @pendingRequests.retrieveItem(request.key())
      @callbacks.onSynced({model: model, cache: model.cache, method: method, key: request.key}, null)
      request.deferred.resolve()
    else
      enqueueRequest(@, request)
    return request.deferred
