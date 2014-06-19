module.exports = describe 'Mnemosyne specifications', ->

  server = null
  model  = null
  model2 = null
  newModel = null
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
      switch xhr.url
        when '/model'
          xhr.respond(
            statusCode
            "Content-Type": "application/json"
            '{"id": 1, "name":"serverModel1"}'
          )
        when '/collection'
          xhr.respond(
            statusCode
            "Content-Type": "application/json"
            '[{"id": 1, "name":"serverModel1"}, {"id": 2, "name":"serverModel2"}]'
          )


  before ->
    mnemosyne = new Mnemosyne()

    class CustomModel extends Backbone.Model
      cache:
        enabled: true

      constructor: ->
        super

      getKey: -> 'modelKey'
      getParentKey: -> 'parentKey'
      getName: -> @get('name')
      setName: (value) -> @set('name', value)
      url: -> '/model'

    class CustomCollection extends Backbone.Collection
      model: CustomModel
      cache:
        enabled: true
      getKey: -> 'parentKey'
      url: -> '/collection'


  beforeEach ->
    localStorage.clear()
    mnemosyne = null
    mnemosyne = new Mnemosyne()
    serverSpy = sinon.spy()
    server = sinon.fakeServer.create()
    model = new CustomModel(id:1)
    model2 = new CustomModel(id:2)
    model2.getKey = -> 'modelKey2'
    newModel = new CustomModel()
    newModel.getKey = -> 'newModelKey'
    collection = new CustomCollection()
    mnemosyne.clear()



  afterEach ->
    server.restore()
    mnemosyne.clear()


  serverAutoRespondError = ->
    server.autoRespond = true

  serverAutoRespondOk = ->
    setUpServerResponse()
    server.autoRespond = true


  ###
              +++++ ONLINE +++++
  ###
  describe 'Online', ->
    beforeEach ->
      serverAutoRespondOk()

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
        mnemosyne.cacheWrite(collection)
        .done ->
          mnemosyne.cacheRead(collection)
          .done (value) ->
            expect(value).to.be.empty
            collection.push(model)
            mnemosyne.cacheWrite(collection).done ->
              model.setName(256)
              mnemosyne.cacheWrite(model)
              .done ->
                mnemosyne.cacheRead(collection)
                .done (value) ->
                  expect(value[0].name).equals(256)
                  done()

      it 'should add the model to the cache of the parent collection if the model is not new', (done) ->
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
          model.cache = {enabled : true, ttl: 600}
          collection.cache = {enabled :true, ttl: 600}
          model.setName("cacheModel")
          mnemosyne.cacheWrite(model)
          .done -> done()

        it 'should trigger "synced" event on model', (done) ->
          model.on "synced", -> done()
          model.fetch()

        it 'should trigger "synced" event on collection', (done) ->
          collection.on "synced", -> done()
          collection.fetch()

        it 'should get data from cache when fetching model', (done) ->
          model.setName("defaultName")
          model.fetch()
          .done ->
            expect(model.getName()).to.be.equal("cacheModel")
            done()

        it 'should get data from cache when fetching collection', (done) ->
          model.setName(17)
          collection.push(model)
          collection.push(model2)
          mnemosyne.cacheWrite(collection).done ->
            collection = new CustomCollection()
            collection.cache = {enabled :true, ttl: 600}
            expect(collection.models).to.be.empty
            collection.fetch().done ->
              expect(collection.get(1).getName()).equals(17)
              done()

        it 'should not call server when fetching model', (done) ->
          server.autoRespond = true
          model.on "synced", ->
            expect(serverSpy).to.not.have.been.called
            done()
          model.fetch()

        it 'should not call server when fetching collection', (done) ->
          server.autoRespond = true
          collection.on "synced", ->
            expect(serverSpy).to.not.have.been.called
            done()
          collection.fetch()


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
                  READ - ONLINE - CACHE EXPIRED
      ###
      describe 'Cache expired', ->
        beforeEach (done) ->
          model.cache = {enabled : true, ttl: 0}
          collection.cache = {enabled : true, ttl: 0}
          model.setName("defaultName")
          mnemosyne.cacheWrite(model).done -> done()

        it 'should trigger "synced" event on model', (done) ->
          model.on "synced", -> done()
          model.fetch()

        it 'should trigger "synced" event on collection', (done) ->
          collection.on "synced", -> done()
          collection.fetch()

        it 'should get data from cache when fetching model', (done) ->
          model.setName("")
          model.fetch().done ->
            expect(model.getName()).equals("defaultName")
            done()

        it 'should get data from cache when fetching collection', (done) ->
          collection.fetch().done ->
            expect(collection.get(1).getName()).equals("defaultName")
            done()

        it 'should get data from cache, and after, update it with server data'

        ###
                    READ - ONLINE - CACHE EXPIRED - "allowExpiredCache : true"
        ###
        describe '"allowExpiredCache" set to false', ->
          beforeEach ->
            model.cache.allowExpiredCache = false
            collection.cache.allowExpiredCache = false

          it 'should trigger "synced" event on model', (done) ->
            model.on "synced", ->
              done()
            model.fetch()

          it 'should trigger "synced" event on collection', (done) ->
            collection.on "synced", ->
              done()
            collection.fetch()

          it 'should not use data from cache when fetching model', (done) ->
            model.fetch()
            .done ->
              expect(model.getName()).equals("serverModel1")
              done()

          it 'should not use data from cache when fetching collection', (done) ->
            collection.fetch()
            .done ->
              expect(collection.get(1).getName()).equals("serverModel1")
              done()

          it 'should write back server data in cache when fetching model', (done) ->
            model.setName("")
            mnemosyne.cacheWrite(model).done ->
              model.fetch().done ->
                mnemosyne.cacheRead(model).done (value) ->
                  expect(value.name).to.equals("serverModel1")
                  done()

          it 'should write back server data in cache when fetching collection', (done) ->
            collection.reset([])
            mnemosyne.cacheWrite(collection).done ->
              mnemosyne.cacheRead(collection).done (value) ->
                expect(value).be.empty
                collection.fetch().done ->
                  mnemosyne.cacheRead(collection).done (value) ->
                    expect(value).not.be.empty
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
    beforeEach ->
      serverAutoRespondError()

    describe 'Cache invalidation', ->

      it 'should remove the model from pendings models'
        # expect(mnemosyne._offlineModels).to.be.empty
        # pending = false
        # newModel.on 'pending', ->
        #   expect(mnemosyne._offlineModels).not.be.empty
        #   pending = true
        #   serverAutoRespondOk()
        #
        # newModel.on 'synced', ->
        #   expect(pending).to.be.true
        #   expect(mnemosyne._offlineModels).to.be.empty
        #   done()
        #
        # newModel.setName('defaultName')
        # newModel.save()

      it 'should add the new model to offlineModels', (done) ->
        newModel.on 'pending', ->
          expect(mnemosyne._offlineModels.length).equals(1)
          done()

        newModel.save()

      it 'should add the new model to offlineCollections', (done) ->
        mnemosyne.clear()
        newModel.on 'pending', ->
          expect(mnemosyne._offlineCollections[newModel.getParentKey()].length).equals(1)
          done()

        newModel.save()

      it 'should add the pending model to the fetched collection', (done) ->
        expect(collection.models).to.be.empty
        mnemosyne._offlineCollections[collection.getKey()] = [newModel]
        collection.fetch().always ->
          expect(collection.models).not.be.empty
          done()

    it 'should trigger "syncing" event on model', (done) ->
      model.on 'syncing', -> done()
      model.save()


    describe 'Read value', ->
      ###
                  READ - OFFLINE - CACHE VALID
      ###
      describe 'Cache valid', ->
        beforeEach (done) ->
          model.cache = {enabled : true, ttl: 600}
          collection.cache = {enabled :true, ttl: 600}
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
                  READ - OFFLINE - CACHE EXPIRED
      ###
      describe 'Cache expired', ->
        beforeEach (done) ->
          model.cache = {enabled : true, ttl: 0}
          collection.cache = {enabled :true, ttl: 0}
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
            expect(model.getName()).equal("cacheModel")
            done()

        it 'should get data from cache when fetching collection', (done) ->
          collection.reset([])
          collection.fetch()
          .done ->
            expect(collection.models.length).to.equal(1)
            done()


        ###
                    READ - OFFLINE - CACHE EXPIRED - "allowExpiredCache : false"
        ###
        describe '"allowExpiredCache" set to false', ->
          beforeEach ->
            model.cache.allowExpiredCache = false
            collection.cache.allowExpiredCache = false

          it 'should trigger "unsynced" event on model', (done) ->
            model.on "unsynced", -> done()
            model.fetch()

          it 'should trigger "unsynced" event on collection', (done) ->
            collection.on "unsynced", -> done()
            collection.fetch()

          it 'should not use data from cache when fetching model and fail', (done) ->
            model.setName("noName")
            model.fetch()
            .fail ->
              expect(model.getName()).equal("noName")
              done()

          it 'should not use data from cache when fetching collection and fail', (done) ->
            collection.reset([model])
            collection.fetch()
            .fail ->
              expect(collection.models.length).equal(1)
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

        it 'should not write the data in cache when saving a model without an id', (done) ->
          newModel.setName("noCache")
          newModel.save().done ->
            mnemosyne.cacheRead(newModel).fail ->
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
