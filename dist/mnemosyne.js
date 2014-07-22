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

dbSync = function(ctx) {
  return _.defer(function() {
    localStorage.setItem(ctx.key + '.orderedKeys', JSON.stringify(ctx.orderedKeys));
    return localStorage.setItem(ctx.key + '.dict', JSON.stringify(ctx.dict));
  });
};

DEFAULT_STORAGE_KEY = 'mnemosyne.pendingRequests';

module.exports = MagicQueue = (function() {
  MagicQueue.prototype.orderedKeys = [];

  MagicQueue.prototype.dict = {};

  function MagicQueue(key, onRestore) {
    this.key = key != null ? key : DEFAULT_STORAGE_KEY;
    this.orderedKeys = JSON.parse(localStorage.getItem(this.key + '.orderedKeys')) || [];
    this.dict = JSON.parse(localStorage.getItem(this.key + '.dict')) || {};
    if (typeof onRestore === 'function') {
      _.map(this.dict, onRestore);
    }
  }

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

  Utils.isConnected = function() {
    if (window.device && (window.navigator.connection != null)) {
      return window.navigator.connection.type !== Connection.NONE;
    } else {
      return window.navigator.onLine;
    }
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
    localStorage.setItem(key, JSON.stringify(value));
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

define('../app/request_manager',['require','exports','module','../app/magic_queue','../app/utils'],function (require, exports, module) {var MAX_INTERVAL, MIN_INTERVAL, MagicQueue, RequestManager, Utils, clearTimer, consumeRequests, defaultCallbacks, enqueueRequest, getMethod, initRequest, isRequestEmpty, onSendFail, onSendSuccess, optimizeRequest, sendRequest;

MagicQueue = require("../app/magic_queue");

Utils = require("../app/utils");

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

isRequestEmpty = function(request) {
  return Object.keys(request.methods).length === 0;
};

initRequest = function(ctx, method, model, options) {
  var pendingId, request;
  request = ctx.pendingRequests.getItem(model.getKey()) || {
    "methods": {}
  };
  request.model = model;
  request.key = model.getKey();
  request.url = _.result(model, 'url');
  request.cache = model.cache;
  request.parentKeys = model.getParentKeys();
  request.methods[method] = options;
  pendingId = request.model.get('pending_id');
  if (pendingId == null) {
    request.model.set('pending_id', new Date().getTime());
  }
  if (request.deferred == null) {
    request.deferred = $.Deferred();
  }
  return optimizeRequest(ctx, request);
};

clearTimer = function(ctx) {
  clearTimeout(ctx.timeout);
  ctx.timeout = null;
  return ctx.interval = MIN_INTERVAL;
};

enqueueRequest = function(ctx, request) {
  ctx.pendingRequests.addTail(request.key, request);
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
  return ctx.timeout = setTimeout(function() {
    return sendRequest(ctx, request);
  }, ctx.interval);
};

onSendFail = function(ctx, request, method, error) {
  var status, _ref, _ref1;
  if (ctx.interval < MAX_INTERVAL) {
    ctx.interval = ctx.interval * 2;
  }
  if (request.cache.enabled) {
    status = error.readyState;
    enqueueRequest(ctx, request);
    ctx.callbacks.onPending(request.model, method);
    if ((_ref = request.deferred) != null) {
      _ref.resolve(request.model.attributes);
    }
  } else {
    ctx.callbacks.onCancelled(request.model);
    if ((_ref1 = request.deferred) != null) {
      _ref1.reject();
    }
  }
  return consumeRequests(ctx);
};

onSendSuccess = function(ctx, request, method, value) {
  delete request.methods[method];
  ctx.interval = MIN_INTERVAL;
  if (isRequestEmpty(request)) {
    ctx.pendingRequests.retrieveItem(request.key);
    ctx.callbacks.onSynced(request.model, method, value);
  } else {
    enqueueRequest(ctx, ctx.pendingRequests.retrieveItem(request.key));
  }
  return consumeRequests(ctx);
};

sendRequest = function(ctx, request) {
  var deferred, method, options, pendingId;
  deferred = request.deferred;
  method = getMethod(request);
  if (!Utils.isConnected()) {
    onSendFail(ctx, request, method, 0);
    return;
  } else {
    pendingId = request.model.attributes["_pending_id"];
    delete request.model.attributes["_pending_id"];
    if (method == null) {
      onSendSuccess(ctx, request, method);
      if (isRequestEmpty(request)) {
        return deferred != null ? deferred.resolve.apply(this, arguments) : void 0;
      }
    }
    options = request.methods[method];
    Backbone.sync(method, request.model, options).done(function(value) {
      onSendSuccess(ctx, request, method, value);
      if (isRequestEmpty(request)) {
        return deferred != null ? deferred.resolve.apply(this, arguments) : void 0;
      }
    }).fail(function(error) {
      request.model.attributes["_pending_id"] = pendingId;
      return onSendFail(ctx, request, method, error);
    });
  }
  return deferred;
};

optimizeRequest = function(ctx, request) {
  if ((request.methods['delete'] != null) && (request.methods['create'] != null)) {
    request.methods = {};
    return request;
  }
  if (((request.methods['create'] != null) || (request.methods['delete'] != null)) && (request.methods['update'] != null)) {
    delete request.methods['update'];
    return request;
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
    return this.callbacks.onCancelled(request.model);
  };

  RequestManager.prototype.clear = function() {
    var e, request, _i, _len, _ref;
    clearTimer(this);
    try {
      _ref = this.pendingRequests.getQueue();
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        request = _ref[_i];
        this.callbacks.onCancelled(request.model);
      }
    } catch (_error) {
      e = _error;
      console.warn("Bad content found into mnemosyne magic queue", e);
    }
    return this.pendingRequests.clear();
  };

  RequestManager.prototype.sync = function(method, model, options) {
    var request;
    if (options == null) {
      options = {};
    }
    request = initRequest(this, method, model, options);
    enqueueRequest(this, request);
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

define('../app/connection_manager',['require','exports','module','../app/utils'],function (require, exports, module) {var ConnectionManager, Utils,
  __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

Utils = require("../app/utils");


/*
  Watch the connection, providing callbacks on connection lost and recovered
 */

module.exports = ConnectionManager = (function() {
  var _CHECK_INTERVAL;

  _CHECK_INTERVAL = 1000;

  ConnectionManager.prototype._connectionLostCallbacks = {};

  ConnectionManager.prototype._connectionRecoveredCallbacks = {};

  function ConnectionManager() {
    this._watchConnection = __bind(this._watchConnection, this);
    this._watchConnection();
    this.onLine = Utils.isConnected();
  }

  ConnectionManager.prototype._watchConnection = function() {
    if (Utils.isConnected() && !this.onLine) {
      _.map(this._connectionRecoveredCallbacks, function(callback) {
        var e;
        try {
          return callback(true);
        } catch (_error) {
          e = _error;
          return console.error("Cannot call ", callback);
        }
      });
    } else if (!Utils.isConnected() && this.onLine) {
      _.map(this._connectionLostCallbacks, function(callback) {
        var e;
        try {
          return callback(false);
        } catch (_error) {
          e = _error;
          return console.error("Cannot call ", callback);
        }
      });
    }
    this.onLine = Utils.isConnected();
    return setTimeout(this._watchConnection, _CHECK_INTERVAL);
  };

  ConnectionManager.prototype.subscribe = function(event, key, callback) {
    if (typeof key !== 'string' || typeof callback !== 'function') {
      return;
    }
    switch (event) {
      case 'connectionLost':
        return this._connectionLostCallbacks[key] = callback;
      case 'connectionRecovered':
        return this._connectionRecoveredCallbacks[key] = callback;
      default:
        return console.warn('No callback for ', event);
    }
  };

  ConnectionManager.prototype.unsubscribe = function(key) {
    delete this._connectionLostCallbacks[key];
    return delete this._connectionRecoveredCallbacks[key];
  };

  ConnectionManager.prototype.isOnline = function() {
    return Utils.isConnected();
  };

  return ConnectionManager;

})();

});

define('mnemosyne',['require','exports','module','../app/request_manager','../app/sync_machine','../app/utils','../app/connection_manager'],function (require, exports, module) {var ConnectionManager, Mnemosyne, MnemosyneCollection, MnemosyneModel, RequestManager, SyncMachine, Utils, defaultCacheOptions, defaultOptions, read, removeFromCache, removeFromCollectionCache, removeFromParentsCache, removePendingModel, serverRead, updateCache, updateCollectionCache, updateParentsCache, validCacheValue, _destroy;

RequestManager = require("../app/request_manager");

SyncMachine = require("../app/sync_machine");

Utils = require("../app/utils");

ConnectionManager = require("../app/connection_manager");

read = function(ctx, model, options) {
  var deferred;
  deferred = $.Deferred();
  if (typeof model.getKey !== 'function' || !model.cache.enabled) {
    return serverRead(ctx, model, options, deferred);
  }
  Utils.store.getItem(model.getKey()).done(function(value) {
    return validCacheValue(ctx, model, options, value, deferred);
  }).fail(function() {
    return serverRead(ctx, model, options, deferred);
  });
  return deferred;
};

validCacheValue = function(ctx, model, options, value, deferred) {
  if (options.forceRefresh) {
    return serverRead(ctx, model, options, deferred);
  } else if (value.expirationDate < new Date().getTime()) {
    if (model.cache.allowExpiredCache && (value != null)) {
      deferred.resolve(value.data);
    }
    return serverRead(ctx, model, options, deferred);
  } else {
    return deferred.resolve(value.data);
  }
};

serverRead = function(ctx, model, options, deferred) {
  console.log("Sync from server");
  if (!Utils.isConnected()) {
    console.log('No connection');
    if (model instanceof Backbone.Collection) {
      return deferred.resolve([]);
    } else {
      return deferred.reject();
    }
  }
  return Backbone.sync('read', model, options).done(function(value) {
    console.log("Succeed sync from server");
    return updateCache(ctx, model, value).always(function() {
      return deferred.resolve(value);
    });
  }).fail(function(error) {
    console.log("Fail sync from server");
    return deferred.reject.apply(this, arguments);
  });
};

removeFromCollectionCache = function(ctx, collectionKey, model) {
  var deferred;
  deferred = $.Deferred();
  Utils.store.getItem(collectionKey).done(function(value) {
    var models;
    models = value.data;
    models = _.filter(models, function(m) {
      return m.id !== model.get('id');
    });
    return Utils.store.setItem(collectionKey, {
      "data": models,
      "expirationDate": value.expirationDate
    }).always(function() {
      return deferred.resolve();
    });
  }).fail(function() {
    return deferred.resolve();
  });
  return deferred;
};

removeFromParentsCache = function(ctx, model) {
  var deferred, deferredArray, parentKeys;
  deferred = $.Deferred();
  parentKeys = model.getParentKeys();
  if (parentKeys.length === 0) {
    return deferred.resolve();
  }
  deferredArray = _.map(parentKeys, function(parentKey) {
    return removeFromCollectionCache(ctx, parentKey, model);
  });
  $.when.apply($, deferredArray).then(function() {
    return deferred.resolve();
  }, function() {
    return deferred.reject();
  });
  return deferred;
};

removeFromCache = function(ctx, model) {
  var deferred;
  deferred = $.Deferred();
  Utils.store.removeItem(model).always(function() {
    return removeFromParentsCache(ctx, model).always(function() {
      return deferred.resolve();
    });
  });
  return deferred;
};

updateCollectionCache = function(ctx, collectionKey, model) {
  var deferred;
  deferred = $.Deferred();
  Utils.store.getItem(collectionKey).done(function(value) {
    var models, parentModel;
    models = value.data;
    parentModel = _.findWhere(models, {
      "id": model.get('id')
    });
    if (parentModel != null) {
      _.extend(parentModel, model.attributes);
    } else {
      models.unshift(model.attributes);
    }
    return Utils.store.setItem(collectionKey, {
      "data": models,
      "expirationDate": 0
    }).always(function() {
      return deferred.resolve();
    });
  }).fail(function() {
    return Utils.store.setItem(collectionKey, {
      "data": [model.attributes],
      "expirationDate": 0
    }).done(function() {
      return deferred.resolve();
    }).fail(function() {
      return deferred.reject();
    });
  });
  return deferred;
};

updateParentsCache = function(ctx, model) {
  var deferred, deferredArray, parentKeys;
  deferred = $.Deferred();
  if (model instanceof Backbone.Collection) {
    return deferred.resolve();
  }
  parentKeys = model.getParentKeys();
  if (parentKeys.length === 0) {
    return deferred.resolve();
  }
  deferredArray = _.map(parentKeys, function(parentKey) {
    return updateCollectionCache(ctx, parentKey, model);
  });
  $.when(deferredArray).then(function() {
    return deferred.resolve();
  }, function() {
    return deferred.reject();
  });
  return deferred;
};

updateCache = function(ctx, model, data) {
  var deferred, expiredDate;
  deferred = $.Deferred();
  if (!model.cache.enabled) {
    return deferred.resolve();
  }
  expiredDate = (new Date()).getTime() + model.cache.ttl * 1000;
  if (model instanceof Backbone.Model && (model.get('id') == null)) {
    ctx._offlineModels = Utils.addWithoutDuplicates(ctx._offlineModels, model);
    updateParentsCache(ctx, model).always(function() {
      return deferred.resolve();
    });
  } else {
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
    } else {
      console.warn("Wrong instance for ", model);
      return deferred.reject();
    }
    Utils.store.setItem(model.getKey(), {
      "data": data,
      "expirationDate": expiredDate
    }).done(function() {
      console.log("Succeed cache write");
      return updateParentsCache(ctx, model).always(function() {
        return deferred.resolve();
      });
    }).fail(function() {
      console.log("fail cache write");
      return deferred.reject();
    });
  }
  return deferred;
};

removePendingModel = function(ctx, model) {
  if (!model instanceof Backbone.Model) {
    return;
  }
  return ctx._offlineModels = _.filter(ctx._offlineModels, function(m) {
    return m.get('_pending_id') !== model.get('_pending_id');
  });
};


/*
  ------- Let's create Mnemosyne ! -------
 */

defaultOptions = {
  forceRefresh: false
};

defaultCacheOptions = {
  enabled: false,
  ttl: 0,
  allowExpiredCache: true
};

module.exports = Mnemosyne = (function() {
  var _context;

  Mnemosyne.prototype._requestManager = null;

  Mnemosyne.prototype._connectionManager = null;

  Mnemosyne.prototype._offlineModels = [];

  _context = null;

  function Mnemosyne() {
    this._connectionManager = new ConnectionManager();
    this._requestManager = new RequestManager({
      onSynced: function(model, method, value) {
        if (model.isSynced()) {
          return;
        }
        if (method !== 'delete') {
          updateCache(_context, model, value);
        }
        removePendingModel(_context, model);
        return model.finishSync();
      },
      onPending: function(model, method) {
        if (model.isPending()) {
          return;
        }
        if (method !== 'delete') {
          updateCache(_context, model);
        }
        if (model.get('id') == null) {
          _context._offlineModels = Utils.addWithoutDuplicates(_context._offlineModels, model);
        }
        return model.pendingSync();
      },
      onCancelled: function(model) {
        if (model.isUnsynced()) {
          return;
        }
        if (model instanceof Backbone.Model) {
          removePendingModel(_context, model);
        }
        return model.unsync();
      }
    });
    _context = this;
  }


  /*
    Set the value of key, model or collection in cache.
    If `key` parameter is a model, parent collections will be updated
  
    return a Deferred
   */

  Mnemosyne.prototype.cacheWrite = function(key, value) {
    var model;
    if (key instanceof Backbone.Model || key instanceof Backbone.Collection) {
      model = key;
      model.cache = _.defaults(model.cache || {}, defaultCacheOptions);
      return updateCache(_context, model);
    }
    return Utils.store.setItem(key, value);
  };


  /*
    Get the value of a key, model or collection in cache.
  
    return a Deferred
   */

  Mnemosyne.prototype.cacheRead = function(key) {
    var deferred, model;
    if (key instanceof Backbone.Model || key instanceof Backbone.Collection) {
      model = key;
      deferred = $.Deferred();
      if (typeof model.getKey !== 'function') {
        return deferred.reject();
      }
      Utils.store.getItem(model.getKey()).done(function(value) {
        return deferred.resolve(value.data);
      }).fail(function() {
        return deferred.reject();
      });
      return deferred;
    }
    return Utils.store.getItem(key);
  };


  /*
    Remove a value, model or a collection from cache.
  
    return a Deferred
   */

  Mnemosyne.prototype.cacheRemove = function(key) {
    var model;
    if (key instanceof Backbone.Model || key instanceof Backbone.Collection) {
      model = key;
      return removeFromCache(_context, model);
    }
    return Utils.store.removeItem(key);
  };


  /*
    Clear the entire cache, deleting all pending requests
  
    return a Deferred
   */

  Mnemosyne.prototype.cacheClear = function() {
    this.clear();
    return Utils.store.clear();
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

  Mnemosyne.prototype.clear = function() {
    _context._offlineModels = [];
    return _context._requestManager.clear();
  };


  /*
    Overrides the Backbone.sync method
   */

  Mnemosyne.prototype.sync = function(method, model, options) {
    var deferred;
    if (options == null) {
      options = {};
    }
    deferred = $.Deferred();
    options = _.defaults(options, defaultOptions);
    model.cache = _.defaults(model.cache || {}, defaultCacheOptions);
    console.log("\n" + model.getKey());
    model.beginSync();
    switch (method) {
      case 'read':
        read(_context, model, options).done(function(data) {
          if (data == null) {
            data = [];
          }
          if (typeof options.success === "function") {
            options.success(data, 'success', null);
          }
          model.finishSync();
          return deferred.resolve(data);
        }).fail(function() {
          deferred.reject.apply(this, arguments);
          return model.unsync();
        });
        break;
      case 'delete':
        removePendingModel(_context, model);
        removeFromCache(_context, model);
        deferred = _context._requestManager.sync(method, model, options);
        break;
      default:
        deferred = _context._requestManager.sync(method, model, options);
    }
    return deferred;
  };


  /*
    Allow you to register a callback on severals events
    The `key` is to provide easier unsubcription when using
    anonymous function.
   */

  Mnemosyne.prototype.subscribe = function(event, key, callback) {
    return _context._connectionManager.subscribe(event, key, callback);
  };


  /*
    Allow you to unregister a callback for a given key
   */

  Mnemosyne.prototype.unsubscribe = function(key) {
    return _context._connectionManager.unsubscribe(event, key);
  };


  /*
    return a boolean
   */

  Mnemosyne.prototype.isOnline = function() {
    return _context._connectionManager.isOnline();
  };

  Mnemosyne.SyncMachine = SyncMachine;

  return Mnemosyne;

})();

MnemosyneModel = (function() {
  function MnemosyneModel() {}

  MnemosyneModel.prototype.getPendingId = function() {
    return this.get('_pending_id');
  };

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