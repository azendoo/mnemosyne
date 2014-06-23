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

MAX_INTERVAL = 2000;

MIN_INTERVAL = 125;

resetTimer = function(ctx) {
  clearTimeout(ctx.timeout);
  ctx.timeout = null;
  return ctx.interval = MIN_INTERVAL;
};

pushRequest = function(ctx, request) {
  var deferred, method, options, pendingId;
  deferred = $.Deferred();
  ctx.pendingRequests.addTail(request.key, request);
  method = getMethod(request);
  options = request.methods[method];
  pendingId = request.model.get('_pending_id');
  if (pendingId != null) {
    console.warn("[pushRequest] -- pendingId already set!!");
  }
  if (!Utils.isConnected()) {
    if (!request.model.cache.enabled) {
      console.log('[pushRequest] -- not connected. Not queued because of cache disabled');
      ctx.callbacks.onCancelled(request.model);
      return deferred.reject();
    }
    console.log('[pushRequest] -- not connected. Push request in queue');
    request.model.attributes['_pending_id'] = new Date().getTime();
    ctx.callbacks.onPending(request.model);
    if (ctx.timeout == null) {
      consume(ctx);
    }
    return deferred.resolve(request.model.attributes);
  }
  console.log('[pushRequest] -- Try sync');
  Backbone.sync(method, request.model, options).done(function(value) {
    console.log('[pushRequest] -- Sync success');
    removeMethod(request, method);
    if (isRequestEmpty(request)) {
      ctx.pendingRequests.retrieveItem(request.key);
      ctx.callbacks.onSynced(request.model, value, method);
      return deferred.resolve.apply(this, arguments);
    }
  }).fail(function(error) {
    console.log('[pushRequest] -- Sync failed');
    if (!request.model.cache.enabled) {
      console.log('[pushRequest] -- sync fail. Not queued because of cache disabled');
      ctx.callbacks.onCancelled(request.model);
      return deferred.reject();
    }
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
  return Backbone.sync(method, request.model, options).done(function(value) {
    console.log('[consume] -- Sync success');
    request.model.attributes._pending_id = pendingId;
    removeMethod(request, method);
    if (isRequestEmpty(request)) {
      ctx.pendingRequests.retrieveHead();
      ctx.callbacks.onSynced(request.model, value, method);
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

  RequestManager.prototype.sync = function(method, model, options) {
    var deferred, request;
    if (options == null) {
      options = {};
    }
    model.beginSync();
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
    if (request == null) {
      deferred = $.Deferred();
      deferred.resolve();
      this.callbacks.onSynced(model);
      return deferred;
    }
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

define('mnemosyne',['require','exports','module','../app/request_manager','../app/sync_machine','../app/utils'],function (require, exports, module) {var Mnemosyne, MnemosyneCollection, MnemosyneModel, RequestManager, SyncMachine, Utils, cacheRead, defaultCacheOptions, defaultOptions, read, removeFromCache, removeFromParentCache, removePendingModel, serverRead, serverWrite, updateCache, updateParentCache, _destroy;

RequestManager = require("../app/request_manager");

SyncMachine = require("../app/sync_machine");

Utils = require("../app/utils");


/*
  ------- Private methods -------
 */

read = function(ctx, model, options) {
  var deferred;
  deferred = $.Deferred();
  if (typeof model.getKey !== 'function' || !model.cache.enabled) {
    console.log("Cache forbidden");
    return serverRead(ctx, model, options, null, deferred);
  }
  console.log("Try loading value from cache");
  Utils.store.getItem(model.getKey()).done(function(value) {
    console.log("Succeed to read from cache");
    return cacheRead(ctx, model, options, value, deferred);
  }).fail(function() {
    console.log("Fail to read from cache");
    return serverRead(ctx, model, options, null, deferred);
  });
  return deferred;
};

cacheRead = function(ctx, model, options, value, deferred) {
  if (model instanceof Backbone.Collection) {
    _.map(model.parse(value.data), function(element) {
      if (element.id == null) {
        return console.warn('New model read in cache !');
      }
    });
  }
  if (options.forceRefresh || value.expirationDate < new Date().getTime()) {
    console.log("-- cache expired");
    return serverRead(ctx, model, options, value.data, deferred);
  } else {
    console.log("-- cache valid");
    return deferred.resolve(value.data);
  }
};

serverRead = function(ctx, model, options, fallbackItem, deferred) {
  console.log("Sync from server");
  if ((fallbackItem != null) && model.cache.allowExpiredCache && !options.forceRefresh) {
    deferred.resolve(fallbackItem);
    options.silent = true;
  }
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
      if (deferred.state() !== "resolved") {
        return deferred.resolve(value);
      }
    });
  }).fail(function(error) {
    console.log("Fail sync from server");
    if (deferred.state() !== "resolved") {
      return deferred.reject.apply(this, arguments);
    }
  });
};

removeFromParentCache = function(ctx, model) {
  var deferred, deferredArray, parentKeys;
  deferred = $.Deferred();
  if (model instanceof Backbone.Collection) {
    console.warn('removeParentFromCache: collection as argument !');
    return deferred.resolve();
  }
  if (model.get('id') == null) {
    console.warn('removeParentFromCache: model is new !');
    return deferred.resolve();
  }
  parentKeys = model.getParentKeys();
  if (parentKeys.length === 0) {
    return deferred.resolve();
  }
  deferredArray = _.map(parentKeys, function(parentKey) {
    var _deferred;
    _deferred = $.Deferred();
    return Utils.store.getItem(parentKey).done(function(value) {
      var models;
      models = value.data;
      models = _.filter(models, function(m) {
        return m.id !== model.get('id');
      });
      return Utils.store.setItem(parentKey, {
        "data": models,
        "expirationDate": value.expirationDate
      }).always(function() {
        return _deferred.resolve();
      });
    }).fail(function() {
      return _deferred.resolve();
    });
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
    return removeFromParentCache(ctx, model).always(function() {
      return deferred.resolve();
    });
  });
  return deferred;
};

updateParentCache = function(ctx, model) {
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
    var _base, _deferred;
    _deferred = $.Deferred();
    console.log("Updating parent cache [" + parentKey + "]");
    if (model.get('id') == null) {
      if ((_base = ctx._offlineCollections)[parentKey] == null) {
        _base[parentKey] = [];
      }
      ctx._offlineCollections[parentKey] = Utils.addWithoutDuplicates(ctx._offlineCollections[parentKey], model);
      console.debug('model set');
      _deferred.resolve();
    } else {
      Utils.store.getItem(parentKey).done(function(value) {
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
        return Utils.store.setItem(parentKey, {
          "data": models,
          "expirationDate": 0
        }).always(function() {
          return _deferred.resolve();
        });
      }).fail(function() {
        return Utils.store.setItem(parentKey, {
          "data": [model],
          "expirationDate": 0
        }).done(function() {
          return _deferred.resolve();
        }).fail(function() {
          return _deferred.reject();
        });
      });
    }
    return _deferred;
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
  console.log("Try to write cache -- expires at " + expiredDate);
  if (model instanceof Backbone.Model && (model.get('id') == null)) {
    ctx._offlineModels = Utils.addWithoutDuplicates(ctx._offlineModels, model);
    deferred.resolve();
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
      _.map(model.parse(data), function(element) {
        if (element.id == null) {
          console.warn('New model in cache !');
          console.warn('\tmodel ', model);
          console.warn('\tdata ', data);
          return console.warn('\telement ', element);
        }
      });
    } else {
      console.warn("Wrong instance for ", model);
      return deferred.reject();
    }
    Utils.store.setItem(model.getKey(), {
      "data": data,
      "expirationDate": expiredDate
    }).done(function() {
      console.log("Succeed cache write");
      return updateParentCache(ctx, model).always(function() {
        return deferred.resolve();
      });
    }).fail(function() {
      console.log("fail cache write");
      return deferred.reject();
    });
  }
  return deferred;
};

serverWrite = function(ctx, method, model, options, deferred) {
  console.log("serverWrite");
  return updateCache(ctx, model).done(function() {
    return ctx._requestManager.sync(method, model, options).done(function(value) {
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

removePendingModel = function(ctx, model) {
  var key, parentKeys, _i, _len, _results;
  if (!model instanceof Backbone.Model) {
    return;
  }
  ctx._offlineModels = _.filter(ctx._offlineModels, function(m) {
    return m.get('_pending_id') !== model.get('_pending_id');
  });
  parentKeys = model.getParentKeys();
  _results = [];
  for (_i = 0, _len = parentKeys.length; _i < _len; _i++) {
    key = parentKeys[_i];
    _results.push(ctx._offlineCollections[key] = _.filter(ctx._offlineCollections[key], function(m) {
      return m.get('_pending_id') !== model.get('_pending_id');
    }));
  }
  return _results;
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

  Mnemosyne.prototype._offlineModels = [];

  _context = null;

  function Mnemosyne() {
    this._requestManager = new RequestManager({
      onSynced: function(model, value, method) {
        if (method !== 'delete') {
          updateCache(_context, model, value);
        }
        removePendingModel(_context, model);
        model.finishSync();
        return console.log('synced');
      },
      onPending: function(model) {
        var parentKey, parentKeys, _i, _len;
        if (model.get('id') == null) {
          _context._offlineModels = Utils.addWithoutDuplicates(_context._offlineModels, model);
          parentKeys = model.getParentKeys();
          for (_i = 0, _len = parentKeys.length; _i < _len; _i++) {
            parentKey = parentKeys[_i];
            _context._offlineCollections[parentKey] = Utils.addWithoutDuplicates(_context._offlineCollections[parentKey], model);
          }
        }
        model.pendingSync();
        return console.log('pending');
      },
      onCancelled: function(model) {
        if (model instanceof Backbone.Model) {
          if (model.get('id') == null) {
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

  Mnemosyne.prototype.cacheWrite = function(key, value) {
    var model;
    if (key instanceof Backbone.Model || key instanceof Backbone.Collection) {
      model = key;
      model.cache = _.defaults(model.cache || {}, defaultCacheOptions);
      return updateCache(_context, model);
    }
    return Utils.store.setItem(key, value);
  };

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

  Mnemosyne.prototype.cacheRemove = function(key) {
    var model;
    if (key instanceof Backbone.Model || key instanceof Backbone.Collection) {
      model = key;
      return removeFromCache(_context, model);
    }
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
        read(_context, model, options).done(function(data) {
          var collection, models, offlineModel, _i, _len;
          if (data == null) {
            data = [];
          }
          if (model instanceof Backbone.Collection) {
            collection = model;
            models = _context._offlineCollections[collection.getKey()];
            if (models != null) {
              for (_i = 0, _len = models.length; _i < _len; _i++) {
                offlineModel = models[_i];
                data.unshift(offlineModel.attributes);
              }
            }
          }
          if (typeof options.success === "function") {
            options.success(data, 'success', null);
          }
          deferred.resolve(data);
          return model.finishSync();
        }).fail(function() {
          var collection, data, models, offlineModel, _i, _len;
          if (model instanceof Backbone.Collection) {
            data = [];
            collection = model;
            models = _context._offlineCollections[collection.getKey()];
            if (models != null) {
              for (_i = 0, _len = models.length; _i < _len; _i++) {
                offlineModel = models[_i];
                data.unshift(offlineModel.attributes);
              }
              if (typeof options.success === "function") {
                options.success(data, 'success', null);
              }
              deferred.resolve(data);
              model.finishSync();
              return;
            }
          }
          deferred.reject.apply(this, arguments);
          return model.unsync();
        });
        break;
      case 'delete':
        removePendingModel(_context, model);
        removeFromCache(_context, model);
        _context._requestManager.sync(method, model, options).done(function(data) {
          return deferred.resolve.apply(this, arguments);
        }).fail(function() {
          return deferred.reject.apply(this, arguments);
        });
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