module.exports = describe 'Request Manager specifications', ->

  server = null
  requestManager =  null
  model1 = null
  model2 = null
  model3 = null
  serverSpy = null
  online = true


  RequestManager = require '../../app/request_manager'
  ConnectionManager = require '../../app/connection_manager'
  Backbone       = require 'backbone'


  setUpServerResponse = (statusCode=200) ->
      server.respondWith (xhr) ->
        serverSpy.call()
        xhr.respond(
          statusCode
          "Content-Type": "application/json"
          '{"id": 1, "time":'+new Date().getTime()+'}'
        )

  beforeEach ->
    localStorage.clear()
    serverSpy = sinon.spy()
    requestManager = null
    requestManager = new RequestManager
      onSynced    : (request) -> request.model.finishSync()
      onPending   : (request) -> request.model.pendingSync()
      onCancelled : (request) -> request.model.unsync()
      ,
      new ConnectionManager(-> online)

    class CustomModel extends Backbone.Model
      cache:
        enabled: true

      constructor: ->
        super
        @setTime(new Date().getTime())

      getKey: -> '/modelKey_request'+ @get('id')
      getTime: -> @get('time')
      setTime: (value) -> @set('time', value)
      url: -> '/test_route'
    server = sinon.fakeServer.create()
    model1 = new CustomModel(id:1)
    model2 = new CustomModel(id:2)
    model3 = new CustomModel(id:3)

  afterEach ->
    server.restore()
    requestManager.clear()
    requestManager = null
    localStorage.clear()



  serverAutoRespondError = ->
    server.autoRespond = true

  serverAutoRespondOk = ->
    setUpServerResponse()
    server.autoRespond = true


  describe 'Spec clear', ->
    it 'should stop the scheduler when the queue is empty', (done) ->
      expect(requestManager.timeout).to.not.exist

      serverAutoRespondError()
      requestManager.sync({method: 'create', model: model1})
      .always ->
        expect(requestManager.timeout).to.exist
        requestManager.clear()
        expect(requestManager.timeout).to.not.exist
        done()

    it 'should reset the time interval when the queue is empty', (done) ->
      expect(requestManager.interval).to.equal(125)

      serverAutoRespondError()
      requestManager.sync({method: 'create', model: model1})
      .always ->
        setTimeout((->
          expect(requestManager.interval).to.be.above(125)
          requestManager.clear()
          expect(requestManager.interval).to.equal(125)
          done()),250)

  describe 'Database persistence', ->

    it 'should save the queue in db', (done) ->
      serverAutoRespondError()
      $.when(
        requestManager.sync({method: 'create', model: model1}),
        requestManager.sync({method: 'create', model: model2}),
        requestManager.sync({method: 'create', model: model3})
      ).done ->
        expect(JSON.parse(localStorage.getItem('mnemosyne.pendingRequests.orderedKeys')).length).to.equal(3)
        expect(Object.keys(JSON.parse(localStorage.getItem('mnemosyne.pendingRequests.dict'))).length).to.equal(3)
        done()

    it 'should load and try sync when db storage is not empty', (done) ->
      serverAutoRespondError()
      $.when(
        requestManager.sync({method: 'create', model: model1}),
        requestManager.sync({method: 'create', model: model2}),
        requestManager.sync({method: 'create', model: model3})
      ).done ->
        reqManager = new RequestManager()
        expect(reqManager.getPendingRequests().length).to.equal(3)
        done()

  ###
              +++++ ONLINE +++++
  ###
  describe 'Online', ->
    beforeEach ->
      model1.beginSync()
      serverAutoRespondOk()

    ###
                ONLINE - CACHE enabled
    ###
    describe 'Cache enabled', ->
      beforeEach ->
        model1.cache = {enabled : true}

      it 'should resolve the promise', (done) ->
        deferred = requestManager.sync({method: 'create', model: model1})
        deferred.always ->
          expect(serverSpy).to.have.been.calledOnce
          expect(deferred.state()).to.be.equal("resolved")
          done()

      it 'should trigger "synced" event on model', (done) ->
        model1.on "synced", -> done()
        requestManager.sync({method: 'update', model: model1})

    ###
                ONLINE - CACHE disabled
    ###
    describe 'Cache disabled', ->
      beforeEach ->
        model1.cache = {enabled : false}

      it 'should resolve the promise', (done) ->
        deferred = requestManager.sync({method: 'create', model: model1})
        deferred.always ->
          expect(serverSpy).to.have.been.calledOnce
          expect(deferred.state()).to.be.equal("resolved")
          done()

      it 'should trigger "synced" event on model', (done) ->
        model1.on "synced", -> done()
        requestManager.sync({method: 'update', model: model1})

  ###
              +++++ OFFLINE +++++
  ###
  describe 'Offline', ->
    beforeEach ->
      online = false
      model1.beginSync()
      serverAutoRespondError()
    ###
                OFFLINE - CACHE enabled
    ###
    describe 'Cache enabled', ->
      it 'should resolve the promise', (done) ->
        deferred = requestManager.sync({method: 'create', model: model1})
        deferred.always ->
          expect(deferred.state()).to.be.equal("resolved")
          done()

      # it 'should trigger "pending" event on model', (done) ->
      #   model1.beginSync()
      #   model1.on "pending", -> done()
      #   requestManager.sync({method: 'update', model: model1})
      #
      # it 'should trigger "pending" event on model if the request fail and is pushed in queue', (done) ->
      #   model1.on "pending", -> done()
      #   requestManager.sync({method: 'update', model: model1})

      describe 'Spec getPendingRequests', ->
        beforeEach ->
          requestManager.clear()

        it 'should return all pending requests', (done) ->
          nbPendingRequests = requestManager.getPendingRequests().length
          expect(nbPendingRequests).to.be.equal(0)

          serverAutoRespondError()

          $.when(
            requestManager.sync({method: 'update', model: model1}),
            requestManager.sync({method: 'update', model: model2}),
            requestManager.sync({method: 'update', model: model3}),
            requestManager.sync({method: 'update', model: model3}) # duplicate
          ).done ->
            nbPendingRequests = requestManager.getPendingRequests().length
            expect(nbPendingRequests).to.be.equal(3)
            done()


      describe 'Spec cancel request', ->
        beforeEach ->
          requestManager.clear()

        it 'should cancel the pending request', (done) ->
          nbPendingRequests = requestManager.getPendingRequests().length
          expect(nbPendingRequests).to.be.equal(0)

          serverAutoRespondError()
          $.when(
            requestManager.sync({method: 'update', model: model1}),
            requestManager.sync({method: 'update', model: model2}),
            requestManager.sync({method: 'update', model: model3}),
            requestManager.sync({method: 'update', model: model3}) # duplicate
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
            requestManager.sync({method: 'update', model: model1}),
            requestManager.sync({method: 'update', model: model2}),
            requestManager.sync({method: 'update', model: model3}),
            requestManager.sync({method: 'update', model: model3}) # duplicate
          ).done ->
            nbPendingRequests = requestManager.getPendingRequests().length
            expect(nbPendingRequests).to.be.equal(3)
            requestManager.clear()
            nbPendingRequests = requestManager.getPendingRequests().length
            expect(nbPendingRequests).to.be.equal(0)
            done()

        it 'should trigger "unsynced" on model when the request is cancelled', (done) ->
          model1.on 'unsynced', -> done()
          model1.on 'pending', -> requestManager.cancelPendingRequest(model1.getKey())
          serverAutoRespondError()
          requestManager.sync({method: 'update', model: model1})


      describe 'Spec retrySync', ->
        it 'should reset the interval value to the min value'


      describe 'Spec smart request', ->
        beforeEach ->
          requestManager.clear()
          serverAutoRespondError()

        it 'should cancel the request if a destroy is pending after a create', (done) ->
          $.when(
            requestManager.sync({method: 'create', model: model1}),
            requestManager.sync({method: 'update', model: model1}),
            requestManager.sync({method: 'delete', model: model1})
          ).always ->
            nbPendingRequests = requestManager.getPendingRequests().length
            expect(nbPendingRequests).to.be.equal(0)
            done()

        it 'should cancel the update request if a create request is pending', (done) ->
          $.when(
            requestManager.sync({method: 'create', model: model1}),
            requestManager.sync({method: 'update', model: model1}),
          ).done ->
            nbPendingRequests = requestManager.getPendingRequests().length
            expect(nbPendingRequests).to.be.equal(1)
            request = requestManager.getPendingRequests()[0]
            expect(request.methods['update']).to.not.exist
            done()

        it 'should cancel the update request if a destroy request is pending', (done) ->
          $.when(
            requestManager.sync({method: 'update', model: model1}),
            requestManager.sync({method: 'delete', model: model1})
          ).always ->
            methods = requestManager.getPendingRequests()[0].methods
            expect(methods.update).to.not.exist
            expect(methods.delete).to.exist
            done()

    ###
                OFFLINE - CACHE disabled
    ###
    describe 'Cache disabled', ->
      beforeEach ->
        model1.cache = {enabled : false}

      it 'should reject the promise', (done) ->
        deferred = requestManager.sync({method: 'create', model: model1})
        deferred.always ->
          expect(serverSpy).to.not.have.been.called
          expect(deferred.state()).to.be.equal("rejected")
          done()

      it 'should trigger "unsynced" event on model', (done) ->
        model1.on "unsynced", -> done()
        requestManager.sync({method: 'update', model: model1})
