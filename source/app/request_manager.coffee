MagicQueue = require "./magic_queue"

###
	TODO
	* limit the number of pending requests ?
	* manage the database limit
	* documentation
	* set models status according to events, and update the cache
	* manage connectivity
	* request db persistence
###

store = localforage
defaultEventMap =
	'syncing'     : 'syncing'
	'pending'     : 'pending'
	'synced'      : 'synced'
	'unsynced'    : 'unsynced'

###
	------- Private methods -------
###

deleteRequest = (ctx, request) ->
	store.removeItem(request.url)
	delete ctx.pendingKeys[request.url]


cancelRequest = (ctx, request) ->
	request.model.trigger(ctx.eventMap['unsynced'])
	deleteRequest(ctx, request)


pushRequest = (ctx, request) ->
	return if not request?

	ctx.pendingRequests.push(request)
	clearTimeout(ctx.timeout)
	interval = 500

	return @_consume(ctx)


consume = (ctx) ->
	deferred = $.deferred()

	req = ctx.pendingRequests.pop()
	return deferred.reject() if not req?

	Backbone.sync(req.method, req.model, req.options)
	.done ->
		request.model.trigger('sent')
		deferred.resolve.apply(this, arguments)
	.fail ->
		ctx.pendingRequests.unshift(req)
		request.model.trigger('request:pending')
		if ctx._interval < ctx._MAX_REQUEST_INTERVAL * 1000 # 60 seconds
			ctx._interval = ctx._interval * 2
		ctx._timeout  = setTimeout( (-> consume(ctx) ), ctx._interval)
		deferred.reject.apply(this, arguments)

	return deferred



###
	------- Public methods -------
###

module.exports = class RequestManager

	MAX_REQUEST_INTERVAL: 60 #seconds
	KEY: 'mnemosyne.pendingRequests'

	###
		request:
			method
			model
			options
			url // replace by key ?
	###

	constructor: (eventMap = {})->
		@eventMap = _.extend(defaultEventMap, eventMap)
		store.getItem(@KEY)
		.done (values) =>
			if (values instanceof Array)
				@pendingRequests = values.concat(@pendingRequests)


	clear: ->
		@cancelAllPendingRequests()


  getPendingRequests: ->
  	return @pendingRequests


  retryRequest: (index) ->
		request = @pendingRequests.splice(index, 1)[0]
		pushRequest(@, request)


  cancelAllPendingRequests:  ->
  	@pendingRequests.map((request) => cancelRequest(@, request))
  	@pendingRequests = []
		@pendingKey = {}


  cancelPendingRequest: (index) ->
  	request = @pendingRequests.splice(index, 1)
  	return if not request?
		cancelRequest(@, request)


  sync: (method, model, options) ->
  	request = {}
  	request.method  = method
  	request.model   = model
  	request.options = options

  	return @pushRequest(@, request)
