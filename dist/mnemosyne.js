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

define('../app/request_manager',['require','exports','module','../app/magic_queue','../app/utils'],function (require, exports, module) {var MAX_INTERVAL, MIN_INTERVAL, MagicQueue, RequestManager, Utils, clearTimer, consumeRequests, defaultCallbacks, enqueueRequest, getMethod, initRequest, onSendFail, onSendSuccess, optimizeRequest, requestsEmpty, sendRequest;

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

requestsEmpty = function(request) {
  return Object.keys(request.methods).length === 0;
};

initRequest = function(ctx, req) {
  var pendingId, request;
  if (req.key == null) {
    req.key = req.model.getKey();
  }
  if (req.options == null) {
    req.options = {};
  }
  if (request = ctx.pendingRequests.getItem(req.key)) {
    request.methods[req.method] = req.options;
    pendingId = request.model.attributes['pending_id'];
    request.model = req.model;
    if (request.deferred.state() !== 'pending') {
      request.deferred = $.Deferred;
    }
    if (req.model.get('id') == null) {
      req.model.attributes = pendingId || new Date().getTime();
    }
    return optimizeRequest(ctx, request);
  } else {
    req.parentKeys = req.model.getParentKeys();
    if (!req.model.get('id')) {
      req.model.attributes['pending_id'] = new Date().getTime();
    }
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
  return ctx.timeout = setTimeout(function() {
    return sendRequest(ctx, request);
  }, ctx.interval);
};

onSendFail = function(ctx, request, method, error) {
  var model, status;
  model = request.model;
  if (ctx.interval < MAX_INTERVAL) {
    ctx.interval = ctx.interval * 2;
  }
  console.debug('onSendFail', request);
  if (model.cache.enabled) {
    status = error.readyState;
    enqueueRequest(ctx, request);
    ctx.callbacks.onPending({
      model: model,
      key: request.key,
      method: method
    });
    request.deferred.resolve(model.attributes);
  } else {
    ctx.callbacks.onCancelled({
      model: model,
      key: request.key,
      method: method
    });
    request.deferred.reject();
  }
  return consumeRequests(ctx);
};

onSendSuccess = function(ctx, request, method, data) {
  var model;
  model = request.model;
  delete request.methods[method];
  ctx.interval = MIN_INTERVAL;
  if (requestsEmpty(request)) {
    ctx.pendingRequests.retrieveItem(request.key);
    ctx.callbacks.onSynced({
      model: model,
      cache: model.cache,
      method: method,
      key: request.key
    }, data);
    request.deferred.resolve(data);
  } else {
    enqueueRequest(ctx, request);
  }
  return consumeRequests(ctx);
};

sendRequest = function(ctx, request) {
  var method, model, options, pendingId;
  method = getMethod(request);
  model = request.model;
  if (method == null) {
    console.warn("DEBUG -- no method in sendRequest");
    ctx.pendingRequests.retrieveItem(request.key);
    if (requestsEmpty(request)) {
      return request.deferred.resolve();
    }
  }
  if (!Utils.isConnected()) {
    onSendFail(ctx, request, method, 0);
  } else {
    pendingId = model.attributes["pending_id"];
    delete model.attributes["pending_id"];
    options = request.methods[method];
    return Backbone.sync(method, model, options).done(function(data) {
      model.attributes["pending_id"] = pendingId;
      return onSendSuccess(ctx, request, method, data);
    }).fail(function(error) {
      model.attributes["pending_id"] = pendingId;
      return onSendFail(ctx, request, method, error);
    });
  }
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
    return this.callbacks.onCancelled({
      model: request.model,
      key: request.key,
      cache: request.model.cache
    });
  };

  RequestManager.prototype.clear = function() {
    var e, request, _i, _len, _ref;
    clearTimer(this);
    try {
      _ref = this.pendingRequests.getQueue();
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        request = _ref[_i];
        this.callbacks.onCancelled({
          model: request.model,
          key: request.key,
          cache: request.model.cache
        });
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
      this.callbacks.onSynced({
        model: model,
        cache: model.cache,
        method: method,
        key: request.key
      }, null);
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

define('mnemosyne',['require','exports','module','../app/request_manager','../app/sync_machine','../app/utils','../app/connection_manager'],function (require, exports, module) {var ConnectionManager, Mnemosyne, MnemosyneCollection, MnemosyneModel, RequestManager, SyncMachine, Utils, addToCache, defaultCacheOptions, defaultOptions, initRequest, read, removeFromCache, removeFromCollectionCache, removeFromParentsCache, serverRead, updateCollectionCache, updateParentsCache, validCacheValue, wipeCache, _destroy;

RequestManager = require("../app/request_manager");

SyncMachine = require("../app/sync_machine");

Utils = require("../app/utils");

ConnectionManager = require("../app/connection_manager");

initRequest = function(method, model, options) {
  var request;
  request = {
    model: model,
    options: options,
    method: method,
    key: typeof model.getKey === "function" ? model.getKey() : void 0,
    url: _.result(model, 'url')
  };
  return request;
};

wipeCache = function(ctx) {
  var backup, deferred, deferredArray;
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
  var deferred, model;
  deferred = $.Deferred();
  model = request.model;
  if ((request.key == null) || !model.cache.enabled) {
    return serverRead(ctx, request, deferred);
  }
  Utils.store.getItem(request.key).done(function(value) {
    return validCacheValue(ctx, request, value, deferred);
  }).fail(function() {
    return serverRead(ctx, request, deferred);
  });
  return deferred;
};

validCacheValue = function(ctx, request, value, deferred) {
  var model;
  model = request.model;
  if (request.options.forceRefresh) {
    return serverRead(ctx, request, deferred);
  } else if (value.expirationDate < new Date().getTime()) {
    console.debug('cache expired');
    if (model.cache.allowExpiredCache && (value != null)) {
      deferred.resolve(value.data);
    }
    return serverRead(ctx, request, deferred);
  } else {
    console.debug(' cache valid');
    return deferred.resolve(value.data);
  }
};

serverRead = function(ctx, request, deferred) {
  console.log("Sync from server");
  if (!Utils.isConnected()) {
    console.log('No connection');
    if (request.model instanceof Backbone.Collection) {
      return deferred.reject();
    } else {
      return deferred.reject();
    }
  }
  return Backbone.sync('read', request.model, request.options).done(function(data) {
    console.log("Succeed sync from server");
    return addToCache(ctx, request, data).always(function() {
      return deferred.resolve(data);
    });
  }).fail(function(error) {
    console.log("Fail sync from server", arguments);
    return deferred.reject.apply(this, arguments);
  });
};

removeFromCollectionCache = function(ctx, request, collectionKey) {
  var deferred, model;
  deferred = $.Deferred();
  model = request.model;
  Utils.store.getItem(collectionKey).done(function(value) {
    var models;
    models = value.data;
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
    return Utils.store.setItem(collectionKey, {
      "data": models,
      "expirationDate": value.expirationDate
    }).done(function() {
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
  var deferred;
  deferred = $.Deferred();
  Utils.store.removeItem(request.key).always(function() {
    return removeFromParentsCache(ctx, request).always(function() {
      return deferred.resolve();
    });
  });
  return deferred;
};

updateCollectionCache = function(ctx, request, collectionKey) {
  var deferred, model;
  deferred = $.Deferred();
  model = request.model;
  Utils.store.getItem(collectionKey).done(function(value) {
    var models, parentModel;
    models = value.data;
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
    return Utils.store.setItem(collectionKey, {
      "data": models,
      "expirationDate": 0
    }).done(function() {
      return deferred.resolve();
    }).fail(function() {
      wipeCache(ctx);
      return deferred.reject();
    });
  }).fail(function() {
    return Utils.store.setItem(collectionKey, {
      "data": [model.attributes],
      "expirationDate": 0
    }).done(function() {
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
  var deferred, expiredDate, model;
  deferred = $.Deferred();
  model = request.model;
  if (!model.cache.enabled) {
    return deferred.resolve();
  }
  expiredDate = (new Date()).getTime() + model.cache.ttl * 1000;
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
  Utils.store.setItem(request.key, {
    "data": data,
    "expirationDate": expiredDate
  }).done(function() {
    console.log("Succeed cache write");
    return updateParentsCache(ctx, request).always(function() {
      return deferred.resolve();
    });
  }).fail(function() {
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
  enabled: false,
  ttl: 0,
  allowExpiredCache: true
};

module.exports = Mnemosyne = (function() {
  var _context;

  Mnemosyne.prototype._requestManager = null;

  Mnemosyne.prototype._connectionManager = null;

  _context = null;

  function Mnemosyne(options) {
    if (options == null) {
      options = {};
    }
    this.protectedKeys = options.protectedKeys || [];
    this._connectionManager = new ConnectionManager();
    this._requestManager = new RequestManager({
      onSynced: function(request, data) {
        var model;
        model = request.model;
        if (model.isSynced()) {
          return;
        }
        if (request.method === 'create') {
          removeFromCache(_context, request).always(function() {
            if (model instanceof Backbone.Model) {
              delete model.attributes['pending_id'];
            }
            return addToCache(_context, request, data);
          });
        } else if (request.method !== 'delete') {
          addToCache(_context, request, data);
        }
        return model.finishSync();
      },
      onPending: function(request) {
        var model;
        model = request.model;
        if (model.isPending()) {
          return;
        }
        if (request.method !== 'delete') {
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
    console.log("\n" + model.getKey());
    model.beginSync();
    request = initRequest(method, model, options);
    switch (method) {
      case 'read':
        read(_context, request).done(function(data) {
          if (data == null) {
            data = [];
          }
          if (typeof options.success === "function") {
            options.success(data, 'success', null);
          }
          model.finishSync();
          return deferred.resolve(data);
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
    return this.get('pending_id');
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