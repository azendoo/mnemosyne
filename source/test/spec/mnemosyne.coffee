describe 'Mnemosyne specifications', ->

  beforeEach: ->
    mnemosyne = new Mnemosyne()

    model1 = new Backbone.model()
    model1.getKey = -> 'model.1'
    model2 = new Backbone.model()
    model2.getKey = -> 'model.2'
    model3 = new Backbone.model()
    model3.getKey = -> 'model.3'


  it 'should be ok', (done) ->
    done()

  it 'should clear all requests'

#  describe 'Online', ->
#    describe 'Read value'
#      describe 'Cache' ->
#      describe 'No cache' ->
#
#    describe 'Write value' ->
#      describe 'Cache' ->
#      describe 'No cache' ->
#
#  describe 'Offline', ->
#    describe 'Read value' ->
#      describe 'Cache' ->
#      describe 'No cache' ->
#
#    describe 'Write value' ->
#      describe 'Cache' ->
#      describe 'No cache' ->
