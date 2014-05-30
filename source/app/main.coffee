require.config
  name: 'mnemosyne'
  paths:
    'backbone'    : '../components/backbone/backbone'
    'underscore'  : '../components/underscore/underscore'
    'jquery'      : '../components/jquery/dist/jquery'
  shim:
    'backbone' :
      deps: ['underscore', 'jquery']
      exports:['Backone']

    'underscore':
      exports: '_'
