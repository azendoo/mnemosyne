module.exports = describe 'Request Manager specifications', ->

  server = null
  requestManager =  null
  model1 = null
  model2 = null
  model3 = null

  RequestManager = require '../../app/request_manager'
  Backbone       = require 'backbone'


  setUpServerResponse = (statusCode=200) ->
      server.respondWith (xhr) ->
        xhr.respond(
          statusCode
          "Content-Type": "application/json"
          '{"id": 1, "time":'+new Date().getTime()+'}'
        )

  beforeEach ->
    requestManager = new RequestManager
      onSynced    : (model) -> model.finishSync()
      onPending   : (model) -> model.pendingSync()
      onCancelled : (model) -> model.unsync()
    requestManager.clear()

    class CustomModel extends Backbone.Model
      constructor: ->
        super
        @setTime(new Date().getTime())

      getKey: -> 'modelKey_request'+ @get('id')
      getTime: -> @get('time')
      setTime: (value) -> @set('time', value)
      url: -> '/test_route'
    server = sinon.fakeServer.create()
    model1 = new CustomModel(id:1)
    model2 = new CustomModel(id:2)
    model3 = new CustomModel(id:3)

  afterEach ->
    server.restore()



  serverAutoRespondError = ->
    server.autoRespond = true

  serverAutoRespondOk = ->
    setUpServerResponse()
    server.autoRespond = true


  describe 'Spec clear', ->
    it 'should stop the scheduler when the queue is empty', (done) ->
      expect(requestManager.timeout).to.not.exist

      serverAutoRespondError()
      requestManager.safeSync('create', model1)
      .always ->
        requestManager.clear()
        expect(requestManager.timeout).to.not.exist
        done()

    it 'should reset the time interval when the queue is empty', (done) ->
      expect(requestManager.interval).to.equal(250)

      serverAutoRespondError()
      requestManager.safeSync('create', model1)
      .always ->
        setTimeout((->
          expect(requestManager.interval).to.be.above(400)
          requestManager.clear()
          expect(requestManager.interval).to.equal(250)
          done()),250)


  describe 'Spec safeSync', ->
    it 'should resolve the promise if the request succeed on the first try', (done) ->
      serverAutoRespondOk()
      deferred = requestManager.safeSync('create', model1)
      deferred.always ->
        expect(deferred.state()).to.be.equal("resolved")
        done()

    it 'should trigger "synced" event on model if the request succeed on the first try', (done) ->
      serverAutoRespondOk()
      model1.on "synced", -> done()
      requestManager.safeSync('update', model1)

    it 'should trigger "pending" event on model if the request fail and is pushed in queue', (done) ->
      model1.on "pending", -> done()
      serverAutoRespondError()
      requestManager.safeSync('update', model1)

    it 'should trigger "synced" after a "pending" event on model when the request succeed'


  describe 'Spec getPendingRequests', ->
    it 'should return all pending requests', (done) ->
      nbPendingRequests = requestManager.getPendingRequests().length
      expect(nbPendingRequests).to.be.equal(0)

      serverAutoRespondError()

      $.when(
        requestManager.safeSync('update', model1),
        requestManager.safeSync('update', model2),
        requestManager.safeSync('update', model3),
        requestManager.safeSync('update', model3) # duplicate
      ).done ->
        nbPendingRequests = requestManager.getPendingRequests().length
        expect(nbPendingRequests).to.be.equal(3)
        done()


  describe 'Spec cancel request', ->
    it 'should cancel the pending request', (done) ->
      nbPendingRequests = requestManager.getPendingRequests().length
      expect(nbPendingRequests).to.be.equal(0)

      serverAutoRespondError()
      $.when(
        requestManager.safeSync('update', model1),
        requestManager.safeSync('update', model2),
        requestManager.safeSync('update', model3),
        requestManager.safeSync('update', model3) # duplicate
      ).done ->
        requestManager.cancelPendingRequest(model3.getKey())
        nbPendingRequests = requestManager.getPendingRequests().length
        expect(nbPendingRequests).to.be.equal(2)
        done()

    it 'should cancel all pending requests', (done) ->
      nbPendingRequests = requestManager.getPendingRequests().length
      expect(nbPendingRequests).to.be.equal(0)

      serverAutoRespondError()
      $.when(
        requestManager.safeSync('update', model1),
        requestManager.safeSync('update', model2),
        requestManager.safeSync('update', model3),
        requestManager.safeSync('update', model3) # duplicate
      ).done ->
        requestManager.cancelPendingRequest(model3.getKey())
        nbPendingRequests = requestManager.getPendingRequests().length
        expect(nbPendingRequests).to.be.equal(2)
        done()

    it 'should trigger "unsynced" on model when the request is cancelled', (done) ->
      model1.on 'unsynced', -> done()
      model1.on 'pending', -> requestManager.cancelPendingRequest(model1.getKey())
      serverAutoRespondError()
      requestManager.safeSync('update', model1)


  describe 'Spec retrySync', ->
    it 'should reset the interval value to the min value'


  describe 'Spec smart request', ->
    it 'should cancel the request if a destroy is pending after a create', (done) ->
      serverAutoRespondError()
      $.when(
        requestManager.safeSync('create', model1),
        requestManager.safeSync('update', model1),
        requestManager.safeSync('delete', model1)
      ).always ->
        nbPendingRequests = requestManager.getPendingRequests().length
        expect(nbPendingRequests).to.be.equal(0)
        done()

    it 'should cancel the update request if a create request is pending', (done) ->
      serverAutoRespondError()
      $.when(
        requestManager.safeSync('create', model1),
        requestManager.safeSync('update', model1),
      ).done ->
        nbPendingRequests = requestManager.getPendingRequests().length
        expect(nbPendingRequests).to.be.equal(1)
        request = requestManager.getPendingRequests()[0]
        expect(request.methods['update']).to.not.exist
        done()

    it 'should cancel the update request if a destroy request is pending'
