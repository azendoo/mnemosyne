describe 'Mnemosyne specifications', ->

  server = null
  requestManager =  null
  model1 = null
  model2 = null
  model3 = null

  setUpServerResponse = ->
    server.respondWith (xhr) ->
      xhr.respond(
        200
        "Content-Type": "application/json"
        '[{"id": 1, "name":"item1"},{"id": 2, "name":"item2"}]'
      )


  beforeEach ->
    RequestManager = require '../app/request_manager'
    Backbone       = require 'backbone'
    requestManager = new RequestManager()
    requestManager.clear()

    model1 = new Backbone.Model()
    model1.getKey = -> 'model.1'
    model1.url = -> '/route_test'

    model2 = new Backbone.Model()
    model2.getKey = -> 'model.2'
    model2.url = -> '/route_test'

    model3 = new Backbone.Model()
    model3.getKey = -> 'model.3'
    model3.url = -> '/route_test'

    server = sinon.fakeServer.create()

  afterEach ->
    server.restore()

  serverAutoRespondError = ->
    server.autoRespond = true

  serverAutoRespondOk = ->
    setUpServerResponse()
    server.autoRespond = true

  # TODO check triggered events

  describe 'Online', ->
    beforeEach ->
      serverAutoRespondOk()

    it 'should trigger "syncing" event on model'

    describe 'Read value', ->
      describe 'Cache valid', ->
        it 'should trigger "synced" event on model'
        it 'should get data from cache'
        it 'should not to get data from server'


      describe 'Cache expired', ->
        it 'should trigger "synced" event on model'
        it 'should get data from cache'
        it 'should get data from cache, and after, update it with server data'
        it 'should write back server data in cache'


        describe '"allowExpiredCache" set to false', ->
          it 'should trigger "synced" event on model'
          it 'should not use data from cache'


      describe 'No cache', ->
        it 'should trigger "synced" event on model'
        it 'should get data from server'
        it 'should trigger "synced" event on model'


    describe 'Write value', ->
      describe 'Cache', ->
        it 'should trigger "synced" event on model'
        it 'should write data on server'
        it 'should write data in cache'


      describe 'No cache', ->
        it 'should trigger "synced" event on model'
        it 'should write data on server'
        it 'should not write data in cache'


  describe 'Offline', ->
    it 'should trigger "syncing" event on model'
    describe 'Read value', ->
      describe 'Cache valid', ->
        it 'should trigger "synced" event on model'
        it 'should get data from cache'
        it 'should not try to get data from server'


      describe 'Cache expired', ->
        it 'should trigger "synced" event on model'
        it 'should get data from cache'


        describe '"allowExpiredCache" set to false', ->
          it 'should trigger "unsynced" event on model'
          it 'should not get data from cache'
          it 'should unsynced the model'

      describe 'No cache', ->
        it 'should trigger "unsynced" event on model'
        it 'should unsynced the model'

    describe 'Write value', ->
      describe 'Cache', ->
        it 'should trigger "pending" event on model'
        it 'should write the data in cache and set the state to pending'


      describe 'No cache', ->
        it 'should trigger "pending" event on model'
        it 'should write the data in cache and set the state to pending'
        it 'should set the state to pending'

      describe 'On connection recovered', ->
        it 'should trigger "synced" event on model'
        it 'should write the data in cache and set the state to synced'
