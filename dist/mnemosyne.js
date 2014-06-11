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

define('../app/request_manager',['require','exports','module','../app/magic_queue'],function (require, exports, module) {var MAX_INTERVAL, MIN_INTERVAL, MagicQueue, RequestManager, cancelRequest, consume, getMethod, isConnected, pushRequest, resetTimer, smartRequest;

MagicQueue = require("../app/magic_queue");


/*
  TODO
  * limit the number of pending requests ?
  * manage the database limit
  * documentation
  * set models status according to events, and update the cache
  * request db persistence
  * Discuss about the status 4XX and 5XX
 */

MAX_INTERVAL = 64000;

MIN_INTERVAL = 250;


/*
  ------- Private methods -------
 */

resetTimer = function(ctx) {
  clearTimeout(ctx.timeout);
  ctx.timeout = null;
  return ctx.interval = MIN_INTERVAL;
};

cancelRequest = function(ctx, request) {
  return request.model.unsync();
};

pushRequest = function(ctx, request) {
  var deferred, method, options;
  deferred = $.Deferred();
  if (request == null) {
    return deferred.reject();
  }
  ctx.pendingRequests.addTail(request.key, request);
  method = getMethod(request);
  options = request.methods[method];
  if (!isConnected()) {
    console.log('[pushRequest] -- not connected. Push request in queue');
    request.model.pendingSync();
    if (ctx.timeout == null) {
      consume(ctx);
    }
    return deferred.resolve(request.model.attributes);
  }
  console.log('[pushRequest] -- Try sync');
  Backbone.sync(method, request.model, options).done(function() {
    console.log('[pushRequest] -- Sync success');
    localStorage.removeItem(request.key);
    ctx.pendingRequests.retrieveItem(request.key);
    deferred.resolve.apply(this, arguments);
    return request.model.finishSync();
  }).fail(function(error) {
    console.log('[pushRequest] -- Sync failed');
    deferred.resolve(request.model.attributes);
    request.model.pendingSync();
    if (ctx.timeout == null) {
      return consume(ctx);
    }
  });
  return deferred;
};

consume = function(ctx) {
  var method, options, request;
  request = ctx.pendingRequests.getHead();
  if (request == null) {
    console.log('[consume] -- done! 0 pending');
    resetTimer(ctx);
    return;
  }
  if (!isConnected()) {
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
  console.log('[consume] -- try sync ', method);
  return Backbone.sync(method, request.model, options).done(function() {
    console.log('[consume] --Sync success');
    ctx.pendingRequests.retrieveHead();
    ctx.interval = MIN_INTERVAL;
    return request.model.finishSync();
  }).fail(function(error) {
    var status;
    console.log('[consume] -- Sync failed', error);
    status = error.readyState;
    switch (status) {
      case 4:
      case 5:
        ctx.pendingRequests.retrieveHead();
        request.model.unsync();
        break;
      default:
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

isConnected = function() {
  return window.navigator.onLine;
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

getMethod = function(request) {
  if (request.methods['create']) {
    return 'create';
  } else if (request.methods['update']) {
    return 'udpate';
  } else if (request.methods['delete']) {
    return 'delete';
  } else {
    return console.error("No method found !", request);
  }
};


/*
  ------- Public methods -------
 */

module.exports = RequestManager = (function() {

  /*
    request:
      method
      model
      options
      key
   */
  function RequestManager() {
    this.pendingRequests = new MagicQueue();
    resetTimer(this);
  }

  RequestManager.prototype.clear = function() {
    this.pendingRequests.getQueue().map((function(_this) {
      return function(request) {
        return cancelRequest(_this, request);
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
    return cancelRequest(this, request);
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

define('mnemosyne',['require','exports','module','../app/request_manager','../app/sync_machine'],function (require, exports, module) {var Collection, Mnemosyne, Model, RequestManager, SyncMachine, cacheRead, cacheWrite, defaultCacheOptions, defaultOptions, load, mnemosyne, read, serverRead, serverWrite, store, wrapPromise,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

RequestManager = require("../app/request_manager");

SyncMachine = require("../app/sync_machine");


/*
  TODO
  * set db infos
  * documentation
 */


/*
  ------- Private methods -------
 */

store = {};

store.getItem = function(key) {
  var value;
  value = localStorage.getItem(key);
  if (value != null) {
    return $.Deferred().resolve(JSON.parse(value));
  }
  return $.Deferred().reject();
};

store.setItem = function(key, value) {
  localStorage.setItem(key, JSON.stringify(value));
  return $.Deferred().resolve();
};

store.clear = function() {
  localStorage.clear();
  return $.Deferred().resolve();
};

read = function(ctx, model, options, deferred) {
  if (((typeof model.getKey === "function" ? model.getKey() : void 0) == null) || !model.cache.enabled) {
    console.log("Cache forbidden");
    return serverRead(ctx, model, options, null, deferred);
  }
  console.log("Try loading value from cache");
  return load(ctx, model.getKey()).done(function(item) {
    console.log("Succeed to read from cache");
    return cacheRead(ctx, model, options, item, deferred);
  }).fail(function() {
    console.log("Fail to read from cache");
    return serverRead(ctx, model, options, null, deferred);
  });
};

cacheRead = function(ctx, model, options, item, deferred) {
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
    if (typeof options.success === "function") {
      options.success(fallbackItem.value, 'success', null);
    }
    deferred.resolve(fallbackItem.value);
    model.finishSync();
    options.silent = true;
  }
  return Backbone.sync('read', model, options).done(function() {
    console.log("Succeed sync from server");
    return cacheWrite(ctx, model.getKey(), arguments[0], model.cache.ttl).always(function() {
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

cacheWrite = function(ctx, key, value, ttl) {
  var deferred, expiredDate;
  deferred = $.Deferred();
  expiredDate = (new Date()).getTime() + ttl * 1000;
  console.log("Try to write cache -- expires at " + expiredDate);
  store.setItem(key, {
    "value": value,
    "expirationDate": expiredDate
  }).then(function() {
    console.log("Succeed cache write");
    return deferred.resolve.apply(this, arguments);
  }, function() {
    console.log("fail cache write");
    return deferred.reject.apply(this, arguments);
  });
  return deferred;
};

serverWrite = function(ctx, method, model, options, deferred) {
  console.log("serverWrite");
  return cacheWrite(ctx, model.getKey(), model.attributes, model.cache.ttl).done(function() {
    return ctx.safeSync(method, model, options).done(function() {
      return deferred.resolve.apply(this, arguments);
    }).fail(function() {
      return deferred.reject.apply(this, arguments);
    });
  }).fail(function() {
    console.log("fail");
    deferred.reject.apply(this, arguments);
    return model.unsync();
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


/*
  ------- Public methods -------
 */

defaultOptions = {
  forceRefresh: false
};

defaultCacheOptions = {
  ttl: 600,
  enabled: false,
  allowExpiredCache: true
};

module.exports = Mnemosyne = (function(_super) {
  var _context;

  __extends(Mnemosyne, _super);

  _context = null;

  function Mnemosyne() {
    Mnemosyne.__super__.constructor.apply(this, arguments);
    _context = this;
  }

  Mnemosyne.prototype.cacheWrite = function(model) {
    model.cache = _.defaults(model.cache || {}, defaultCacheOptions);
    return cacheWrite(_context, model.getKey(), model.attributes, model.cache.ttl);
  };

  Mnemosyne.prototype.cacheRead = function(key) {
    var deferred;
    deferred = $.Deferred();
    store.getItem(key).done(function(item) {
      return deferred.resolve(item.value);
    }).fail(function() {
      return deferred.reject();
    });
    return deferred;
  };

  Mnemosyne.prototype.cacheRemove = function(key) {
    return store.removeItem(key);
  };

  Mnemosyne.prototype.clearCache = function() {
    return store.clear();
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
        read(_context, model, options, deferred);
        break;
      default:
        serverWrite(_context, method, model, options, deferred);
    }
    return deferred;
  };

  Mnemosyne.prototype.SyncMachine = SyncMachine;

  return Mnemosyne;

})(RequestManager);

mnemosyne = new Mnemosyne();

Backbone.Model = Model = (function(_super) {
  __extends(Model, _super);

  function Model() {
    return Model.__super__.constructor.apply(this, arguments);
  }

  Model.prototype.initialize = function() {
    Model.__super__.initialize.apply(this, arguments);
    return _.extend(this, SyncMachine);
  };

  Model.prototype.sync = function() {
    return mnemosyne.sync.apply(this, arguments);
  };

  Model.prototype.destroy = function() {
    if (this.isNew()) {
      return this.cancelPendingRequest(this.getKey());
    } else {
      return Model.__super__.destroy.apply(this, arguments);
    }
  };

  return Model;

})(Backbone.Model);

Backbone.Collection = Collection = (function(_super) {
  __extends(Collection, _super);

  function Collection() {
    return Collection.__super__.constructor.apply(this, arguments);
  }

  Collection.prototype.initialize = function() {
    Collection.__super__.initialize.apply(this, arguments);
    return _.extend(this, SyncMachine);
  };

  Collection.prototype.sync = function() {
    return mnemosyne.sync.apply(this, arguments);
  };

  Collection.prototype.destroy = function() {
    if (this.isNew()) {
      return this.cancelPendingRequest(this.getKey());
    } else {
      return Collection.__super__.destroy.apply(this, arguments);
    }
  };

  return Collection;

})(Backbone.Collection);

});


  return require('mnemosyne');
}));