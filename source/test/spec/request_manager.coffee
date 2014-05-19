describe 'Request Manager specifications', ->

  requestManager =  null
  model = null

  beforeEach: ->
    requestManager = new RequestManager()
    requestManager.clear()

    model1 = new Backbone.model()
    model1.getKey() = -> 'model.1'
    model2 = new Backbone.model()
    model2.getKey() = -> 'model.2'
    model3 = new Backbone.model()
    model3.getKey() = -> 'model.3'

  it 'should be ok', (done) ->
    done()

  describe 'Spec clear', ->
    it 'should stop the scheduler when the queue is empty', ->
      expect(requestManager.timeout).to.be.equal(null)
      requestManager.safeSync('write', model1)
      expect(requestManager.timeout).not.to.be.equal(null)
      requestManager.clear()
      expect(requestManager.timeout)to.be.equal(null)

    it 'should reset the time interval when the queue is empty', ->
      expect(requestManager.interval).to.be.equal(250)
      requestManager.safeSync('write', model1)
      # autorespond server error
      expect(requestManager.interval).to.be.greater(400)
      requestManager.clear()
      expect(requestManager.interval)to.be.equal(250)


  describe 'Spec safeSync', ->
    it 'should resolve the promise if the request succeed on the first try', (done) ->
      # server autorespond ok
      deferred = requestManager.safeSync('update', model1)
      .always ->
        expect(deferred.state()).to.be.equal("resolved")
        done()

    it 'should trigger "synced" event on model if the request succeed on the first try', (done) ->
      model.on "synced", -> done()
      # server autorespond ok
      requestManager.safeSync('update', model1)

    it 'should trigger "pending" event on model if the request fail and is pushed in queue', (done) ->
      model.on "pending", -> done()
      # server autorespond not  ok
      requestManager.safeSync('update', model1)

    it 'should trigger "synced" after a "pending" event on model when the request succeed', (done) ->
      pendingTriggered = false
      model.on "pending", ->
        pendingTriggered = true
        # server autorespond ok

      model.on "synced", ->
        expect(pendingTriggered).to.be.true
        done()

      # server autorespond not  ok
      requestManager.safeSync('update', model1)


  describe 'Spec getPendingRequests', ->
    it 'should return all pending requests', (done) ->
      nbPendingRequests = requestManager.getPendingRequests().length
      expect(nbPendingRequests).to.be.equal(0)

      # server autorespond not  ok
      requestManager.safeSync('update', model1)
      requestManager.safeSync('update', model2)
      requestManager.safeSync('update', model3)
      requestManager.safeSync('update', model3) # duplicate

      nbPendingRequests = requestManager.getPendingRequests().length
      expect(nbPendingRequests).to.be.equal(3)
      done()


  describe 'Spec cancel request', ->
    it 'should cancel the pending request', (done) ->
      nbPendingRequests = requestManager.getPendingRequests().length
      expect(nbPendingRequests).to.be.equal(0)

      # server autorespond not  ok
      requestManager.safeSync('update', model1)
      requestManager.safeSync('update', model2)
      requestManager.safeSync('update', model3)
      requestManager.safeSync('update', model3) # duplicate

      requestManager.cancelPendingRequest(model3.getKey())
      nbPendingRequests = requestManager.getPendingRequests().length
      expect(nbPendingRequests).to.be.equal(2)
      done()

    it 'should cancel all pending requests', (done) ->
      nbPendingRequests = requestManager.getPendingRequests().length
      expect(nbPendingRequests).to.be.equal(0)

      # server autorespond not  ok
      requestManager.safeSync('update', model1)
      requestManager.safeSync('update', model2)
      requestManager.safeSync('update', model3)
      requestManager.safeSync('update', model3) # duplicate

      requestManager.cancelPendingRequest(model3.getKey())
      nbPendingRequests = requestManager.getPendingRequests().length
      expect(nbPendingRequests).to.be.equal(2)
      done()

    it 'should trigger "unsynced" on model when the request is cancelled', (done) ->
      model1.on 'unsynced', -> done()
      # server autorespond not  ok
      requestManager.safeSync('update', model1)
      requestManager.cancelPendingRequest(model1.getKey())


  describe 'Spec retrySync', ->
    it 'should do nothing if there is no pending requests', ->
      # TODO add spy on consume()
      nbPendingRequests = requestManager.getPendingRequests().length
      expect(nbPendingRequests).to.be.equal(0)
      expect(spyConsume).not.to.have.been.called()

      requestManager.retrySync()
      expect(spyConsume).not.to.have.been.called()


    it 'should call reset the interval value to the min value', (done) ->
      expect(requestManager.interval).to.be.equal(250)
      requestManager.safeSync('write', model1)
      # autorespond server error
      requestManager.safeSync('update', model1)
      .reject
        expect(requestManager.interval).to.be.greater(400)
        requestManager.retrySync()
        expect(requestManager.interval)to.be.equal(250)
        done()
