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

  - TODO -
  db persistence
 */
var MagicQueue, removeValue;

removeValue = function(ctx, key) {
  var value;
  value = ctx.dict[key];
  delete ctx.dict[key];
  return value;
};

({
  KEY: 'mnemosyne.pendingRequests'
});

module.exports = MagicQueue = (function() {
  function MagicQueue() {}

  MagicQueue.prototype.orderedKeys = [];

  MagicQueue.prototype.dict = {};

  MagicQueue.prototype.addHead = function(key, value) {
    this.retrieveItem(key);
    this.orderedKeys.push(key);
    return this.dict[key] = value;
  };

  MagicQueue.prototype.addTail = function(key, value) {
    this.retrieveItem(key);
    this.orderedKeys.unshift(key);
    return this.dict[key] = value;
  };

  MagicQueue.prototype.getHead = function() {
    var len;
    len = this.orderedKeys.length;
    return this.dict[this.orderedKeys[len - 1]];
  };

  MagicQueue.prototype.getTail = function() {
    return this.dict[this.orderedKeys[0]];
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
    return value;
  };

  MagicQueue.prototype.retrieveTail = function() {
    var key, value;
    if (this.orderedKeys.length === 0) {
      return null;
    }
    key = this.orderedKeys.shift();
    value = removeValue(this, key);
    return value;
  };

  MagicQueue.prototype.retrieveItem = function(key) {
    var indexKey;
    indexKey = this.orderedKeys.indexOf(key);
    if (indexKey === -1) {
      return null;
    }
    this.orderedKeys.splice(indexKey, 1);
    return removeValue(this, key);
  };

  MagicQueue.prototype.getItem = function(key) {
    return this.dict[key] || null;
  };

  MagicQueue.prototype.isEmpty = function() {
    return this.getQueue().length === 0;
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
      if ((this.dict[key] != null) && !this.dict[key].removed) {
        queue.push(this.dict[key]);
      }
    }
    return queue;
  };

  return MagicQueue;

})();

});

define('../app/utils',['require','exports','module'],function (require, exports, module) {var Utils;

module.exports = Utils = (function() {
  function Utils() {}

  Utils.isConnected = function() {
    return window.navigator.onLine;
  };

  Utils.isCollection = function(model) {
    return model instanceof Backbone.Collection;
  };

  Utils.isModel = function(model) {
    return model instanceof Backbone.Model;
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

define('../app/request_manager',['require','exports','module','../app/magic_queue','../app/utils'],function (require, exports, module) {var MAX_INTERVAL, MIN_INTERVAL, MagicQueue, RequestManager, Utils, consume, defaultCallbacks, getMethod, isRequestEmpty, pushRequest, removeMethod, resetTimer, smartRequest;

MagicQueue = require("../app/magic_queue");

Utils = require("../app/utils");

MAX_INTERVAL = 64000;

MIN_INTERVAL = 250;

resetTimer = function(ctx) {
  clearTimeout(ctx.timeout);
  ctx.timeout = null;
  return ctx.interval = MIN_INTERVAL;
};

pushRequest = function(ctx, request) {
  var deferred, method, options, pendingId;
  deferred = $.Deferred();
  if (request == null) {
    return deferred.reject();
  }
  ctx.pendingRequests.addTail(request.key, request);
  method = getMethod(request);
  options = request.methods[method];
  pendingId = request.model.get('_pending_id');
  if (pendingId != null) {
    console.warn("[pushRequest] -- pendingId already set!!");
  }
  if (!Utils.isConnected()) {
    console.log('[pushRequest] -- not connected. Push request in queue');
    request.model.attributes['_pending_id'] = new Date().getTime();
    ctx.callbacks.onPending(request.model);
    if (ctx.timeout == null) {
      consume(ctx);
    }
    return deferred.resolve(request.model.attributes);
  }
  console.log('[pushRequest] -- Try sync');
  Backbone.sync(method, request.model, options).done(function() {
    console.log('[pushRequest] -- Sync success');
    removeMethod(request, method);
    if (isRequestEmpty(request)) {
      ctx.pendingRequests.retrieveItem(request.key);
      ctx.callbacks.onSynced(request.model);
      return deferred.resolve.apply(this, arguments);
    }
  }).fail(function(error) {
    console.log('[pushRequest] -- Sync failed');
    request.model.attributes['_pending_id'] = new Date().getTime();
    ctx.callbacks.onPending(request.model);
    deferred.resolve(request.model.attributes);
    if (ctx.timeout == null) {
      return consume(ctx);
    }
  });
  return deferred;
};

consume = function(ctx) {
  var method, options, pendingId, request;
  request = ctx.pendingRequests.getHead();
  if (request == null) {
    console.log('[consume] -- done! 0 pending');
    resetTimer(ctx);
    return;
  }
  if (!Utils.isConnected()) {
    if (ctx.interval < MAX_INTERVAL) {
      ctx.interval = ctx.interval * 2;
    }
    console.log('[consume] -- not connected, next try in ', ctx.interval);
    return ctx.timeout = setTimeout((function() {
      return consume(ctx);
    }), ctx.interval);
  }
  method = getMethod(request);
  options = request.methods[method];
  pendingId = request.model.get('_pending_id');
  delete request.model.attributes._pending_id;
  console.log('[consume] -- try sync ', method);
  return Backbone.sync(method, request.model, options).done(function() {
    console.log('[consume] -- Sync success');
    request.model.attributes._pending_id = pendingId;
    removeMethod(request, method);
    if (isRequestEmpty(request)) {
      ctx.pendingRequests.retrieveHead();
      ctx.callbacks.onSynced(request.model);
    }
    return ctx.interval = MIN_INTERVAL;
  }).fail(function(error) {
    var status;
    console.log('[consume] -- Sync failed', error);
    status = error.readyState;
    switch (status) {
      case 4:
      case 5:
        ctx.pendingRequests.retrieveHead();
        ctx.callbacks.onCancelled(request.model);
        break;
      default:
        request.model.attributes._pending_id = pendingId;
        ctx.pendingRequests.rotate();
    }
    if (ctx.interval < MAX_INTERVAL) {
      return ctx.interval = ctx.interval * 2;
    }
  }).always(function() {
    return ctx.timeout = setTimeout((function() {
      return consume(ctx);
    }), ctx.interval);
  });
};

smartRequest = function(ctx, request) {
  if ((request.methods['delete'] != null) && (request.methods['create'] != null)) {
    ctx.pendingRequests.retrieveItem(request.key);
    return null;
  }
  if (((request.methods['create'] != null) || (request.methods['delete'] != null)) && (request.methods['update'] != null)) {
    delete request.methods['update'];
    return request;
  }
  return request;
};

removeMethod = function(request, method) {
  return delete request.methods[method];
};

isRequestEmpty = function(request) {
  return Object.keys(request.methods).length === 0;
};

getMethod = function(request) {
  if (request.methods['create']) {
    return 'create';
  } else if (request.methods['update']) {
    return 'update';
  } else if (request.methods['delete']) {
    return 'delete';
  } else {
    return console.error("No method found !", request);
  }
};

defaultCallbacks = {
  onSynced: function() {},
  onPending: function() {},
  onCancelled: function() {}
};

module.exports = RequestManager = (function() {
  function RequestManager(callbacks) {
    this.callbacks = callbacks != null ? callbacks : {};
    _.defaults(this.callbacks, defaultCallbacks);
    this.pendingRequests = new MagicQueue();
    resetTimer(this);
  }

  RequestManager.prototype.clear = function() {
    this.pendingRequests.getQueue().map((function(_this) {
      return function(request) {
        return _this.callbacks.onCancelled(request.model);
      };
    })(this));
    resetTimer(this);
    return this.pendingRequests.clear();
  };

  RequestManager.prototype.getPendingRequests = function() {
    return this.pendingRequests.getQueue();
  };

  RequestManager.prototype.retrySync = function() {
    resetTimer(this);
    return consume(this);
  };

  RequestManager.prototype.cancelPendingRequest = function(key) {
    var request;
    request = this.pendingRequests.retrieveItem(key);
    if (request == null) {
      return;
    }
    return this.callbacks.onCancelled(request.model);
  };

  RequestManager.prototype.safeSync = function(method, model, options) {
    var request;
    if (options == null) {
      options = {};
    }
    request = this.pendingRequests.getItem(model.getKey());
    if (request == null) {
      request = {};
    }
    if (request.methods == null) {
      request.methods = {};
    }
    request.model = model;
    request.methods[method] = options;
    request.key = model.getKey();
    request = smartRequest(this, request);
    model.beginSync();
    return pushRequest(this, request);
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
    if ((_ref = this._syncState) === UNSYNCED || _ref === SYNCED) {
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

define('mnemosyne',['require','exports','module','../app/request_manager','../app/sync_machine','../app/utils'],function (require, exports, module) {var Mnemosyne, MnemosyneCollection, MnemosyneModel, RequestManager, SyncMachine, Utils, cacheRead, defaultCacheOptions, defaultOptions, load, read, removeFromParentCache, removePendingModel, serverRead, serverWrite, updateCache, updateParentCache, wrapPromise;

RequestManager = require("../app/request_manager");

SyncMachine = require("../app/sync_machine");

Utils = require("../app/utils");


/*
  ------- Private methods -------
 */

read = function(ctx, model, options) {
  var deferred;
  deferred = $.Deferred();
  if (((typeof model.getKey === "function" ? model.getKey() : void 0) == null) || !model.cache.enabled) {
    console.log("Cache forbidden");
    return serverRead(ctx, model, options, null, deferred);
  }
  console.log("Try loading value from cache");
  load(model.getKey()).done(function(item) {
    console.log("Succeed to read from cache");
    return cacheRead(ctx, model, options, item, deferred);
  }).fail(function() {
    console.log("Fail to read from cache");
    return serverRead(ctx, model, options, null, deferred);
  });
  return deferred;
};

cacheRead = function(ctx, model, options, item, deferred) {
  if (Utils.isCollection(model)) {
    _.map(item.value, function(element) {
      if (element.id == null) {
        return console.warn('New model read in cache !');
      }
    });
  }
  if (options.forceRefresh || item.expirationDate < new Date().getTime()) {
    console.log("-- cache expired");
    return serverRead(ctx, model, options, item, deferred);
  } else {
    console.log("-- cache valid");
    if (typeof options.success === "function") {
      options.success(item.value, 'success', null);
    }
    if (deferred != null) {
      deferred.resolve(item.value);
    }
    return model.finishSync();
  }
};

serverRead = function(ctx, model, options, fallbackItem, deferred) {
  console.log("Sync from server");
  if ((fallbackItem != null) && model.cache.allowExpiredCache && !options.forceRefresh) {
    deferred.resolve(fallbackItem.value);
    model.finishSync();
    options.silent = true;
  }
  if (!Utils.isConnected()) {
    model.finishSync();
    console.log('No connection');
    if (Utils.isCollection(model)) {
      return deferred.resolve([]);
    } else {
      return deferred.reject();
    }
  }
  return Backbone.sync('read', model, options).done(function() {
    console.log("Succeed sync from server");
    model.attributes = arguments[0];
    return updateCache(ctx, model).always(function() {
      if (deferred.state() !== "resolved") {
        model.finishSync();
        return deferred.resolve.apply(this, arguments);
      }
    });
  }).fail(function(error) {
    console.log("Fail sync from server");
    if (deferred.state() !== "resolved") {
      deferred.reject.apply(this, arguments);
      return model.unsync();
    }
  });
};

load = function(key) {
  var deferred;
  deferred = $.Deferred();
  Utils.store.getItem(key).then(function(item) {
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

removeFromParentCache = function(ctx, model) {
  var deferred, parentKey;
  deferred = $.Deferred();
  if (Utils.isCollection(model)) {
    console.warn('removeParentFromCache: collection as argument !');
    return deferred.resolve();
  }
  if (model.isNew()) {
    console.warn('removeParentFromCache: model is new !');
    return deferred.resolve();
  }
  parentKey = model.getParentKey();
  load(parentKey).done(function(item) {
    var models;
    models = item.value;
    models = _.filter(models, function(m) {
      return m.id !== model.get('id');
    });
    return Utils.store.setItem(parentKey, {
      "value": models,
      "expirationDate": item.expirationDate
    }).always(function() {
      return deferred.resolve();
    });
  }).fail(function() {
    return deferred.resolve();
  });
  return deferred;
};

updateParentCache = function(ctx, model) {
  var deferred, parentKey, _base;
  deferred = $.Deferred();
  if (Utils.isCollection(model) || typeof model.getParentKey !== 'function') {
    return deferred.resolve();
  }
  parentKey = model.getParentKey();
  console.log("Updating parent cache [" + parentKey + "]");
  if (model.isNew()) {
    if ((_base = ctx._offlineCollections)[parentKey] == null) {
      _base[parentKey] = [];
    }
    ctx._offlineCollections[parentKey] = Utils.addWithoutDuplicates(ctx._offlineCollections[parentKey], model);
    deferred.resolve();
  } else {
    load(parentKey).done(function(item) {
      var models, parentModel;
      models = item.value;
      parentModel = _.findWhere(models, {
        "id": model.get('id')
      });
      if (parentModel != null) {
        _.extend(parentModel, model.attributes);
      } else {
        models.unshift(model.attributes);
      }
      return Utils.store.setItem(parentKey, {
        "value": models,
        "expirationDate": 0
      }).always(function() {
        return deferred.resolve();
      });
    }).fail(function() {
      Utils.store.setItem(parentKey, {
        "value": [model],
        "expirationDate": 0
      });
      return deferred.resolve();
    });
  }
  return deferred;
};

updateCache = function(ctx, model) {
  var deferred, expiredDate, value;
  deferred = $.Deferred();
  expiredDate = (new Date()).getTime() + model.cache.ttl * 1000;
  console.log("Try to write cache -- expires at " + expiredDate);
  value = null;
  if (model.models == null) {
    value = model.attributes;
  } else if (model.models != null) {
    value = _.map(model.models, function(m) {
      return m.attributes;
    });
  } else {
    console.warn("Wrong instance for ", model);
    return deferred.reject();
  }
  if (Utils.isModel(model) && model.isNew()) {
    ctx._offlineModels = Utils.addWithoutDuplicates(ctx._offlineModels, model);
    deferred.resolve();
  } else {
    if (Utils.isCollection(model)) {
      _.map(value, function(element) {
        if (element.id == null) {
          return console.warn('New model in cache !');
        }
      });
    }
    Utils.store.setItem(model.getKey(), {
      "value": value,
      "expirationDate": expiredDate
    }).then(function() {
      console.log("Succeed cache write");
      return updateParentCache(ctx, model).always(function() {
        return deferred.resolve();
      });
    }, function() {
      console.log("fail cache write");
      return deferred.reject();
    });
  }
  return deferred;
};

serverWrite = function(ctx, method, model, options, deferred) {
  console.log("serverWrite");
  return updateCache(ctx, model).done(function() {
    return ctx._requestManager.safeSync(method, model, options).done(function(value) {
      return deferred.resolve.apply(this, arguments);
    }).fail(function() {
      return deferred.reject.apply(this, arguments);
    });
  }).fail(function() {
    console.log("fail");
    model.unsync();
    deferred.reject.apply(this, arguments);
    return Utils.store.removeItem(model.getKey());
  });
};


/*
  Wrap promise using jQuery Deferred
 */

wrapPromise = function(ctx, promise) {
  var deferred;
  deferred = $.Deferred();
  promise.then(function() {
    return deferred.resolve();
  }, function() {
    return deferred.reject();
  });
  return deferred;
};

removePendingModel = function(ctx, model) {
  var key;
  ctx._offlineModels = _.filter(ctx._offlineModels, function(m) {
    return m.get('_pending_id') !== model.get('_pending_id');
  });
  key = model.getParentKey();
  return ctx._offlineCollections[key] = _.filter(ctx._offlineCollections[key], function(m) {
    return m.get('_pending_id') !== model.get('_pending_id');
  });
};


/*
  ------- Public methods -------
 */

defaultOptions = {
  forceRefresh: false
};

defaultCacheOptions = {
  ttl: 0,
  enabled: false,
  allowExpiredCache: true
};

module.exports = Mnemosyne = (function() {
  var _context;

  Mnemosyne.prototype._requestManager = null;

  Mnemosyne.prototype._offlineCollections = {};

  Mnemosyne.prototype._offlineModels = {};

  _context = null;

  function Mnemosyne() {
    this._requestManager = new RequestManager({
      onSynced: function(model) {
        if (Utils.isModel(model)) {
          if (model.isNew()) {
            console.warn("Model has not been updated yet !");
          }
          updateParentCache(_context, model);
          removePendingModel(_context, model);
        }
        model.finishSync();
        return console.log('synced');
      },
      onPending: function(model) {
        _context._offlineModels = Utils.addWithoutDuplicates(_context._offlineModels, model);
        if (model.getParentKey() != null) {
          _context._offlineCollections[model.getParentKey()] = Utils.addWithoutDuplicates(_context._offlineCollections[model.getParentKey()], model);
        }
        model.pendingSync();
        return console.log('pending');
      },
      onCancelled: function(model) {
        if (Utils.isModel(model)) {
          if (model.isNew()) {
            console.warn("Model has not been updated yet !");
            removePendingModel(_context, model);
          } else {
            console.log("TODO rollback");
          }
        }
        model.unsync();
        return console.log('unsynced');
      }
    });
    _context = this;
  }

  Mnemosyne.prototype.cacheWrite = function(model) {
    model.cache = _.defaults(model.cache || {}, defaultCacheOptions);
    return updateCache(_context, model);
  };

  Mnemosyne.prototype.cacheRead = function(key) {
    var deferred;
    deferred = $.Deferred();
    Utils.store.getItem(key).done(function(item) {
      return deferred.resolve(item.value);
    }).fail(function() {
      return deferred.reject();
    });
    return deferred;
  };

  Mnemosyne.prototype.cacheRemove = function(key) {
    return Utils.store.removeItem(key);
  };

  Mnemosyne.prototype.cacheClear = function() {
    return Utils.store.clear();
  };

  Mnemosyne.prototype.getPendingRequests = function() {
    return _context._requestManager.getPendingRequests();
  };

  Mnemosyne.prototype.retrySync = function() {
    return _context._requestManager.retrySync();
  };

  Mnemosyne.prototype.cancelPendingRequest = function(key) {
    var request;
    request = this.pendingRequests.retrieveItem(key);
    if (request == null) {
      return;
    }
    return cancelRequest(this, request);
  };

  Mnemosyne.prototype.clear = function() {
    _context._offlineCollections = {};
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
    options = _.defaults(options, defaultOptions);
    model.cache = _.defaults(model.cache || {}, defaultCacheOptions);
    deferred = $.Deferred();
    console.log("\n" + model.getKey());
    model.beginSync();
    switch (method) {
      case 'read':
        read(_context, model, options).done(function(value) {
          var collection, models, offlineModel, _i, _len;
          if (Utils.isCollection(model)) {
            collection = model;
            models = _context._offlineCollections[collection.getKey()];
            if (models != null) {
              for (_i = 0, _len = models.length; _i < _len; _i++) {
                offlineModel = models[_i];
                value.unshift(offlineModel.attributes);
              }
            }
          }
          if (typeof options.success === "function") {
            options.success(value, 'success', null);
          }
          return deferred.resolve(value);
        }).fail(function() {
          var collection, models, offlineModel, value, _i, _len;
          if (Utils.isCollection(model)) {
            value = [];
            collection = model;
            models = _context._offlineCollections[collection.getKey()];
            if (models != null) {
              for (_i = 0, _len = models.length; _i < _len; _i++) {
                offlineModel = models[_i];
                value.unshift(offlineModel.attributes);
              }
            }
            if (typeof options.success === "function") {
              options.success(value, 'success', null);
            }
          }
          return deferred.reject.apply(this, arguments);
        });
        break;
      case 'delete':
        model.on('synced', function() {
          removePendingModel(_context, model);
          return removeFromParentCache(_context, model);
        });
        serverWrite(_context, method, model, options, deferred);
        break;
      default:
        serverWrite(_context, method, model, options, deferred);
    }
    return deferred;
  };

  Mnemosyne.SyncMachine = SyncMachine;

  return Mnemosyne;

})();

MnemosyneModel = (function() {
  function MnemosyneModel() {}

  MnemosyneModel.prototype.getPendingId = function() {
    return this.get('_pending_id');
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

_.extend(Backbone.Model.prototype, SyncMachine);

_.extend(Backbone.Model.prototype, MnemosyneModel.prototype);

_.extend(Backbone.Collection.prototype, SyncMachine);

_.extend(Backbone.Collection.prototype, MnemosyneCollection.prototype);

});


  return require('mnemosyne');
}));