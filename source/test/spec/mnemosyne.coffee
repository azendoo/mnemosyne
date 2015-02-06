module.exports = describe 'Mnemosyne specifications', ->

  server = null
  model  = null
  model2 = null
  newModel = null
  collection = null
  collection2 = null
  CustomModel = null
  CustomCollection = null
  Backbone  = require 'backbone'
  Mnemosyne = require 'mnemosyne'
  mnemosyne = null
  serverSpy = null
  online = true

  setUpServerResponse = (statusCode = 200)->
    server.respondWith (xhr) ->
      serverSpy.call()
      switch xhr.url
        when '/model/1'
          xhr.respond(
            statusCode
            "Content-Type": "application/json"
            '{"id": 1, "name":"serverModel1"}'
          )
        when '/model/2'
          xhr.respond(
            statusCode
            "Content-Type": "application/json"
            '{"id": 2, "name":"serverModel2"}'
          )
        when '/collection'
          xhr.respond(
            statusCode
            "Content-Type": "application/json"
            '[{"id": 1, "name":"serverModel1"}, {"id": 2, "name":"serverModel2"}]'
          )
        else
          xhr.respond(
            statusCode
            "Content-Type": "application/json"
            '{"id": 3, "name":"serverNewModel3"}'
          )


  before ->

    mnemosyne = new Mnemosyne(isOnline: -> online)

    class CustomModel extends Backbone.Model
      cache:
        enabled: true

      constructor: ->
        super

      getKey: -> 'modelKey'
      getParentKeys: -> ['parentKey1', 'parentKey2']
      getName: -> @get('name')
      setName: (value) -> @set('name', value)
      url: -> "/model/#{@get('id')}"

    class CustomCollection extends Backbone.Collection
      model: CustomModel
      cache:
        enabled: true
      getKey: -> 'parentKey1'
      url: -> '/collection'


  beforeEach ->
    mnemosyne = null
    mnemosyne = new Mnemosyne(isOnline: -> online)
    serverSpy = sinon.spy()
    server = sinon.fakeServer.create()
    model = new CustomModel(id:1)
    model2 = new CustomModel(id:2)
    model2.getKey = -> 'modelKey2'
    model2.setName('model2')
    newModel = new CustomModel()
    newModel.getKey = -> 'newModelKey'
    collection = new CustomCollection()
    collection2 = new CustomCollection()
    collection2.getKey = ->'parentKey2'
    mnemosyne.cacheClear()



  afterEach ->
    server.restore()
    mnemosyne.cacheClear()



  serverAutoRespondError = ->
    server.autoRespond = true

  serverAutoRespondOk = ->
    setUpServerResponse()
    server.autoRespond = true

  serverSetOffline= ->
    sinon.stub(Backbone, "sync", -> $.Deferred().reject(readyState: 0))

  serverSetOnline= ->
    Backbone.sync.restore()


  ###
              +++++ ONLINE +++++
  ###
  describe 'Online', ->
    beforeEach ->
      serverAutoRespondOk()

    describe 'Cache wipe', ->
      it 'should clean the cache but preserve protected keys', (done) ->
        mnemosyne = new Mnemosyne({protectedKeys: ['key1', 'key2', 'key3']})
        $.when(
          mnemosyne.cacheWrite('key1', 'some random text'),
          mnemosyne.cacheWrite('key2', 'some random text'),
          mnemosyne.cacheWrite('key3', 'some random text'),
          mnemosyne.cacheWrite('key4', 'some random text'),
          mnemosyne.cacheWrite('key5', 'some random text')
        ).done ->
          mnemosyne.cacheClear().done ->
            mnemosyne.cacheRead('key1').done (value) ->
              expect(value).to.exists
              mnemosyne.cacheRead('key5').fail ->
                done()


    describe 'Cache invalidation', ->

      it 'should create the collection cache', (done) ->
        mnemosyne.cacheRead(collection).fail ->
          model.fetch().done ->
            mnemosyne.cacheRead(collection).done (value)->
              expect(value.length).equals(1)
              done()

      it 'should update the collection cache', (done) ->
        model.setName("defaultName")
        collection.push(model)
        mnemosyne.cacheWrite(collection).done ->
          mnemosyne.cacheRead(collection).done (value) ->
            expect(value[0].name).equals("defaultName")
            model.fetch().done ->
              mnemosyne.cacheRead(collection).done (value) ->
                expect(value[0].name).equals("serverModel1")
                done()

      it 'should remove the model from the collection cache when model is destroyed', (done) ->
        model.setName("defaultName")
        collection.push(model)
        mnemosyne.cacheWrite(collection).done ->
          mnemosyne.cacheRead(collection).done (value) ->
            expect(value[0].name).equals("defaultName")
            model.destroy().done ->
              mnemosyne.cacheRead(collection).done (value) ->
                expect(value).to.be.empty
                done()

      it 'should apply filter on parent collections', (done) ->
        shouldBeInParentCollection = true
        model.getParentKeys = ->
          [
            {key: 'parentKey1', filter: -> shouldBeInParentCollection}
            {key: 'parentKey2', filter: -> shouldBeInParentCollection}
          ]
        model.save().done ->
          mnemosyne.cacheRead('parentKey1').done (value)->
            expect(value.length).to.equal(1)
            mnemosyne.cacheRead('parentKey2').done (value)->
              expect(value.length).to.equal(1)
              shouldBeInParentCollection = false
              model.save().done ->
                mnemosyne.cacheRead('parentKey1').done (value)->
                  expect(value.length).to.be.empty
                  mnemosyne.cacheRead('parentKey2').done (value)->
                    expect(value.length).to.be.empty
                    done()

    describe 'Read value', ->
      it 'should trigger "syncing" event on model', (done) ->
        model.cache = {enabled : true}
        model.on "syncing", -> done()
        model.fetch()

      it 'should trigger "syncing" event on collection', (done) ->
        collection.cache = {enabled : true}
        collection.on "syncing", -> done()
        collection.fetch()

      it 'should write the collection in cache', (done) ->
        collection.push(model2)
        collection.push(model)
        mnemosyne.cacheWrite(collection)
        .done ->
          mnemosyne.cacheRead(collection)
          .done (value) ->
            expect(value.length).equals(2)
            done()


      it 'should update the collection', (done) ->
        mnemosyne.cacheWrite(collection).done ->
          mnemosyne.cacheRead(collection).done (value) ->
            expect(value).to.be.empty
            collection.push(model)
            mnemosyne.cacheWrite(collection).done ->
              model.setName("myName")
              mnemosyne.cacheWrite(model).done ->
                mnemosyne.cacheRead(collection).done (value) ->
                  expect(value[0].name).equals("myName")
                  done()

      it 'should create parent collection cache', (done) ->
        mnemosyne.cacheRead(collection).fail ->
          mnemosyne.cacheRead(collection2).fail ->
            model.save().done ->
              mnemosyne.cacheRead(collection).done (value) ->
                expect(value[0].name).to.equal("serverModel1")
                mnemosyne.cacheRead(collection2).done (value) ->
                  expect(value[0]).to.not.be.empty
                  done()

      it 'should update all parent Collection', (done) ->
        model.setName('cacheName')
        mnemosyne.cacheWrite(model).done ->
          mnemosyne.cacheRead(collection).done (value) ->
            expect(value[0].name).to.equal('cacheName')
            mnemosyne.cacheRead(collection2).done (value) ->
              expect(value[0].name).to.equal('cacheName')
              model.save().done ->
                mnemosyne.cacheRead(collection).done (value) ->
                  expect(value[0].name).to.equal('serverModel1')
                  mnemosyne.cacheRead(collection2).done (value) ->
                    expect(value[0].name).to.equal('serverModel1')
                    done()

      it 'should add the model to the cache of the parent collection', (done) ->
        collection.push(model)
        mnemosyne.cacheWrite(collection).done ->
          mnemosyne.cacheRead(collection)
          .done (value) ->
            expect(value.length).equals(1)
            model2.save()
            .done ->
              mnemosyne.cacheRead(collection)
              .done (value) ->
                expect(value.length).equals(2)
                done()


      ###
                  READ - ONLINE - CACHE VALID
      ###
      describe 'Cache valid', ->
        beforeEach (done) ->
          model.cache = {enabled : true}
          collection.cache = {enabled :true}
          model.setName("cacheModel")
          mnemosyne.cacheWrite(model)
          .done -> done()

        it 'should trigger "synced" event on model', (done) ->
          model.on "synced", -> done()
          model.fetch()

        it 'should trigger "synced" event on collection', (done) ->
          collection.on "synced", -> done()
          collection.fetch()

        it 'should get data from server when fetching model', (done) ->
          model.setName("defaultName")
          model.fetch()
          .done ->
            expect(model.getName()).to.be.equal("serverModel1")
            done()

        it 'should get data from server when fetching collection', (done) ->
          model.setName(17)
          collection.push(model)
          collection.push(model2)
          mnemosyne.cacheWrite(collection).done ->
            collection = new CustomCollection()
            collection.cache = {enabled :true}
            expect(collection.models).to.be.empty
            collection.fetch().done ->
              expect(collection.get(1).getName()).equals("serverModel1")
              done()

        it 'should not read cache when fetching model'

        it 'should not read cache when fetching collection'


        ###
                    READ - ONLINE - CACHE VALID - "forceRefresh: true"
        ###
        describe '"forceRefresh" set to true', ->
          beforeEach (done) ->
            server.autoRespond = true
            model.setName("defaultName")
            mnemosyne.cacheWrite(model)
            .done -> done()

          it 'should get data from server when fetching model', (done) ->
            model.fetch(forceRefresh: true).done ->
              expect(serverSpy).to.have.been.called
              expect(model.getName()).equals("serverModel1")
              done()

          it 'should get data from server when fetching collection', (done) ->
            collection.fetch(forceRefresh: true).done ->
              expect(collection.get(1).getName()).equals("serverModel1")
              done()


          it 'should update the cache value when fetching the model', (done) ->
            model.fetch(forceRefresh: true).done ->
              expect(model.getName()).equals("serverModel1")
              mnemosyne.cacheRead(model).done (value) ->
                expect(value.name).equals("serverModel1")
                done()

          it 'should update the cache value when fetching the collection', (done) ->
            collection.fetch(forceRefresh: true).done ->
              expect(collection.get(1).getName()).equals("serverModel1")
              mnemosyne.cacheRead(collection).done (value) ->
                expect(value[0].name).equals("serverModel1")
                done()


      ###
                  READ - ONLINE - CACHE DISABLED
      ###
      describe 'Cache disabled', ->
        beforeEach (done) ->
          model.setName("defaultName")
          mnemosyne.cacheWrite(model)
          .done ->
            model.cache = {enabled : false}
            done()

        it 'should trigger "synced" event on model', (done) ->
          model.on "synced", -> done()
          model.fetch()

        it 'should get data from server', (done) ->
          expect(model.getName()).to.equals("defaultName")
          model.fetch()
          .done ->
            expect(model.getName()).to.equals("serverModel1")
            done()


    describe 'Write value', ->
      it 'should trigger "syncing" event on model', (done) ->
        model.on "syncing", -> done()
        model.save()


      ###
                  WRITE - ONLINE - CACHE
      ###
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
          model.setName("customName")
          mnemosyne.cacheWrite(model)
          .done ->
            model.fetch()
            .done ->
              mnemosyne.cacheRead(model)
              .done (value) ->
                expect(value).to.not.equal("customName")
                done()

      ###
                  WRITE - ONLINE - NO CACHE
      ###
      describe 'No cache', ->
        beforeEach (done) ->
          mnemosyne.cacheRead(model).fail ->
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
          model.setName("defaultName")
          model.save()
          .done ->
            mnemosyne.cacheRead(model)
            .always (value) ->
              expect(value).to.not.exists
              done()




  ###
              +++++ OFFLINE +++++
  ###
  describe 'Offline', ->
    before ->
      online = false
      serverSetOffline()

    after ->
      serverSetOnline()
      
    describe 'Cache invalidation', ->

      it 'should trigger "syncing" event on model', (done) ->
        completed = false
        model.on 'syncing', -> completed = true
        model.save().always ->
          expect(completed).to.be.true
          done()

      it 'should remove the model from the cache of all parent collection', (done) ->
        model.setName('offline model')

        model.save().done ->
          mnemosyne.cacheRead(collection).done (value) ->
            expect(value).to.be.not.empty
            mnemosyne.cacheRead(collection2).done (value) ->
              expect(value).to.be.not.empty
              model.on 'pending', ->
                mnemosyne.cacheRead(collection).done (value) ->
                  expect(value).to.be.empty
                  mnemosyne.cacheRead(collection2).done (value) ->
                    expect(value).to.be.empty
                    done()

              model.destroy()


    describe 'Read value', ->
      ###
                  READ - OFFLINE - CACHE VALID
      ###
      describe 'Cache valid', ->
        beforeEach (done) ->
          model.cache = {enabled : true}
          collection.cache = {enabled :true}
          model.setName("cacheModel")
          mnemosyne.cacheWrite(model)
          .done -> done()

        it 'should trigger "synced" event on model', (done) ->
          model.on 'synced', -> done()
          model.fetch()

        it 'should trigger "synced" event on collection', (done) ->
          collection.on 'synced', -> done()
          collection.fetch()

        it 'should get data from cache when fetching model', (done) ->
          model.setName("")
          model.fetch()
          .done ->
            expect(model.getName()).to.equal("cacheModel")
            done()

        it 'should get data from cache when fetching collection', (done) ->
          collection.reset([])
          expect(collection.models).to.be.empty
          collection.fetch()
          .done ->
            expect(collection.models.length).to.equal(1)
            done()

        it 'should not try to get data from server when fetching model', (done) ->
          model.fetch()
          .done ->
            expect(serverSpy).not.called
            done()

        it 'should not try to get data from server when fetching collection', (done) ->
          collection.fetch()
          .done ->
            expect(serverSpy).not.called
            done()

      ###
                  READ - OFFLINE - NO CACHE
      ###
      describe 'No cache', ->
        beforeEach (done) ->
          mnemosyne.cacheRead(model).fail ->
            model.cache = {enabled : false}
            mnemosyne.cacheRead(collection).fail ->
              collection.cache = {enabled: false}
              done()

        it 'should trigger "unsynced" event on model', (done) ->
          model.on 'unsynced', -> done()
          model.fetch()

        it 'should trigger "unsynced" event on collection', (done) ->
          collection.on 'unsynced', -> done()
          collection.fetch()

        it 'should fail when fetching model', (done) ->
          model.setName("noName")
          model.fetch()
          .fail ->
            expect(model.getName()).equal("noName")
            done()

        it 'should fail when fetching collection', (done) ->
          collection.reset([model,model2])
          collection.fetch()
          .fail ->
            expect(collection.models.length).equal(2)
            done()

    describe 'Write value', ->
      ###
                  WRITE - OFFLINE - CACHE
      ###
      describe 'Cache', ->
        it 'should trigger "pending" event on model', (done)->
          model.on 'pending', -> done()
          model.save()

        it 'should write the data in cache when saving a model with an id', (done) ->
          model.setName("awesome")
          model.save().done ->
            mnemosyne.cacheRead(model).done (value) ->
              expect(value.name).to.equal("awesome")
              done()

        it 'should push the request in the queue', (done) ->
          model2.save().done ->
            model.save().done ->
              expect(mnemosyne.getPendingRequests().length).to.equal(2)
              done()

      ###
                  WRITE - OFFLINE - CACHE disabled
      ###
      describe 'Cache disabled', ->
        beforeEach (done) ->
          mnemosyne.cacheRead(model).fail ->
            model.cache = {enabled : false}
            mnemosyne.cacheRead(collection).fail ->
              collection.cache = {enabled: false}
              done()

        it 'should trigger "unsynced" event on model', (done) ->
          model.on 'unsynced', -> done()
          model.save()

        it 'should fail when saving a model', (done) ->
          model.setName("noCache")
          deferred = model.save()
          deferred.always ->
            expect(deferred.state()).to.equal('rejected')
            done()

        it 'should not write the data in cache', (done) ->
          model.setName("noCache")
          model.save().fail ->
            mnemosyne.cacheRead(model).fail ->
              done()


      describe 'On connection recovered', ->
        it 'should trigger "synced" event on model'
        it 'should write the data in cache and set the state to synced'
