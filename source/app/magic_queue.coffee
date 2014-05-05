###
  - MagicQueue -

  Provides constant access to all operation,
  except for getting the queue.

  - TODO -


###

removeValue = (ctx, key) ->
  value = ctx.dict[key]
  delete  ctx.dict[key]
  return value


module.exports = class MagicQueue

  # Keep the order state, only store keys.
  orderedKeys: []

  # Store all value with constant access.
  dict: {}

  pushHead: (key, value) ->
    @orderedQueue.push(key)
    @dict[key] = value


  pushTail: (key, value) ->
    @orderedKeys.unshift(key)
    @dict[key] = value


  popHead: () ->
    return null if @orderedKeys.length is 0
    key = @orderedKeys.pop()
    value = removeValue(key)
    if not value? or value.removed is true
      return @popHead()
    return value


  popTail: () ->
    return null if @orderedKeys.length is 0
    key = @orderedKeys.shift()
    value = removeValue(key)
    if not value? or value.removed is true
      return @popTail()
    return value


  removeItem: (key) ->
    @dict[key]?.removed = true


  getItem: (key) ->
    @dict[key]


  clear: ->
    @orderedKeys = []
    @dict = {}


  getQueue: () ->
    queue = []
    for key in @orderedKeys
      queue.push(@dict[key])

    return queue
