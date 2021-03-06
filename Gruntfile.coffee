# Credits https://github.com/dfournier/plasticine/blob/master/Gruntfile.coffee


"use strict"
module.exports = (grunt) ->

  # Project configuration.
  grunt.initConfig

    # Metadata.
    pkg: grunt.file.readJSON("package.json")

    dir:
      source : 'source/'
      bower  : 'components/'
      tmp    : '.tmp/'


    # Task configuration.
    clean:
      tmp  : ["<%= dir.tmp %>"]
      dist : ["dist"]

    copy:
      source:
        files: [
          expand: true
          cwd: "<%= dir.source %>"
          src: ['**', '!**/*.coffee']
          dest: "<%= dir.tmp %>"
        ]
      components:
        files: [
          expand: true
          cwd: "<%= dir.bower %>"
          src: ['**']
          dest: "<%= dir.tmp %><%= dir.bower %>"
        ]

    coffee:
      compile:
        options:
          bare      : true
          sourceMap : false
        expand : true
        cwd    : "<%= dir.source %>"
        src    : ['**/*.coffee']
        dest   : "<%= dir.tmp %>"
        ext    : '.js'

    amdwrap:
      compile:
        expand : true
        cwd    : "<%= dir.tmp %>"
        src    : ['app/**/*.js', 'test/spec/**/*.js']
        dest   : "<%= dir.tmp %>"

    wrap:
      dist:
        expand: true
        cwd: "dist/"
        src: ["**"]
        dest: "dist/"
        options:
          wrapper: [
            """
            (function (root, factory) {
              if (typeof define === 'function' && define.amd) {
                // AMD. Register as an anonymous module.
                define(['b'], factory);
              } else {
                // Browser globals
                root.Mnemosyne = factory(root.b);
              }
            }(this, function (b) {
            """
            """
              return require('mnemosyne');
            }));
            """]

    process:
      testInit:
        options:
          base64: false
          processors: [
            pattern: '// main_node_var_here'
            setup: (grunt) ->
              fs = require 'fs'
              getFiles = (dir) ->

                node =
                  name: dir.split('/').pop()
                  files: []
                  directories: []
                files = fs.readdirSync(dir)
                for file in files
                  name = dir + '/' + file
                  if fs.statSync(name).isDirectory()
                    node.directories.push getFiles(name)
                  else
                    if (/\.coffee$/).test(file)
                      node.files.push file.replace /\.coffee$/, ''
                return node

              main_node = getFiles("#{grunt.config.get('dir.source')}test/spec")
              return main_node: main_node

            handler: (context) ->
              return JSON.stringify context.main_node
          ]
        files: [
          expand: true
          cwd: "<%= dir.tmp %>test/"
          src: "config.js"
          dest: "<%= dir.tmp %>test/"
        ]

    mocha:
      all: ["<%= dir.tmp %>test/index.html"]
      options:
        reporter : 'Progress'
        run      : false
        log: true
        logErrors: true

    watch:
      options:
        livereload: true
        spawn: false
        cwd  : "<%= dir.source %>"
      coffeeFileModified:
        files: "**/*.coffee"
        tasks: ["coffee", "amdwrap", "process", "mocha"]
        options:
          event: ['added', 'changed']
      coffeeFileDeleted:
        files: "**/*.coffee"
        tasks: ["clean:tmp", "coffee", "process", "mocha"]
        options:
          event: ['deleted']

    requirejs:
      compile:
        options:
          mainConfigFile: "<%= dir.tmp %>app/main.js"
          out: "dist/mnemosyne.js"
          optimize: 'none'
          cjsTranslate: true
          exclude: ['backbone']

    usebanner:
      dist:
        options:
          position: 'top'
          linebreak: true
          banner:
            """
            /*!
             * Mnemosyne JavaScript Library v0.0.1
             */
             """
        files:
          src: "dist/mnemosyne.js"

    "git-describe":
      dist: {}

    connect:
      development:
        options:
          open: 'http://0.0.0.0:8000/test'
          base: ["./", "<%= dir.tmp %>"]


  grunt.loadNpmTasks "grunt-contrib-clean"
  grunt.loadNpmTasks "grunt-mocha"
  grunt.loadNpmTasks "grunt-contrib-watch"
  grunt.loadNpmTasks "grunt-contrib-connect"
  grunt.loadNpmTasks "grunt-contrib-copy"
  grunt.loadNpmTasks "grunt-contrib-coffee"
  grunt.loadNpmTasks "grunt-amd-wrap"
  grunt.loadNpmTasks "grunt-renaming-wrap"
  grunt.loadNpmTasks 'grunt-file-process'
  grunt.loadNpmTasks "grunt-contrib-requirejs"
  grunt.loadNpmTasks "grunt-git-describe"
  grunt.loadNpmTasks "grunt-banner"

  grunt.event.on 'watch', (action, filepath, target) ->
    coffee_files = []
    process_files_conf = grunt.config.get("process.testInit.files")
    process_files_conf[0].src = ''
    compile_config = ->
      coffee_files.push 'test/config.coffee'
      process_files_conf[0].src = 'config.js'

    coffee_task = 'coffee.compile'
    root_path = grunt.config.get("#{coffee_task}.cwd")
    relative_path = filepath.replace(new RegExp("^#{root_path}"), '')
    ext = grunt.config.get("#{coffee_task}.ext")
    relative_compiled_path = relative_path.replace(/.coffee$/, ext)
    compiled_file = grunt.config.get('dir.tmp') + relative_compiled_path

    if target is 'coffeeFileModified'
      coffee_files.push relative_path
      grunt.config("amdwrap.compile.src", relative_compiled_path)

      # recompile test/config.coffee if a new file is added in test/spec folder
      if action is 'added' and (/^test\/spec\//).test relative_path
        compile_config()

    if target is 'coffeeFileDeleted'
      grunt.config('clean.tmp', compiled_file)
      compile_config() if (/^test\/spec\//).test relative_path

    grunt.config("#{coffee_task}.src", coffee_files)
    grunt.config("process.testInit.files", process_files_conf)


  grunt.registerTask 'setRevision', ->
    grunt.event.once 'git-describe', -> grunt.option('gitRevision', rev)
    grunt.task.run('git-describe')

  grunt.registerTask "compileTest", ["amdwrap", "process"]

  grunt.registerTask "default", ["test"]
  grunt.registerTask "compile", ["clean:tmp", "coffee", "copy"]
  grunt.registerTask "build", ["clean:dist", "compile", "requirejs", "wrap:dist", "usebanner"]

  grunt.registerTask "start", ["compile", "compileTest", "watch"]
  grunt.registerTask "start:browser", ["connect:development", "start"]

  grunt.registerTask "test", ["compile", "compileTest", "mocha"]
