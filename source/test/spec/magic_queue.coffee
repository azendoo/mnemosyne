describe 'Magic Queue specifications', ->

  magicQueue = null

  beforeEach: ->
    magicQueue = new MagicQueue()

  populateMagicQueue = ->
    for i in [1..10]
      magicQueue.addHead("key.#{i}",i)


  describe 'Spec addHead, addTail, retrieveHead, retrieveTail', ->
    it 'should retrieve the head object', (done) ->
      populateMagicQueue()

      value = magicQueue.retrieveHead()
      expect(value).to.be.equal(10)

      value = magicQueue.retrieveHead()
      expect(value).to.be.equal(9)

      magicQueue.addHead('key',17)
      value = magicQueue.retrieveHead()
      expect(value).to.be.equal(17)

      done()

    it 'should retrieve the tail object', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveTail()
      expect(value).to.be.equal(1)

      value = magicQueue.retrieveTail()
      expect(value).to.be.equal(9)

      magicQueue.addHead('key',17)
      value = magicQueue.retrieveTail()
      expect(value).to.be.equal(17)

      done()


  describe 'Spec retrieveItem', ->
    it 'should retrieve the object', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveItem("key5")
      expect(value).to.be.equal(5)


      done()

    it 'should return null if the object has already been retrieved', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveItem("key5")
      expect(value).to.be.equal(5)

      value = magicQueue.retrieveItem("key5")
      expect(value).to.be.equal(null)

      done()

    it 'should retrieve null if the object is not in the queue', (done) ->
      populateMagicQueue()
      value = magicQueue.retrieveItem("key92")
      expect(value).to.be.equal(null)

      done()


  describe 'Spec getItem', ->
    it 'should retrieve the object', (done) ->
      populateMagicQueue()
      value = magicQueue.getItem("key5")
      expect(value).to.be.equal(5)

      done()

    it 'should keep the value in the queue', ->
      populateMagicQueue()
      value = magicQueue.getItem("key5")
      expect(value).to.be.equal(5)

      value = magicQueue.getItem("key5")
      expect(value).to.be.equal(5)

      done()


  describe 'Spec clear', ->
    it 'should return an empty array if the queue has been cleared', (done) ->
      populateMagicQueue()
      queue = magicQueue.getQueue()
      expect(queue).not.to.be.empty()

      magicQueue.clear()
      queue = magicQueue.getQueue()
      expect(queue).to.be.empty()

      done()

    it 'should always retrieve null if the queue has been cleared', (done) ->
      populateMagicQueue()
      value = magicQueue.getItem("key5")
      expect(value).to.be.equal(5)

      magicQueue.clear()
      value = magicQueue.getItem("key5")
      expect(value).to.be.equal(null)

      done()


  describe 'Spec getQueue', ->
    it 'should return the correct array', (done) ->
      expectedQueue = [1..10]
      populateMagicQueue()
      queue = magicQueue.getQueue()
      expect(queue).to.be.equal(expectedQueue)

      done()

    it 'should avoid duplicated keys', (done) ->
      expectedQueue = [1..10]
      populateMagicQueue()
      magicQueue.addHead("key1",1)
      magicQueue.addHead("key1",1)
      magicQueue.addHead("key1",1)
      queue = magicQueue.getQueue()

      expect(queue.length).to.be.equal(expectedQueue.length)

      done()
