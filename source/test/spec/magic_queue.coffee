
describe 'Magic Queue specifications', ->

  magicQueue = null

  beforeEach ->
    MagicQueue = require('../app/magic_queue')
    magicQueue = new MagicQueue()
    magicQueue.clear()

  populateMagicQueue = ->
    for i in [1..10]
      magicQueue.addHead("key.#{i}",i)


  describe 'Spec addHead, addTail, retrieveHead, retrieveTail', ->
    it 'should retrieve the head object', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveHead()
      value.should.be.equal(10)

      value = magicQueue.retrieveHead()
      value.should.be.equal(9)

      magicQueue.addHead('key',17)
      value = magicQueue.retrieveHead()
      value.should.be.equal(17)

      done()

    it 'should retrieve the tail object', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveTail()
      value.should.be.equal(1)

      value = magicQueue.retrieveTail()
      value.should.be.equal(2)

      magicQueue.addTail('key',17)
      value = magicQueue.retrieveTail()
      value.should.be.equal(17)

      done()


  describe 'Spec retrieveItem', ->
    it 'should retrieve the object', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveItem("key.5")
      value.should.be.equal(5)

      done()

    it 'should return null if the object has already been retrieved', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveItem("key.5")
      value.should.be.equal(5)

      value = magicQueue.retrieveItem("key.5")
      # should.equal(value, undefined)
      # should.not.exist(value)

      done()

    it 'should retrieve null if the object is not in the queue', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveItem("key.92")
      # should.equal(value, undefined)

      done()


  describe 'Spec getItem', ->
    it 'should retrieve the object', (done) ->
      populateMagicQueue()
      value = magicQueue.getItem("key.5")
      value.should.be.equal(5)

      done()

    it 'should keep the value in the queue', (done) ->
      populateMagicQueue()
      value = magicQueue.getItem("key.5")
      value.should.be.equal(5)

      value = magicQueue.getItem("key.5")
      value.should.be.equal(5)

      done()


  describe 'Spec clear', ->
    it 'should return an empty array if the queue has been cleared', (done) ->
      populateMagicQueue()
      queue = magicQueue.getQueue()
      queue.should.not.be.empty

      magicQueue.clear()
      queue = magicQueue.getQueue()
      queue.should.be.empty

      done()

    it 'should always retrieve null if the queue has been cleared', (done) ->
      populateMagicQueue()
      value = magicQueue.getItem("key.5")
      value.should.be.equal(5)

      magicQueue.clear()
      value = magicQueue.getItem("key.5")
      #should.equal(value, undefined)

      done()


  describe 'Spec getQueue', ->
    it 'should return the correct array', (done) ->
      expectedQueue = [1..10]
      populateMagicQueue()
      queue = magicQueue.getQueue()

      equality = !( queue < expectedQueue || expectedQueue < queue )
      equality.should.be.true

      done()

    it 'should avoid duplicated keys', (done) ->
      expectedQueue = [1..11]
      populateMagicQueue()
      magicQueue.addHead("key.11",11)
      magicQueue.addTail("key.11",11)
      magicQueue.addHead("key.11",11)
      queue = magicQueue.getQueue()

      queue.length.should.be.equal(expectedQueue.length)
      equality = !( queue < expectedQueue || expectedQueue < queue )
      equality.should.be.true

      done()
