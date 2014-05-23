module.exports = describe 'Mnemosyne specifications', ->

  server = null
  model = null
  CustomModel = null
  Backbone  = require 'backbone'
  Mnemosyne = require 'mnemosyne'
  mnemosyne = null
  serverSpy = null


  setUpServerResponse = ->
    server.respondWith (xhr) ->
      serverSpy.call()
      xhr.respond(
        200
        "Content-Type": "application/json"
        "{id: 1, time:#{new Date().getTime()}}"
      )


  before ->
    mnemosyne = new Mnemosyne()
    class CustomModel extends Backbone.Model
      constructor: ->
        super
        @setTime(new Date().getTime())

      getKey: -> 'modelKey'
      getTime: -> @get('time')
      setTime: (value) -> @set('time', value)
      url: -> '/test_route'
      sync: -> mnemosyne.sync.apply this, arguments

  beforeEach ->
    serverSpy = sinon.spy()
    server = sinon.fakeServer.create()
    model = new CustomModel(id:1)

    # Clear the localStorage may break sinon.server
    # mnemosyne.clear().done -> done()

  afterEach ->
    server.restore()

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
        model.constants = {cache : true}
        model.on "syncing", -> done()
        model.fetch()

      describe 'Cache valid', ->
        beforeEach (done) ->
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
          model.constants = {cache : true, ttl: 0}
          mnemosyne.cacheWrite(model)
          .done -> done()

        it 'should trigger "synced" event on model', (done) ->
          model.on "synced", -> done()
          model.fetch()

        it 'should get data from cache', (done) ->
          oldValue = model.getTime()
          model.setTime(0)
          model.fetch()
          .done ->
            expect(model.getTime()).to.equal(oldValue)
            done()

        it 'should get data from cache, and after, update it with server data'

        it 'should write back server data in cache', (done) ->
          model.setTime(17)
          mnemosyne.cacheWrite(model)
          .done ->
            model.fetch()
            .done() ->
              mnemosyne.cacheRead(model.getKey())
              .done (value) ->
                expect(value).to.not.equal(17)
                done()


        describe '"allowExpiredCache" set to false', ->
          beforeEach ->
            model.constants.allowExpiredCache = false

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
              .done() ->
                mnemosyne.cacheRead(model.getKey())
                .done (value) ->
                  expect(value).to.not.equal(17)
                  done()



      describe 'No cache', ->
        beforeEach (done) ->
          model.constants = {cache : false}
          model.setTime(17)
          mnemosyne.cacheWrite(model)
          .done -> done()

        it 'should trigger "synced" event on model', (done) ->
          model.on "synced", -> done()
          model.fetch()

        it 'should get data from server', (done) ->
          cacheValue = model.getTime()
          model.fetch()
          .done ->
            expect(model.getTime()).to.be.above(cacheValue)
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
            .done() ->
              mnemosyne.cacheRead(model.getKey())
              .done (value) ->
                expect(value).to.not.equal(17)
                done()


      describe 'No cache', ->
        beforeEach (done) ->
          model.constants = {cache : false}
          model.setTime(17)
          mnemosyne.cacheWrite(model)
          .done -> done()


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
          mnemosyne.cacheWrite(model)
          .done ->
            model.fetch()
            .done() ->
              mnemosyne.cacheRead(model.getKey())
              .done (value) ->
                expect(value).to.equal(17)
                done()


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
