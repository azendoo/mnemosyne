###
  - MagicQueue -

  Provides constant access to all operation,
  except for getting the queue.

  - TODO -
  db persistence

###

removeValue = (ctx, key) ->
  value = ctx.dict[key]
  delete  ctx.dict[key]
  return value

# TODO move the key to the constructor
KEY: 'mnemosyne.pendingRequests'

module.exports = class MagicQueue



  # Keep the order state, only store keys.
  orderedKeys: []

  # Store all value with constant access.
  dict: {}

  addHead: (key, value) ->
    @orderedQueue.push(key)
    @dict[key] = value


  addTail: (key, value) ->
    @orderedKeys.unshift(key)
    @dict[key] = value


  retrieveHead: () ->
    return null if @orderedKeys.length is 0
    key = @orderedKeys.pop()
    value = removeValue(key)
    if not value? or value.removed is true
      return @popHead()
    return value


  retrieveTail: () ->
    return null if @orderedKeys.length is 0
    key = @orderedKeys.shift()
    value = removeValue(key)
    if not value? or value.removed is true
      return @popTail()
    return value


  retrieveItem: (key) ->
    @dict[key]?.removed = true


  getItem: (key) ->
    @dict[key]

  # TODO improve complexity
  isEmpty: ->
    return @getQueue().length is 0

  clear: ->
    @orderedKeys = []
    @dict = {}


  getQueue: () ->
    queue = []
    for key in @orderedKeys
      if @dict[key]? and not @dict[key].removed
        queue.push(@dict[key])

    return queue
