###
  - MagicQueue -
###

removeValue = (ctx, key) ->
  value = ctx.dict[key]
  delete  ctx.dict[key]
  return value

#Save the queue in DB
dbSync = (ctx) ->
  localStorage.setItem(ctx.key + '.orderedKeys', JSON.stringify(ctx.orderedKeys))
  localStorage.setItem(ctx.key + '.dict', JSON.stringify(ctx.dict))

DEFAULT_STORAGE_KEY = 'mnemosyne.pendingRequests'

module.exports = class MagicQueue

  # Keep the order state, only store keys.
  orderedKeys: []

  # Store all value with constant access.
  dict: {}

  constructor: (@key= DEFAULT_STORAGE_KEY, onRestore) ->
    # Load the queue from localStorage
    @orderedKeys = JSON.parse(localStorage.getItem(@key + '.orderedKeys')) or []
    @dict        = JSON.parse(localStorage.getItem(@key + '.dict'))        or {}
    if typeof onRestore is 'function'
      _.map(@dict, onRestore)


  addHead: (key, value) ->
    @retrieveItem(key)
    @orderedKeys.push(key)
    @dict[key] = value
    dbSync(this)


  addTail: (key, value) ->
    @retrieveItem(key)
    @orderedKeys.unshift(key)
    @dict[key] = value
    dbSync(this)


  getHead: ->
    @dict[_.last(@orderedKeys)]


  getTail: ->
    @dict[@orderedKeys[0]]


  rotate: ->
    return if @orderedKeys.length < 1
    @orderedKeys.unshift(@orderedKeys.pop())


  retrieveHead: ->
    return null if @orderedKeys.length is 0
    key = @orderedKeys.pop()
    value = removeValue(@, key)
    dbSync(this)
    return value


  retrieveTail: ->
    return null if @orderedKeys.length is 0
    key = @orderedKeys.shift()
    value = removeValue(@, key)
    dbSync(this)
    return value


  retrieveItem: (key) ->
    indexKey = @orderedKeys.indexOf(key)
    return null if indexKey is -1
    @orderedKeys.splice(indexKey, 1)
    value = removeValue(@, key)
    dbSync(this)
    return value


  getItem: (key) ->
    @dict[key] or null

  # TODO improve complexity
  isEmpty: ->
    return @getQueue().length is 0

  clear: ->
    @orderedKeys = []
    @dict = {}

    dbSync(this)


  getQueue: () ->
    queue = []
    for key in @orderedKeys
      if @dict[key]? and not @dict[key].removed
        queue.push(@dict[key])

    return queue
