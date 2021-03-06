require.config
  paths:
    'chai'         : '../components/chai/chai'
    'sinon-chai'   : '../components/sinon-chai/lib/sinon-chai'
    'sinon'        : '../node_modules/sinon/pkg/sinon-1.10.0'
    'jquery'       : '../components/jquery/dist/jquery'
    'underscore'   : '../components/underscore/underscore'
    'backbone'     : '../components/backbone/backbone'
    'mnemosyne'    : '../app/mnemosyne'
  shim:
    'sinon':
      exports: "sinon"

files = [
  'jquery'
  'chai'
  'sinon-chai'
  'sinon'
  'backbone'
  'mnemosyne'
]


`var main_node = // main_node_var_here`

get_files = (path, node) ->
  out = []
  new_path = path + node.name + '/'
  out.push new_path + file for file in node.files
  for directory in node.directories
    out = out.concat get_files(new_path, directory)
  return out
specs = get_files '', main_node

capitalize = (s) ->
  s.charAt(0).toUpperCase() + s[1...]

get_requires = (path, node, is_base = false) -> ->
  new_path = path + node.name + '/'
  name = if is_base then "" else capitalize node.name
  describe name, ->
    for file in node.files
      require(new_path + file)
    for directory in node.directories
      get_requires(new_path, directory)()


require files, ->
  chai = require("chai")
  sinonChai = require("sinon-chai")

  # chai.should()
  window.expect = chai.expect
  chai.use(sinonChai);
  mocha.setup
    globals: ['sinon']

  require specs, ->
    describe '', ->
      before (done) ->
        xhr = sinon.useFakeXMLHttpRequest()
        xhr.onCreate = (request) =>
          request.respondHelper = (status, data) ->
            request.respond(
              status
              {"Content-Type": "application/json"}
              JSON.stringify data)
          @requests.push(request)

        require ['mnemosyne'], (mnemosyne) =>
          @mnemosyne = mnemosyne
          done()

      beforeEach ->
        @requests = []

      get_requires('', main_node, true)()

    mocha.run()
