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
define('../app/magic_queue',['require','exports','module'],function (require, exports, module) {
/*
  - MagicQueue -
 */
var DEFAULT_STORAGE_KEY, MagicQueue, dbSync, removeValue;

removeValue = function(ctx, key) {
  var value;
  value = ctx.dict[key];
  delete ctx.dict[key];
  return value;
};

dbSync = function(ctx) {};

DEFAULT_STORAGE_KEY = 'mnemosyne.pendingRequests';

module.exports = MagicQueue = (function() {
  function MagicQueue() {}

  MagicQueue.prototype.orderedKeys = [];

  MagicQueue.prototype.dict = {};

  MagicQueue.prototype.addHead = function(key, value) {
    this.retrieveItem(key);
    this.orderedKeys.push(key);
    this.dict[key] = value;
    return dbSync(this);
  };

  MagicQueue.prototype.addTail = function(key, value) {
    this.retrieveItem(key);
    this.orderedKeys.unshift(key);
    this.dict[key] = value;
    return dbSync(this);
  };

  MagicQueue.prototype.getHead = function() {
    return this.dict[_.last(this.orderedKeys)];
  };

  MagicQueue.prototype.getTail = function() {
    return this.dict[this.orderedKeys[0]];
  };

  MagicQueue.prototype.getItem = function(key) {
    return this.dict[key] || null;
  };

  MagicQueue.prototype.rotate = function() {
    if (this.orderedKeys.length < 1) {
      return;
    }
    return this.orderedKeys.unshift(this.orderedKeys.pop());
  };

  MagicQueue.prototype.retrieveHead = function() {
    var key, value;
    if (this.orderedKeys.length === 0) {
      return null;
    }
    key = this.orderedKeys.pop();
    value = removeValue(this, key);
    dbSync(this);
    return value;
  };

  MagicQueue.prototype.retrieveTail = function() {
    var key, value;
    if (this.orderedKeys.length === 0) {
      return null;
    }
    key = this.orderedKeys.shift();
    value = removeValue(this, key);
    dbSync(this);
    return value;
  };

  MagicQueue.prototype.retrieveItem = function(key) {
    var indexKey, value;
    if (this.dict[key] == null) {
      return null;
    }
    indexKey = this.orderedKeys.indexOf(key);
    this.orderedKeys.splice(indexKey, 1);
    value = removeValue(this, key);
    dbSync(this);
    return value;
  };

  MagicQueue.prototype.isEmpty = function() {
    return this.orderedKeys.length === 0;
  };

  MagicQueue.prototype.getQueue = function() {
    return _.map(this.orderedKeys, (function(_this) {
      return function(key) {
        return _this.dict[key];
      };
    })(this));
  };

  MagicQueue.prototype.clear = function() {
    this.orderedKeys = [];
    this.dict = {};
    return dbSync(this);
  };

  return MagicQueue;

})();

});

define('../app/utils',['require','exports','module'],function (require, exports, module) {var Utils;

module.exports = Utils = (function() {
  function Utils() {}

  Utils.debug = function(context, message) {
    if (!window.DEBUG_MNEMOSYNE) {
      return;
    }
    return console.debug("[" + context + "] " + message);
  };

  Utils.addWithoutDuplicates = function(array, model) {
    if (model == null) {
      return;
    }
    array = _.filter(array, function(m) {
      return model.get('_pending_id') !== m.get('_pending_id');
    });
    array.unshift(model);
    return array;
  };

  Utils.store = {};

  Utils.store.getItem = function(key) {
    var value;
    value = localStorage.getItem(key);
    if (value != null) {
      return $.Deferred().resolve(JSON.parse(value));
    }
    return $.Deferred().reject();
  };

  Utils.store.setItem = function(key, value) {
    var e;
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch (_error) {
      e = _error;
      return $.Deferred().reject();
    }
    return $.Deferred().resolve();
  };

  Utils.store.removeItem = function(key) {
    localStorage.removeItem(key);
    return $.Deferred().resolve();
  };

  Utils.store.clear = function() {
    localStorage.clear();
    return $.Deferred().resolve();
  };

  return Utils;

})();

});

define('../app/request_manager',['require','exports','module','../app/magic_queue','../app/utils'],function (require, exports, module) {var MAX_INTERVAL, MIN_INTERVAL, MagicQueue, RequestManager, Utils, clearTimer, consumeRequests, debug, defaultCallbacks, enqueueRequest, getMethod, initRequest, onSendFail, onSendSuccess, optimizeRequest, requestsEmpty, sendRequest;

MagicQueue = require("../app/magic_queue");

Utils = require("../app/utils");

debug = Utils.debug;

MAX_INTERVAL = 2000;

MIN_INTERVAL = 125;

getMethod = function(request) {
  if (request.methods['create']) {
    return 'create';
  } else if (request.methods['update']) {
    return 'update';
  } else if (request.methods['delete']) {
    return 'delete';
  } else {
    return null;
  }
};

requestsEmpty = function(request) {
  return _.isEmpty(Object.keys(request.methods));
};

initRequest = function(ctx, req) {
  var request;
  if (req.options == null) {
    req.options = {};
  }
  if (req.key == null) {
    req.key = req.model.getKey();
  }
  if (request = ctx.pendingRequests.getItem(req.key)) {
    request.methods[req.method] = req.options;
    request.model = req.model;
    if (request.deferred.state() !== 'pending') {
      request.deferred = $.Deferred();
    }
    return optimizeRequest(ctx, request);
  } else {
    req.parentKeys = req.model.getParentKeys();
    req.deferred = $.Deferred();
    req.methods = {};
    req.methods[req.method] = req.options;
    return req;
  }
};

clearTimer = function(ctx) {
  clearTimeout(ctx.timeout);
  ctx.timeout = null;
  return ctx.interval = MIN_INTERVAL;
};

enqueueRequest = function(ctx, request) {
  ctx.pendingRequests.retrieveItem(request.key);
  if ((request != null) && !requestsEmpty(request)) {
    ctx.pendingRequests.addTail(request.key, request);
  }
  if (ctx.timeout === null) {
    return consumeRequests(ctx);
  }
};

consumeRequests = function(ctx) {
  var request;
  request = ctx.pendingRequests.getHead();
  if (request == null) {
    clearTimer(ctx);
    return;
  }
  return ctx.timeout = setTimeout((function() {
    return sendRequest(ctx, request);
  }), ctx.interval);
};

onSendFail = function(ctx, request, method, error) {
  var cancelRequest, model, status;
  model = request.model;
  if (ctx.interval < MAX_INTERVAL) {
    ctx.interval = ctx.interval * 2;
  }
  cancelRequest = function() {
    ctx.callbacks.onCancelled(request);
    ctx.pendingRequests.retrieveItem(request.key);
    return request.deferred.reject();
  };
  if (model.cache.enabled) {
    status = error.readyState;
    switch (status) {
      case 4:
      case 5:
        cancelRequest();
        break;
      default:
        delete request.options.xhr;
        enqueueRequest(ctx, request);
        ctx.callbacks.onPending(request, method);
        request.deferred.resolve(model.attributes);
    }
  } else {
    cancelRequest();
  }
  return consumeRequests(ctx);
};

onSendSuccess = function(ctx, request, method, data) {
  var model;
  model = request.model;
  delete request.methods[method];
  ctx.interval = MIN_INTERVAL;
  if (requestsEmpty(request)) {
    ctx.callbacks.onSynced(request, method, data);
    request.deferred.resolve(data);
  } else {
    enqueueRequest(ctx, request);
  }
  return consumeRequests(ctx);
};

sendRequest = function(ctx, request) {
  var method, model, options;
  method = getMethod(request);
  model = request.model;
  options = request.methods[method];
  Backbone.sync(method, model, options).done(function(data) {
    debug("sendRequest", "success");
    return onSendSuccess(ctx, request, method, data);
  }).fail(function(error) {
    debug("sendRequest", "fail");
    return onSendFail(ctx, request, method, error);
  });
};

optimizeRequest = function(ctx, request) {
  if ((request.methods['create'] != null) && (request.methods['delete'] != null)) {
    request.methods = {};
  } else if (((request.methods['create'] != null) || (request.methods['delete'] != null)) && (request.methods['update'] != null)) {
    delete request.methods['update'];
  }
  return request;
};

defaultCallbacks = {
  onSynced: function() {},
  onPending: function() {},
  onCancelled: function() {}
};

module.exports = RequestManager = (function() {
  function RequestManager(callbacks) {
    var onRestore;
    this.callbacks = callbacks != null ? callbacks : {};
    _.defaults(this.callbacks, defaultCallbacks);
    onRestore = function(request) {
      request.model = new Backbone.Model(request.model);
      request.model.getKey = function() {
        return request.key;
      };
      request.model.getParentKeys = function() {
        return request.parentKeys;
      };
      request.model.url = function() {
        return request.url;
      };
      return request;
    };
    this.pendingRequests = new MagicQueue(void 0, onRestore);
    this.retrySync();
  }

  RequestManager.prototype.getPendingRequests = function() {
    return this.pendingRequests.getQueue();
  };

  RequestManager.prototype.retrySync = function() {
    clearTimer(this);
    return consumeRequests(this);
  };

  RequestManager.prototype.cancelPendingRequest = function(key) {
    var request;
    request = this.pendingRequests.retrieveItem(key);
    if (request == null) {
      return;
    }
    return this.callbacks.onCancelled(request);
  };

  RequestManager.prototype.clear = function() {
    var e, request, _i, _len, _ref;
    clearTimer(this);
    try {
      _ref = this.pendingRequests.getQueue();
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        request = _ref[_i];
        this.callbacks.onCancelled(request);
      }
    } catch (_error) {
      e = _error;
      console.warn("Bad content found into mnemosyne magic queue", e);
    }
    return this.pendingRequests.clear();
  };

  RequestManager.prototype.sync = function(request) {
    var method, model;
    method = request.method;
    request = initRequest(this, request);
    model = request.model;
    if (requestsEmpty(request)) {
      this.pendingRequests.retrieveItem(request.key);
      this.callbacks.onSynced(request, null);
      request.deferred.resolve();
    } else {
      enqueueRequest(this, request);
    }
    return request.deferred;
  };

  return RequestManager;

})();

});

define('../app/sync_machine',['require','exports','module'],function (require, exports, module) {
var PENDING, STATE_CHANGE, SYNCED, SYNCING, SyncMachine, UNSYNCED, event, _fn, _i, _len, _ref,
  __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

UNSYNCED = 'unsynced';

SYNCING = 'syncing';

PENDING = 'pending';

SYNCED = 'synced';

STATE_CHANGE = 'syncStateChange';

SyncMachine = {
  _syncState: UNSYNCED,
  _previousSyncState: null,
  syncState: function() {
    return this._syncState;
  },
  isUnsynced: function() {
    return this._syncState === UNSYNCED;
  },
  isSynced: function() {
    return this._syncState === SYNCED;
  },
  isSyncing: function() {
    return this._syncState === SYNCING;
  },
  isPending: function() {
    return this._syncState === PENDING;
  },
  unsync: function() {
    var _ref;
    if ((_ref = this._syncState) === SYNCING || _ref === PENDING || _ref === SYNCED) {
      this._previousSync = this._syncState;
      this._syncState = UNSYNCED;
      this.trigger(this._syncState, this, this._syncState);
      this.trigger(STATE_CHANGE, this, this._syncState);
    }
  },
  beginSync: function() {
    var _ref;
    if ((_ref = this._syncState) === UNSYNCED || _ref === SYNCED || _ref === PENDING) {
      this._previousSync = this._syncState;
      this._syncState = SYNCING;
      this.trigger(this._syncState, this, this._syncState);
      this.trigger(STATE_CHANGE, this, this._syncState);
    }
  },
  pendingSync: function() {
    if (this._syncState === SYNCING) {
      this._previousSync = this._syncState;
      this._syncState = PENDING;
      this.trigger(this._syncState, this, this._syncState);
      this.trigger(STATE_CHANGE, this, this._syncState);
    }
  },
  finishSync: function() {
    var _ref;
    if ((_ref = this._syncState) === SYNCING || _ref === PENDING) {
      this._previousSync = this._syncState;
      this._syncState = SYNCED;
      this.trigger(this._syncState, this, this._syncState);
      this.trigger(STATE_CHANGE, this, this._syncState);
    }
  },
  abortSync: function() {
    var _ref;
    if (_ref = this._syncState, __indexOf.call(SYNCING, _ref) >= 0) {
      this._syncState = this._previousSync;
      this._previousSync = this._syncState;
      this.trigger(this._syncState, this, this._syncState);
      this.trigger(STATE_CHANGE, this, this._syncState);
    }
  }
};

_ref = [UNSYNCED, SYNCING, SYNCED, PENDING, STATE_CHANGE];
_fn = function(event) {
  return SyncMachine[event] = function(callback, context) {
    if (context == null) {
      context = this;
    }
    this.on(event, callback, context);
    if (this._syncState === event) {
      return callback.call(context);
    }
  };
};
for (_i = 0, _len = _ref.length; _i < _len; _i++) {
  event = _ref[_i];
  _fn(event);
}

if (typeof Object.freeze === "function") {
  Object.freeze(SyncMachine);
}

module.exports = SyncMachine;

});

define('mnemosyne',['require','exports','module','../app/request_manager','../app/sync_machine','../app/utils'],function (require, exports, module) {var MNEMOSYNE_DB_VERSION, Mnemosyne, MnemosyneCollection, MnemosyneModel, RequestManager, SyncMachine, Utils, addToCache, checkVersion, debug, defaultCacheOptions, defaultOptions, initRequest, read, removeFromCache, removeFromCollectionCache, removeFromParentsCache, serverRead, updateCollectionCache, updateParentsCache, wipeCache, _destroy;

RequestManager = require("../app/request_manager");

SyncMachine = require("../app/sync_machine");

Utils = require("../app/utils");

debug = Utils.debug;

MNEMOSYNE_DB_VERSION = 1;

checkVersion = function(ctx) {
  return Utils.store.getItem("MNEMOSYNE_DB_VERSION").done(function(previousBaseVersion) {
    if (previousBaseVersion < MNEMOSYNE_DB_VERSION) {
      return wipeCache(ctx);
    }
  }).fail(function() {
    return wipeCache(ctx);
  });
};

initRequest = function(method, model, options) {
  var enabled, request, _ref;
  if (model instanceof Backbone.Model && !model.get('id')) {
    model.attributes['pending_id'] = new Date().getTime();
  }
  enabled = model.cache.enabled;
  if (((_ref = options.data) != null ? _ref.page : void 0) > 1) {
    enabled = false;
  }
  request = {
    model: model,
    options: options,
    method: method,
    key: model.getKey(),
    url: _.result(model, 'url'),
    cacheEnabled: enabled
  };
  return request;
};

wipeCache = function(ctx) {
  var backup, deferred, deferredArray;
  console.log("Mnemosyne: wipe cache");
  deferred = $.Deferred();
  backup = [];
  deferredArray = _.map(ctx.protectedKeys, function(protectedKey) {
    deferred = $.Deferred();
    Utils.store.getItem(protectedKey).done(function(val) {
      return backup.push({
        value: val,
        key: protectedKey
      });
    }).always(function() {
      return deferred.resolve();
    });
    return deferred;
  });
  $.when(deferredArray).then(function() {
    return Utils.store.clear().done(function() {
      var val, _i, _len;
      Utils.store.setItem("MNEMOSYNE_DB_VERSION", MNEMOSYNE_DB_VERSION);
      for (_i = 0, _len = backup.length; _i < _len; _i++) {
        val = backup[_i];
        Utils.store.setItem(val.key, val.value);
      }
      return deferred.resolve();
    }).fail(function() {
      console.error('Fail to clear cache');
      return deferred.reject();
    });
  });
  return deferred;
};

read = function(ctx, request) {
  var deferred;
  deferred = $.Deferred();
  serverRead(ctx, request).done(function() {
    debug("read", "success");
    return deferred.resolve.apply(this, arguments);
  }).fail(function() {
    var args;
    debug("read", "fail");
    args = arguments;
    return ctx.cacheRead(request.key).done(function() {
      return deferred.resolve.apply(this, arguments);
    }).fail(function() {
      return deferred.reject.apply(this, args);
    });
  });
  return deferred;
};

serverRead = function(ctx, request) {
  return Backbone.sync('read', request.model, request.options).done(function(value) {
    debug("serverRead", "success");
    return addToCache(ctx, request, value);
  }).fail(function() {
    return debug("serverRead", "fail");
  }).always(function() {
    return request.model.trigger('sync:args', arguments[0], arguments[1], arguments[2]);
  });
};

removeFromCollectionCache = function(ctx, request, collectionKey) {
  var deferred, model;
  deferred = $.Deferred();
  model = request.model;
  Utils.store.getItem(collectionKey).done(function(value) {
    var models;
    models = value;
    if (model.get('pending_id')) {
      models = _.filter(models, function(m) {
        return m.pending_id !== model.get('pending_id');
      });
    }
    if (model.get('id')) {
      models = _.filter(models, function(m) {
        return m.id !== model.get('id');
      });
    }
    return Utils.store.setItem(collectionKey, models).done(function() {
      return deferred.resolve();
    }).fail(function() {
      return onDataBaseError(ctx);
    });
  }).fail(function() {
    return deferred.resolve();
  });
  return deferred;
};

removeFromParentsCache = function(ctx, request) {
  var deferred, deferredArray, parentKeys, _base;
  deferred = $.Deferred();
  parentKeys = (typeof (_base = request.model).getParentKeys === "function" ? _base.getParentKeys() : void 0) || [];
  if (parentKeys.length === 0) {
    return deferred.resolve();
  }
  deferredArray = _.map(parentKeys, function(parentKey) {
    if (typeof parentKey === 'string') {
      return removeFromCollectionCache(ctx, request, parentKey);
    } else {
      return removeFromCollectionCache(ctx, request, parentKey.key);
    }
  });
  $.when.apply($, deferredArray).then(function() {
    return deferred.resolve();
  }, function() {
    return deferred.reject();
  });
  return deferred;
};

removeFromCache = function(ctx, request) {
  var deferred, model;
  deferred = $.Deferred();
  model = request.model;
  if (model instanceof Backbone.Collection) {
    Utils.store.removeItem(model.getKey()).always(function() {
      return deferred.resolve();
    });
  } else {
    Utils.store.removeItem(request.key).always(function() {
      return removeFromParentsCache(ctx, request).always(function() {
        return deferred.resolve();
      });
    });
  }
  return deferred;
};

updateCollectionCache = function(ctx, request, collectionKey) {
  var deferred, model;
  deferred = $.Deferred();
  model = request.model;
  Utils.store.getItem(collectionKey).done(function(value) {
    var models, parentModel;
    models = value;
    if (model.get('pending_id')) {
      parentModel = _.findWhere(models, {
        "pending_id": model.get('pending_id')
      });
    } else {
      parentModel = _.findWhere(models, {
        "id": model.get('id')
      });
    }
    if (parentModel != null) {
      _.extend(parentModel, model.attributes);
    } else {
      models.unshift(model.attributes);
    }
    return Utils.store.setItem(collectionKey, models).done(function() {
      return deferred.resolve();
    }).fail(function() {
      wipeCache(ctx);
      return deferred.reject();
    });
  }).fail(function() {
    return Utils.store.setItem(collectionKey, [model.attributes]).done(function() {
      return deferred.resolve();
    }).fail(function() {
      wipeCache(ctx);
      return deferred.reject();
    });
  });
  return deferred;
};

updateParentsCache = function(ctx, request) {
  var deferred, deferredArray, parentKeys, _base;
  deferred = $.Deferred();
  if (request.model instanceof Backbone.Collection) {
    return deferred.resolve();
  }
  parentKeys = (typeof (_base = request.model).getParentKeys === "function" ? _base.getParentKeys() : void 0) || [];
  if (parentKeys.length === 0) {
    return deferred.resolve();
  }
  deferredArray = _.map(parentKeys, function(parentKey) {
    if (typeof parentKey === 'string') {
      return updateCollectionCache(ctx, request, parentKey);
    } else if (typeof parentKey.filter === "function" ? parentKey.filter(request.model) : void 0) {
      return updateCollectionCache(ctx, request, parentKey.key);
    } else {
      return removeFromCollectionCache(ctx, request, parentKey.key);
    }
  });
  $.when(deferredArray).then(function() {
    return deferred.resolve();
  }, function() {
    return deferred.reject();
  });
  return deferred;
};

addToCache = function(ctx, request, data) {
  var deferred, model, _ref;
  deferred = $.Deferred();
  model = request.model;
  if (!request.cacheEnabled) {
    return deferred.resolve();
  }
  if (model instanceof Backbone.Model) {
    if (data == null) {
      data = model.attributes;
    }
  } else if (model instanceof Backbone.Collection) {
    if (data == null) {
      data = _.map(model.models, function(m) {
        return m.attributes;
      });
    }
    if (((_ref = request.options.data) != null ? _ref.page : void 0) > 1) {
      console.warn('Attempting to save page > 1');
      return deferred.resolve();
    }
  } else {
    console.warn("Wrong instance for ", model);
    return deferred.reject();
  }
  Utils.store.setItem(request.key, data).done(function() {
    debug("addToCache", "success");
    return updateParentsCache(ctx, request).always(function() {
      return deferred.resolve();
    });
  }).fail(function() {
    debug("addToCache", "fail");
    wipeCache(ctx);
    return deferred.reject();
  });
  return deferred;
};


/*
  ------- Let's create Mnemosyne ! -------
 */

defaultOptions = {
  forceRefresh: false
};

defaultCacheOptions = {
  enabled: false
};

module.exports = Mnemosyne = (function() {
  var _context;

  Mnemosyne.prototype._requestManager = null;

  _context = null;

  function Mnemosyne(options) {
    if (options == null) {
      options = {};
    }
    this.protectedKeys = options.protectedKeys || [];
    this._requestManager = new RequestManager({
      onSynced: function(request, method, data) {
        var model;
        model = request.model;
        if (model.isSynced()) {
          return;
        }
        if (method === 'create') {
          removeFromCache(_context, request).always(function() {
            if (model instanceof Backbone.Model) {
              delete model.attributes['pending_id'];
            }
            request.key = model.getKey();
            return addToCache(_context, request, data);
          });
        } else if (method !== 'delete') {
          addToCache(_context, request, data);
        }
        return model.finishSync();
      },
      onPending: function(request, method) {
        var model;
        model = request.model;
        if (model.isPending()) {
          return;
        }
        if (method !== 'delete') {
          addToCache(_context, request);
        }
        return model.pendingSync();
      },
      onCancelled: function(request) {
        var model;
        model = request.model;
        if (model.isUnsynced()) {
          return;
        }
        if (model instanceof Backbone.Model && !model.get('id')) {
          removeFromCache(_context, request);
        }
        return model.unsync();
      }
    });
    _context = this;
    checkVersion(_context);
  }


  /*
    Set the value of key, model or collection in cache.
    If `key` parameter is a model, parent collections will be updated
  
    return a Deferred
   */

  Mnemosyne.prototype.cacheWrite = function(key, value) {
    var model, request;
    if (key instanceof Backbone.Model || key instanceof Backbone.Collection) {
      model = key;
      model.cache = _.defaults(model.cache || {}, defaultCacheOptions);
      request = initRequest(null, model, {});
      return addToCache(_context, request);
    }
    return Utils.store.setItem(key, value);
  };


  /*
    Get the value of a key, model or collection in cache.
  
    return a Deferred
   */

  Mnemosyne.prototype.cacheRead = function(key) {
    if (key instanceof Backbone.Model || key instanceof Backbone.Collection) {
      key = key.getKey();
    }
    return Utils.store.getItem(key);
  };


  /*
    Remove a value, model or a collection from cache.
  
    return a Deferred
   */

  Mnemosyne.prototype.cacheRemove = function(key) {
    var equest, model;
    if (key instanceof Backbone.Model || key instanceof Backbone.Collection) {
      model = key;
      equest = initRequest(null, model, {});
      return removeFromCache(_context, request);
    }
    return Utils.store.removeItem(key);
  };


  /*
    Clear the entire cache, deleting all pending requests
  
    return a Deferred
   */

  Mnemosyne.prototype.cacheClear = function() {
    this.cancelAllPendingRequests();
    return wipeCache(_context);
  };


  /*
    return an Array of all pending requests
      (see RequestManager doc for `request` object)
   */

  Mnemosyne.prototype.getPendingRequests = function() {
    return _context._requestManager.getPendingRequests();
  };


  /*
    Retry the synchronisation setting the timeout to the lowest value
   */

  Mnemosyne.prototype.retrySync = function() {
    return _context._requestManager.retrySync();
  };


  /*
    Cancel the pending request corresponding to the `key` parameter
   */

  Mnemosyne.prototype.cancelPendingRequest = function(key) {
    var request;
    request = this.pendingRequests.retrieveItem(key);
    if (request == null) {
      return;
    }
    return cancelRequest(this, request);
  };


  /*
    Cancel all pending requests
   */

  Mnemosyne.prototype.cancelAllPendingRequests = function() {
    return _context._requestManager.clear();
  };


  /*
    Overrides the Backbone.sync method
   */

  Mnemosyne.prototype.sync = function(method, model, options) {
    var deferred, request;
    if (options == null) {
      options = {};
    }
    deferred = $.Deferred();
    options = _.defaults(options, defaultOptions);
    model.cache = _.defaults(model.cache || {}, defaultCacheOptions);
    model.beginSync();
    request = initRequest(method, model, options);
    debug("sync", request.key);
    switch (method) {
      case 'read':
        read(_context, request).done(function() {
          var _ref;
          if ((_ref = options.success) != null) {
            _ref.apply(this, arguments);
          }
          model.finishSync();
          return deferred.resolve.apply(this, arguments);
        }).fail(function() {
          model.unsync();
          return deferred.reject.apply(this, arguments);
        });
        break;
      case 'delete':
        removeFromCache(_context, request);
        deferred = _context._requestManager.sync(request);
        break;
      default:
        deferred = _context._requestManager.sync(request);
    }
    return deferred;
  };

  Mnemosyne.SyncMachine = SyncMachine;

  return Mnemosyne;

})();

MnemosyneModel = (function() {
  function MnemosyneModel() {}

  MnemosyneModel.prototype.getParentKeys = function() {
    return [];
  };

  MnemosyneModel.prototype.sync = function() {
    return Mnemosyne.prototype.sync.apply(this, arguments);
  };

  return MnemosyneModel;

})();

MnemosyneCollection = (function() {
  function MnemosyneCollection() {}

  MnemosyneCollection.prototype.sync = function() {
    return Mnemosyne.prototype.sync.apply(this, arguments);
  };

  return MnemosyneCollection;

})();

_destroy = Backbone.Model.prototype.destroy;

Backbone.Model.prototype.destroy = function() {
  var ret, _isNew;
  _isNew = this.isNew;
  this.isNew = function() {
    return false;
  };
  ret = _destroy.apply(this, arguments);
  this.isNew = _isNew;
  return ret;
};

_.extend(Backbone.Model.prototype, SyncMachine);

_.extend(Backbone.Model.prototype, MnemosyneModel.prototype);

_.extend(Backbone.Collection.prototype, SyncMachine);

_.extend(Backbone.Collection.prototype, MnemosyneCollection.prototype);

});


  return require('mnemosyne');
}));