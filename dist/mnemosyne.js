/*!
 * Mnemosyne JavaScript Library v0.0.1
 */
(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
    // AMD. Register as an anonymous module.
    define(['b'], factory);
  } else {
    // Browser globals
    root.Mnemosyne = factory(root.b);
  }
}(this, function (b) {
/**
 * @license almond 0.2.9 Copyright (c) 2011-2014, The Dojo Foundation All Rights Reserved.
 * Available via the MIT or new BSD license.
 * see: http://github.com/jrburke/almond for details
 */
//Going sloppy to avoid 'use strict' string cost, but strict practices should
//be followed.
/*jslint sloppy: true */
/*global setTimeout: false */

var requirejs, require, define;
(function (undef) {
    var main, req, makeMap, handlers,
        defined = {},
        waiting = {},
        config = {},
        defining = {},
        hasOwn = Object.prototype.hasOwnProperty,
        aps = [].slice,
        jsSuffixRegExp = /\.js$/;

    function hasProp(obj, prop) {
        return hasOwn.call(obj, prop);
    }

    /**
     * Given a relative module name, like ./something, normalize it to
     * a real name that can be mapped to a path.
     * @param {String} name the relative name
     * @param {String} baseName a real name that the name arg is relative
     * to.
     * @returns {String} normalized name
     */
    function normalize(name, baseName) {
        var nameParts, nameSegment, mapValue, foundMap, lastIndex,
            foundI, foundStarMap, starI, i, j, part,
            baseParts = baseName && baseName.split("/"),
            map = config.map,
            starMap = (map && map['*']) || {};

        //Adjust any relative paths.
        if (name && name.charAt(0) === ".") {
            //If have a base name, try to normalize against it,
            //otherwise, assume it is a top-level require that will
            //be relative to baseUrl in the end.
            if (baseName) {
                //Convert baseName to array, and lop off the last part,
                //so that . matches that "directory" and not name of the baseName's
                //module. For instance, baseName of "one/two/three", maps to
                //"one/two/three.js", but we want the directory, "one/two" for
                //this normalization.
                baseParts = baseParts.slice(0, baseParts.length - 1);
                name = name.split('/');
                lastIndex = name.length - 1;

                // Node .js allowance:
                if (config.nodeIdCompat && jsSuffixRegExp.test(name[lastIndex])) {
                    name[lastIndex] = name[lastIndex].replace(jsSuffixRegExp, '');
                }

                name = baseParts.concat(name);

                //start trimDots
                for (i = 0; i < name.length; i += 1) {
                    part = name[i];
                    if (part === ".") {
                        name.splice(i, 1);
                        i -= 1;
                    } else if (part === "..") {
                        if (i === 1 && (name[2] === '..' || name[0] === '..')) {
                            //End of the line. Keep at least one non-dot
                            //path segment at the front so it can be mapped
                            //correctly to disk. Otherwise, there is likely
                            //no path mapping for a path starting with '..'.
                            //This can still fail, but catches the most reasonable
                            //uses of ..
                            break;
                        } else if (i > 0) {
                            name.splice(i - 1, 2);
                            i -= 2;
                        }
                    }
                }
                //end trimDots

                name = name.join("/");
            } else if (name.indexOf('./') === 0) {
                // No baseName, so this is ID is resolved relative
                // to baseUrl, pull off the leading dot.
                name = name.substring(2);
            }
        }

        //Apply map config if available.
        if ((baseParts || starMap) && map) {
            nameParts = name.split('/');

            for (i = nameParts.length; i > 0; i -= 1) {
                nameSegment = nameParts.slice(0, i).join("/");

                if (baseParts) {
                    //Find the longest baseName segment match in the config.
                    //So, do joins on the biggest to smallest lengths of baseParts.
                    for (j = baseParts.length; j > 0; j -= 1) {
                        mapValue = map[baseParts.slice(0, j).join('/')];

                        //baseName segment has  config, find if it has one for
                        //this name.
                        if (mapValue) {
                            mapValue = mapValue[nameSegment];
                            if (mapValue) {
                                //Match, update name to the new value.
                                foundMap = mapValue;
                                foundI = i;
                                break;
                            }
                        }
                    }
                }

                if (foundMap) {
                    break;
                }

                //Check for a star map match, but just hold on to it,
                //if there is a shorter segment match later in a matching
                //config, then favor over this star map.
                if (!foundStarMap && starMap && starMap[nameSegment]) {
                    foundStarMap = starMap[nameSegment];
                    starI = i;
                }
            }

            if (!foundMap && foundStarMap) {
                foundMap = foundStarMap;
                foundI = starI;
            }

            if (foundMap) {
                nameParts.splice(0, foundI, foundMap);
                name = nameParts.join('/');
            }
        }

        return name;
    }

    function makeRequire(relName, forceSync) {
        return function () {
            //A version of a require function that passes a moduleName
            //value for items that may need to
            //look up paths relative to the moduleName
            return req.apply(undef, aps.call(arguments, 0).concat([relName, forceSync]));
        };
    }

    function makeNormalize(relName) {
        return function (name) {
            return normalize(name, relName);
        };
    }

    function makeLoad(depName) {
        return function (value) {
            defined[depName] = value;
        };
    }

    function callDep(name) {
        if (hasProp(waiting, name)) {
            var args = waiting[name];
            delete waiting[name];
            defining[name] = true;
            main.apply(undef, args);
        }

        if (!hasProp(defined, name) && !hasProp(defining, name)) {
            throw new Error('No ' + name);
        }
        return defined[name];
    }

    //Turns a plugin!resource to [plugin, resource]
    //with the plugin being undefined if the name
    //did not have a plugin prefix.
    function splitPrefix(name) {
        var prefix,
            index = name ? name.indexOf('!') : -1;
        if (index > -1) {
            prefix = name.substring(0, index);
            name = name.substring(index + 1, name.length);
        }
        return [prefix, name];
    }

    /**
     * Makes a name map, normalizing the name, and using a plugin
     * for normalization if necessary. Grabs a ref to plugin
     * too, as an optimization.
     */
    makeMap = function (name, relName) {
        var plugin,
            parts = splitPrefix(name),
            prefix = parts[0];

        name = parts[1];

        if (prefix) {
            prefix = normalize(prefix, relName);
            plugin = callDep(prefix);
        }

        //Normalize according
        if (prefix) {
            if (plugin && plugin.normalize) {
                name = plugin.normalize(name, makeNormalize(relName));
            } else {
                name = normalize(name, relName);
            }
        } else {
            name = normalize(name, relName);
            parts = splitPrefix(name);
            prefix = parts[0];
            name = parts[1];
            if (prefix) {
                plugin = callDep(prefix);
            }
        }

        //Using ridiculous property names for space reasons
        return {
            f: prefix ? prefix + '!' + name : name, //fullName
            n: name,
            pr: prefix,
            p: plugin
        };
    };

    function makeConfig(name) {
        return function () {
            return (config && config.config && config.config[name]) || {};
        };
    }

    handlers = {
        require: function (name) {
            return makeRequire(name);
        },
        exports: function (name) {
            var e = defined[name];
            if (typeof e !== 'undefined') {
                return e;
            } else {
                return (defined[name] = {});
            }
        },
        module: function (name) {
            return {
                id: name,
                uri: '',
                exports: defined[name],
                config: makeConfig(name)
            };
        }
    };

    main = function (name, deps, callback, relName) {
        var cjsModule, depName, ret, map, i,
            args = [],
            callbackType = typeof callback,
            usingExports;

        //Use name if no relName
        relName = relName || name;

        //Call the callback to define the module, if necessary.
        if (callbackType === 'undefined' || callbackType === 'function') {
            //Pull out the defined dependencies and pass the ordered
            //values to the callback.
            //Default to [require, exports, module] if no deps
            deps = !deps.length && callback.length ? ['require', 'exports', 'module'] : deps;
            for (i = 0; i < deps.length; i += 1) {
                map = makeMap(deps[i], relName);
                depName = map.f;

                //Fast path CommonJS standard dependencies.
                if (depName === "require") {
                    args[i] = handlers.require(name);
                } else if (depName === "exports") {
                    //CommonJS module spec 1.1
                    args[i] = handlers.exports(name);
                    usingExports = true;
                } else if (depName === "module") {
                    //CommonJS module spec 1.1
                    cjsModule = args[i] = handlers.module(name);
                } else if (hasProp(defined, depName) ||
                           hasProp(waiting, depName) ||
                           hasProp(defining, depName)) {
                    args[i] = callDep(depName);
                } else if (map.p) {
                    map.p.load(map.n, makeRequire(relName, true), makeLoad(depName), {});
                    args[i] = defined[depName];
                } else {
                    throw new Error(name + ' missing ' + depName);
                }
            }

            ret = callback ? callback.apply(defined[name], args) : undefined;

            if (name) {
                //If setting exports via "module" is in play,
                //favor that over return value and exports. After that,
                //favor a non-undefined return value over exports use.
                if (cjsModule && cjsModule.exports !== undef &&
                        cjsModule.exports !== defined[name]) {
                    defined[name] = cjsModule.exports;
                } else if (ret !== undef || !usingExports) {
                    //Use the return value from the function.
                    defined[name] = ret;
                }
            }
        } else if (name) {
            //May just be an object definition for the module. Only
            //worry about defining if have a module name.
            defined[name] = callback;
        }
    };

    requirejs = require = req = function (deps, callback, relName, forceSync, alt) {
        if (typeof deps === "string") {
            if (handlers[deps]) {
                //callback in this case is really relName
                return handlers[deps](callback);
            }
            //Just return the module wanted. In this scenario, the
            //deps arg is the module name, and second arg (if passed)
            //is just the relName.
            //Normalize module name, if it contains . or ..
            return callDep(makeMap(deps, callback).f);
        } else if (!deps.splice) {
            //deps is a config object, not an array.
            config = deps;
            if (config.deps) {
                req(config.deps, config.callback);
            }
            if (!callback) {
                return;
            }

            if (callback.splice) {
                //callback is an array, which means it is a dependency list.
                //Adjust args if there are dependencies
                deps = callback;
                callback = relName;
                relName = null;
            } else {
                deps = undef;
            }
        }

        //Support require(['a'])
        callback = callback || function () {};

        //If relName is a function, it is an errback handler,
        //so remove it.
        if (typeof relName === 'function') {
            relName = forceSync;
            forceSync = alt;
        }

        //Simulate async callback;
        if (forceSync) {
            main(undef, deps, callback, relName);
        } else {
            //Using a non-zero value because of concern for what old browsers
            //do, and latest browsers "upgrade" to 4 if lower value is used:
            //http://www.whatwg.org/specs/web-apps/current-work/multipage/timers.html#dom-windowtimers-settimeout:
            //If want a value immediately, use require('id') instead -- something
            //that works in almond on the global level, but not guaranteed and
            //unlikely to work in other AMD implementations.
            setTimeout(function () {
                main(undef, deps, callback, relName);
            }, 4);
        }

        return req;
    };

    /**
     * Just drops the config on the floor, but returns req in case
     * the config return value is used.
     */
    req.config = function (cfg) {
        return req(cfg);
    };

    /**
     * Expose module registry for debugging and tooling
     */
    requirejs._defined = defined;

    define = function (name, deps, callback) {

        //This module may not have dependencies
        if (!deps.splice) {
            //deps is not an array, so probably means
            //an object literal or factory function for
            //the value. Adjust args.
            callback = deps;
            deps = [];
        }

        if (!hasProp(defined, name) && !hasProp(waiting, name)) {
            waiting[name] = [name, deps, callback];
        }
    };

    define.amd = {
        jQuery: true
    };
}());

define("requireLib", function(){});

define('magic_queue',['require','exports','module'],function (require, exports, module) {
/*
  - MagicQueue -

  Provides constant access to all operation,
  except for getting the queue.

  - TODO -
 */
var MagicQueue, removeValue;

removeValue = function(ctx, key) {
  var value;
  value = ctx.dict[key];
  delete ctx.dict[key];
  return value;
};

module.exports = MagicQueue = (function() {
  function MagicQueue() {}

  MagicQueue.prototype.orderedKeys = [];

  MagicQueue.prototype.dict = {};

  MagicQueue.prototype.pushHead = function(key, value) {
    this.orderedQueue.push(key);
    return this.dict[key] = value;
  };

  MagicQueue.prototype.pushTail = function(key, value) {
    this.orderedKeys.unshift(key);
    return this.dict[key] = value;
  };

  MagicQueue.prototype.popHead = function() {
    var key, value;
    if (this.orderedKeys.length === 0) {
      return null;
    }
    key = this.orderedKeys.pop();
    value = removeValue(key);
    if ((value == null) || value.removed === true) {
      return this.popHead();
    }
    return value;
  };

  MagicQueue.prototype.popTail = function() {
    var key, value;
    if (this.orderedKeys.length === 0) {
      return null;
    }
    key = this.orderedKeys.shift();
    value = removeValue(key);
    if ((value == null) || value.removed === true) {
      return this.popTail();
    }
    return value;
  };

  MagicQueue.prototype.removeItem = function(key) {
    var _ref;
    return (_ref = this.dict[key]) != null ? _ref.removed = true : void 0;
  };

  MagicQueue.prototype.getItem = function(key) {
    return this.dict[key];
  };

  MagicQueue.prototype.clear = function() {
    this.orderedKeys = [];
    return this.dict = {};
  };

  MagicQueue.prototype.getQueue = function() {
    var key, queue, _i, _len, _ref;
    queue = [];
    _ref = this.orderedKeys;
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      key = _ref[_i];
      queue.push(this.dict[key]);
    }
    return queue;
  };

  return MagicQueue;

})();

});

define('request_manager',['require','exports','module','./magic_queue'],function (require, exports, module) {var MagicQueue, RequestManager, cancelRequest, consume, defaultEventMap, deleteRequest, pushRequest, store;

MagicQueue = require("./magic_queue");


/*
	TODO
	* limit the number of pending requests ?
	* manage the database limit
	* documentation
	* set models status according to events, and update the cache
	* manage connectivity
	* request db persistence
 */

store = localforage;

defaultEventMap = {
  'syncing': 'syncing',
  'pending': 'pending',
  'synced': 'synced',
  'unsynced': 'unsynced'
};


/*
	------- Private methods -------
 */

deleteRequest = function(ctx, request) {
  store.removeItem(request.url);
  return delete ctx.pendingKeys[request.url];
};

cancelRequest = function(ctx, request) {
  request.model.trigger(ctx.eventMap['unsynced']);
  return deleteRequest(ctx, request);
};

pushRequest = function(ctx, request) {
  var interval;
  if (request == null) {
    return;
  }
  ctx.pendingRequests.push(request);
  clearTimeout(ctx.timeout);
  interval = 500;
  return this._consume(ctx);
};

consume = function(ctx) {
  var deferred, req;
  deferred = $.deferred();
  req = ctx.pendingRequests.pop();
  if (req == null) {
    return deferred.reject();
  }
  Backbone.sync(req.method, req.model, req.options).done(function() {
    request.model.trigger('sent');
    return deferred.resolve.apply(this, arguments);
  }).fail(function() {
    ctx.pendingRequests.unshift(req);
    request.model.trigger('request:pending');
    if (ctx._interval < ctx._MAX_REQUEST_INTERVAL * 1000) {
      ctx._interval = ctx._interval * 2;
    }
    ctx._timeout = setTimeout((function() {
      return consume(ctx);
    }), ctx._interval);
    return deferred.reject.apply(this, arguments);
  });
  return deferred;
};


/*
	------- Public methods -------
 */

module.exports = RequestManager = (function() {
  RequestManager.prototype.MAX_REQUEST_INTERVAL = 60;

  RequestManager.prototype.KEY = 'mnemosyne.pendingRequests';


  /*
  		request:
  			method
  			model
  			options
  			url // replace by key ?
   */

  function RequestManager(eventMap) {
    if (eventMap == null) {
      eventMap = {};
    }
    this.eventMap = _.extend(defaultEventMap, eventMap);
    store.getItem(this.KEY).done((function(_this) {
      return function(values) {
        if (values instanceof Array) {
          return _this.pendingRequests = values.concat(_this.pendingRequests);
        }
      };
    })(this));
  }

  RequestManager.prototype.clear = function() {
    var request;
    this.cancelAllPendingRequests();
    ({
      getPendingRequests: function() {
        return this.pendingRequests;
      },
      retryRequest: function(index) {}
    });
    request = this.pendingRequests.splice(index, 1)[0];
    pushRequest(this, request);
    ({
      cancelAllPendingRequests: function() {
        this.pendingRequests.map((function(_this) {
          return function(request) {
            return cancelRequest(_this, request);
          };
        })(this));
        return this.pendingRequests = [];
      }
    });
    this.pendingKey = {};
    ({
      cancelPendingRequest: function(index) {
        request = this.pendingRequests.splice(index, 1);
        if (request == null) {

        }
      }
    });
    cancelRequest(this, request);
    return {
      sync: function(method, model, options) {
        request = {};
        request.method = method;
        request.model = model;
        request.options = options;
        return this.pushRequest(this, request);
      }
    };
  };

  return RequestManager;

})();

});

define('mnemosyne',['require','exports','module','./request_manager'],function (require, exports, module) {var Mnemosyne, RequestManager, cacheRead, cacheWrite, defaultOptions, load, read, serverRead, store,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

RequestManager = require("./request_manager");


/*
  TODO
  * set db infos
  * extend public methods of RequestManager
  * documentation
 */


/*
  ------- Private methods -------
 */

store = localforage;

defaultOptions = {
  forceRefresh: false,
  invalidCache: false,
  ttl: 600 * 1000
};

read = function(ctx, model, options, deferred) {
  return load(ctx, key).done(function(item) {
    return cacheRead(ctx, model, options, item, deferred);
  }).fail(function() {
    return serverRead(ctx, model, options, null, deferred);
  });
};

cacheRead = function(ctx, model, options, item, deferred) {
  if (options.forceRefresh || item.expirationDate < (new Date).getTime()) {
    return serverRead(ctx, model, options, item, deferred);
  } else {
    if (typeof options.success === "function") {
      options.success(item.value, 'success', null);
    }
    model.trigger(ctx.eventMap['synced']);
    if (deferred != null) {
      deferred.resolve(item.value);
    }
    if (model.constants.silent) {
      options.silent = true;
      return serverRead(ctx, model, options, item, null);
    }
  }
};

serverRead = function(ctx, model, options, fallbackItem, deferred) {
  return Backbone.sync(method, model, options).done(function() {
    cacheWrite(ctx, model);
    model.trigger(ctx.eventMap['synced']);
    return deferred.resolve.apply(this, arguments);
  }).fail((function(_this) {
    return function() {
      if ((typeof value !== "undefined" && value !== null) && model.constants.allowExpiredCache) {
        model.trigger(ctx.eventMap['cacheSynced']);
      } else {

      }
      model.trigger(ctx.eventMap['unsynced']);
      return deferred.reject.apply(_this, arguments);
    };
  })(this));
};

load = function(ctx, key) {
  var deferred;
  deferred = $.Deferred();
  store.getItem(key).then(function(item) {
    if (_.isEmpty(item) || (item.value == null)) {
      return deferred.reject();
    } else {
      return deferred.resolve(item);
    }
  }, function() {
    return deferred.reject();
  });
  return deferred;
};

cacheWrite = function(ctx, model) {
  var deferred, expiredDate, ttl;
  deferred = $.Deferred();
  if (((typeof model.getKey === "function" ? model.getKey() : void 0) == null) || !model.constants.cache) {
    deferred.reject();
  }
  ttl = model.constants.ttl || this._DEFAULT_EXPIRATION_TIME;
  expiredDate = (new Date()).getTime() + ttl * 1000;
  store.setItem(key, {
    'value': value,
    'expirationDate': expiredDate
  }).then(function() {
    return deferred.resolve.apply(this, arguments);
  }, function() {
    return deferred.reject.apply(this, arguments);
  });
  return deferred;
};

({

  /*
    Set the expiration date to 0
    TODO put this method public ?
   */
  invalidCache: function(key, deferred) {
    var set_item_failure, set_item_success;
    if (deferred == null) {
      deferred = $.Deferred();
    }
    if (key == null) {
      return deferred.reject();
    }
    set_item_failure = function() {
      return deferred.reject();
    };
    set_item_success = function() {
      var _base;
      if (model.collection != null) {
        return invalidCache(typeof (_base = model.collection).getKey === "function" ? _base.getKey() : void 0, deferred);
      } else {
        return deferred.resolve();
      }
    };
    store.getItem(key).then((function(_this) {
      return function(item) {
        if (item == null) {
          return deferred.resolve();
        }
        return store.setItem(key, {
          value: item.value,
          expiration_date: 0
        }).then(set_item_success, set_item_failure);
      };
    })(this), function() {
      return deferred.resolve();
    });
    return deferred;
  },

  /*
    Wrap promise using jQuery Deferred
   */
  wrapPromise: function(promise) {
    var deferred;
    deferred = $.Deferred();
    promise.then(function() {
      return deferred.resolve.apply(this, arguments);
    }, function() {
      return deferred.reject.apply(this, arguments);
    });
    return deferred;
  }
});


/*
  ------- Public methods -------
 */

module.exports = Mnemosyne = (function(_super) {
  __extends(Mnemosyne, _super);

  function Mnemosyne() {
    return Mnemosyne.__super__.constructor.apply(this, arguments);
  }


  /*
    Clear the cache. Cancel all pending requests.
   */

  Mnemosyne.prototype.clear = function() {
    Mnemosyne.__super__.clear.apply(this, arguments);
    return _wrapPromise(this._store.clear.apply(this, arguments));
  };


  /*
    Overrides the Backbone.sync method
    var methodMap = {
    'create': 'POST',
    'update': 'PUT',
    'patch':  'PATCH',
    'delete': 'DELETE',
    'read':   'GET'
    };
   */

  Mnemosyne.prototype.sync = function(method, model, options) {
    var deferred;
    if (options == null) {
      options = {};
    }
    options = _.extend(defaultOptions, options);
    deferred = $.Deferred();
    model.trigger(this.eventMap['syncing']);
    switch (method) {
      case 'read':
        read(this, model, options, deferred);
        break;
      default:
        serverSync(this, method, model, options, null, deferred);
    }
    return deferred;
  };

  return Mnemosyne;

})(RequestManager);

});


  return require('mnemosyne');
}));