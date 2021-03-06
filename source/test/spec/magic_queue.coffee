module.exports = describe 'Magic Queue specifications', ->

  magicQueue = null

  beforeEach ->
    MagicQueue = require('../../app/magic_queue')
    magicQueue = new MagicQueue()
    magicQueue.clear()

  populateMagicQueue = ->
    for i in [1..10]
      magicQueue.addHead("key.#{i}",i)


  describe 'Spec addHead, addTail, retrieveHead, retrieveTail', ->
    it 'should retrieve the head object', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveHead()
      expect(value).to.equal(10)

      value = magicQueue.retrieveHead()
      expect(value).to.equal(9)

      magicQueue.addHead('key',17)
      value = magicQueue.retrieveHead()
      expect(value).to.equal(17)

      done()

    it 'should retrieve the tail object', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveTail()
      expect(value).to.equal(1)

      value = magicQueue.retrieveTail()
      expect(value).to.equal(2)

      magicQueue.addTail('key',17)
      value = magicQueue.retrieveTail()
      expect(value).to.equal(17)

      done()


  describe 'Spec retrieveItem', ->
    it 'should retrieve the object', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveItem("key.5")
      expect(value).to.equal(5)

      done()

    it 'should return null if the object has already been retrieved', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveItem("key.5")
      expect(value).to.equal(5)

      value = magicQueue.retrieveItem("key.5")
      expect(value).to.be.null

      done()

    it 'should retrieve null if the object is not in the queue', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveItem("key.92")
      expect(value).to.be.null

      done()


  describe 'Spec getItem', ->
    it 'should retrieve the object', (done) ->
      populateMagicQueue()
      value = magicQueue.getItem("key.5")
      expect(value).to.equal(5)

      done()

    it 'should keep the value in the queue', (done) ->
      populateMagicQueue()
      value = magicQueue.getItem("key.5")
      expect(value).to.equal(5)

      value = magicQueue.getItem("key.5")
      expect(value).to.equal(5)

      done()


  describe 'Spec clear', ->
    it 'should return an empty array if the queue has been cleared', (done) ->
      populateMagicQueue()
      queue = magicQueue.getQueue()
      expect(queue).not.be.empty

      magicQueue.clear()
      queue = magicQueue.getQueue()
      expect(queue).to.be.empty

      done()

    it 'should always retrieve null if the queue has been cleared', (done) ->
      populateMagicQueue()
      value = magicQueue.getItem("key.5")
      expect(value).to.equal(5)

      magicQueue.clear()
      value = magicQueue.getItem("key.5")
      expect(value).to.be.null

      done()


  describe 'Spec getQueue', ->
    it 'should return the correct array', (done) ->
      expectedQueue = [1..10]
      populateMagicQueue()
      queue = magicQueue.getQueue()

      expect(queue).to.eql(expectedQueue)

      done()

    it 'should avoid duplicated keys', (done) ->
      expectedQueue = [1..11]
      populateMagicQueue()
      magicQueue.addHead("key.11",11)
      magicQueue.addTail("key.11",11)
      magicQueue.addHead("key.11",11)
      queue = magicQueue.getQueue()

      expect(queue).to.eql(expectedQueue)

      done()

  describe 'Spec getHead', ->
    it 'should return the head value', ->
      populateMagicQueue()
      expect(magicQueue.getHead()).to.be.equal(10)

    it 'should keep the value at the head', ->
      expectedQueue = [1..10]
      populateMagicQueue()
      magicQueue.getHead()
      magicQueue.getHead()
      magicQueue.getHead()
      magicQueue.getHead()
      expect(magicQueue.getHead()).to.be.equal(10)
      expect(magicQueue.getQueue()).to.eql(expectedQueue)


  describe 'Spec getTail', ->
    it 'should return the tail value', ->
      populateMagicQueue()
      expect(magicQueue.getTail()).to.be.equal(1)

    it 'should keep the value at the tail', ->
      expectedQueue = [1..10]
      populateMagicQueue()
      magicQueue.getHead()
      magicQueue.getTail()
      expect(magicQueue.getTail()).to.be.equal(1)
      expect(magicQueue.getQueue()).to.eql(expectedQueue)

  describe 'Spec rotate', ->
    it 'should pop the head and unshift it to the queue', ->
      expectedQueue = [8,9,10,1,2,3,4,5,6,7]
      populateMagicQueue()
      magicQueue.rotate()
      magicQueue.rotate()
      magicQueue.rotate()
      expect(magicQueue.getQueue()).to.eql(expectedQueue)
