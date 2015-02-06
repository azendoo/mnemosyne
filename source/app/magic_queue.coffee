###
  - MagicQueue -
###

removeValue = (ctx, key) ->
  value = ctx.dict[key]
  delete  ctx.dict[key]
  return value

#Sync the queue with database
dbSync = (ctx) ->
  return
  # _.defer ->
  #   localStorage.setItem(ctx.key + '.orderedKeys', JSON.stringify(ctx.orderedKeys))
  #   localStorage.setItem(ctx.key + '.dict', JSON.stringify(ctx.dict))

DEFAULT_STORAGE_KEY = 'mnemosyne.pendingRequests'

module.exports = class MagicQueue

  # Keep the order state, only store keys.
  orderedKeys: []

  # Store all value with constant access.
  dict: {}

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


  getItem: (key) ->
    @dict[key] or null


  rotate: ->
    return if @orderedKeys.length < 1
    @orderedKeys.unshift(@orderedKeys.pop())


  retrieveHead: ->
    return null if @orderedKeys.length is 0
    key   = @orderedKeys.pop()
    value = removeValue(@, key)
    dbSync(this)
    return value


  retrieveTail: ->
    return null if @orderedKeys.length is 0
    key   = @orderedKeys.shift()
    value = removeValue(@, key)
    dbSync(this)
    return value


  retrieveItem: (key) ->
    return null if not @dict[key]?
    indexKey = @orderedKeys.indexOf(key)
    @orderedKeys.splice(indexKey, 1)
    value = removeValue(@, key)
    dbSync(this)
    return value


  isEmpty: ->
    return @orderedKeys.length is 0


  getQueue: () ->
    _.map(@orderedKeys, (key) =>
      return @dict[key]
      )


  clear: ->
    @orderedKeys = []
    @dict = {}
    dbSync(this)
