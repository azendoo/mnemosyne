module.exports = describe 'Mnemosyne specifications', ->

  server = null
  model  = null
  model2 = null
  collection = null
  CustomModel = null
  CustomCollection = null
  Backbone  = require 'backbone'
  Mnemosyne = require 'mnemosyne'
  mnemosyne = null
  serverSpy = null


  setUpServerResponse = (statusCode = 200)->
    server.respondWith (xhr) ->
      serverSpy.call()
      xhr.respond(
        statusCode
        "Content-Type": "application/json"
        '{"id": 1, "time":' + new Date().getTime()+'}'
      )


  before ->
    mnemosyne = new Mnemosyne()
    class CustomCollection extends Backbone.Collection
      getKey: -> 'parentKey'

    class CustomModel extends Backbone.Model
      cache:
        enabled: true

      constructor: ->
        super
        @setTime(new Date().getTime())

      getKey: -> 'modelKey'
      getParentKey: -> 'parentKey'
      getTime: -> @get('time')
      setTime: (value) -> @set('time', value)
      url: -> '/test_route'



  beforeEach ->
    mnemosyne = null
    mnemosyne = new Mnemosyne()
    serverSpy = sinon.spy()
    server = sinon.fakeServer.create()
    model = new CustomModel(id:1)
    model2 = new CustomModel(id:2)


    collection = new CustomCollection()

  afterEach ->
    server.restore()
    mnemosyne.clear()


  serverAutoRespondError = ->
    server.autoRespond = true

  serverAutoRespondOk = ->
    setUpServerResponse()
    server.autoRespond = true


  describe 'Online', ->
    beforeEach ->
      serverAutoRespondOk()

    describe 'Read value', ->
      it 'should trigger "syncing" event on model', (done) ->
        model.cache = {enabled : true}
        model.on "syncing", -> done()
        model.fetch()

      it 'should write the collection in cache', (done) ->
        collection.push(model2)
        collection.push(model)
        mnemosyne.cacheWrite(collection)
        .done ->
          mnemosyne.cacheRead(collection.getKey())
          .done (value) ->
            expect(value.length).equals(2)
            done()

      it 'should update the collection model', (done) ->
        mnemosyne.cacheWrite(collection)
        .done ->
          mnemosyne.cacheRead(collection.getKey())
          .done (value) ->
            expect(value).to.be.empty
            collection.push(model)
            mnemosyne.cacheWrite(collection).done ->
              model.setTime(256)
              mnemosyne.cacheWrite(model)
              .done ->
                mnemosyne.cacheRead(collection.getKey())
                .done (value) ->
                  expect(value[0].time).equals(256)
                  done()

      it 'should add the model to the cache of the parent collection if the model is not new', (done) ->
        collection.push(model)
        mnemosyne.cacheWrite(collection).done ->
          mnemosyne.cacheRead(collection.getKey())
          .done (value) ->
            expect(value.length).equals(1)
            model2.save()
            .done ->
              mnemosyne.cacheRead(collection.getKey())
              .done (value) ->
                expect(value.length).equals(2)
                done()


      describe 'Cache valid', ->
        beforeEach (done) ->
          model.cache = {enabled : true}
          mnemosyne.cacheWrite(model)
          .done -> done()

        it 'should trigger "synced" event on model', (done) ->
          model.on "synced", -> done()
          model.fetch()

        it 'should get data from cache', (done) ->
          cacheTime = model.getTime()
          model.setTime(0)
          model.fetch()
          .done (value) ->
            expect(model.getTime()).to.be.equal(cacheTime)
            done()

        it 'should not to get data from server', (done) ->
          server.autoRespond = false
          model.on "synced", ->
            expect(server.requests).to.be.empty
            done()
          model.fetch()


      describe 'Cache expired', ->
        beforeEach (done) ->
          model.cache = {enabled : true, ttl: 0}
          model.setTime(0)
          mnemosyne.cacheWrite(model)
          .done -> done()

        it 'should trigger "synced" event on model', (done) ->
          model.on "synced", -> done()
          model.fetch()

        it 'should get data from cache', (done) ->
          model.setTime(17)
          model.fetch()
          .done ->
            expect(model.getTime()).to.equal(0)
            done()

        it 'should get data from cache, and after, update it with server data'

        it 'should write back server data in cache', (done) ->
          model.fetch()
          .done ->
            mnemosyne.cacheRead(model.getKey())
            .done (value) ->
              expect(value).to.not.equal(0)
            .always -> done()


        describe '"allowExpiredCache" set to false', ->
          beforeEach ->
            model.cache.allowExpiredCache = false

          it 'should trigger "synced" event on model', (done) ->
            model.on "synced", ->
              done()
            model.fetch()

          it 'should not use data from cache', (done) ->
            cacheValue = model.getTime()
            model.fetch()
            .done ->
              expect(model.getTime()).to.be.above(cacheValue)
              done()

          it 'should write back server data in cache', (done) ->
            model.setTime(17)
            mnemosyne.cacheWrite(model)
            .done ->
              model.fetch()
              .done ->
                mnemosyne.cacheRead(model.getKey())
                .done (value) ->
                  expect(value).to.not.equal(17)
                  done()


      describe 'No cache', ->
        # Should never equal 0
        beforeEach (done) ->
          model.setTime(0)
          mnemosyne.cacheWrite(model)
          .done ->
            model.cache = {enabled : false}
            done()

        it 'should trigger "synced" event on model', (done) ->
          model.on "synced", -> done()
          model.fetch()

        it 'should get data from server', (done) ->
          model.fetch()
          .done ->
            expect(model.getTime()).to.be.above(0)
            done()


    describe 'Write value', ->
      it 'should trigger "syncing" event on model', (done) ->
        model.on "syncing", -> done()
        model.save()


      describe 'Cache', ->
        it 'should trigger "synced" event on model', (done) ->
          model.on "synced", -> done()
          model.save()

        it 'should write data on server', (done) ->
          model.save()
          .done ->
            expect(serverSpy).calledOnce
            done()

        it 'should write data in cache', (done) ->
          model.setTime(17)
          mnemosyne.cacheWrite(model)
          .done ->
            model.fetch()
            .done ->
              mnemosyne.cacheRead(model.getKey())
              .done (value) ->
                expect(value).to.not.equal(17)
                done()


      describe 'No cache', ->
        # Should never be 0
        beforeEach (done) ->
          model.setTime(0)
          mnemosyne.cacheWrite(model)
          .done ->
            model.cache = {enabled : false}
            done()


        it 'should trigger "synced" event on model', (done) ->
          model.on "synced", -> done()
          model.save()

        it 'should write data on server', (done) ->
          model.save()
          .done ->
            expect(serverSpy).calledOnce
            done()


        it 'should not write data in cache', (done) ->
          model.setTime(17)
          model.save()
          .done ->
            mnemosyne.cacheRead(model.getKey())
            .always (value) ->
              expect(value).to.not.exists
              done()


  describe 'Offline', ->
    beforeEach ->
      serverAutoRespondError()

    it 'should trigger "syncing" event on model', (done) ->
      model.on 'syncing', -> done()
      model.save()

    describe 'Read value', ->
      describe 'Cache valid', ->
        beforeEach (done) ->
          model.setTime(52)
          mnemosyne.cacheWrite(model)
          .done -> done()

        it 'should trigger "synced" event on model', (done) ->
          model.on 'synced', -> done()
          model.fetch()

        it 'should get data from cache', (done) ->
          model.setTime(17)
          model.fetch()
          .done ->
            expect(model.getTime()).to.equal(52)
            done()

        it 'should not try to get data from server', (done) ->
          model.fetch()
          .done ->
            expect(serverSpy).not.called
            done()


      describe 'Cache expired', ->
        beforeEach (done) ->
          model.cache = {enabled : true, ttl: 0}
          model.setTime(19)
          mnemosyne.cacheWrite(model)
          .done -> done()


        it 'should trigger "synced" event on model', (done) ->
          model.on 'synced', -> done()
          model.fetch()

        it 'should get data from cache', (done) ->
          model.setTime(52)
          model.fetch()
          .done ->
            expect(model.getTime()).equal(19)
            done()


        describe '"allowExpiredCache" set to false', ->
          beforeEach ->
            model.cache.allowExpiredCache = false

          it 'should trigger "unsynced" event on model', (done) ->
            model.on "unsynced", -> done()
            model.fetch()

          it 'should not use data from cache', (done) ->
            model.setTime(52)
            model.fetch()
            .fail ->
              expect(model.getTime()).equal(52)
              done()


      describe 'No cache', ->
        # model.getTime() should never be 0
        beforeEach (done) ->
          model.setTime(0)
          mnemosyne.cacheWrite(model)
          .done ->
            model.cache = {enabled : false}
            done()

        it 'should trigger "unsynced" event on model', (done) ->
          model.on 'unsynced', -> done()
          model.fetch()

    describe 'Write value', ->
      describe 'Cache', ->
        it 'should trigger "pending" event on model', (done)->
          model.on 'pending', -> done()
          model.save()

        it 'should write the data in cache', (done) ->
          model.setTime(13)
          model.save()
          .done ->
            mnemosyne.cacheRead(model.getKey())
            .done (value) ->
              expect(value.time).to.equal(13)
              done()

        it 'should push the request in the queue', (done) ->
          model2.save()
          model.save()
          .done ->
            expect(mnemosyne.getPendingRequests()).not.be.empty
            done()

      describe 'No cache', ->
        # model.getTime() should never be 0
        beforeEach (done) ->
          model.setTime(0)
          mnemosyne.cacheWrite(model)
          .done ->
            model.cache = {enabled : false}
            done()

        it 'should trigger "pending" event on model', (done) ->
          model.on 'pending', -> done()
          model.save()

        it 'should write the data in cache', (done) ->
          model.setTime(13)
          model.save()
          .done ->
            mnemosyne.cacheRead(model.getKey())
            .done (value) ->
              expect(value.time).to.equal(13)
              done()


      describe 'On connection recovered', ->
        it 'should trigger "synced" event on model'
        it 'should write the data in cache and set the state to synced'
