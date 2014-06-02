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

define('../app/request_manager',['require','exports','module','../app/magic_queue'],function (require, exports, module) {var MAX_INTERVAL, MIN_INTERVAL, MagicQueue, RequestManager, cancelRequest, consume, defaultEventMap, getMethod, isConnected, pushRequest, resetTimer, smartRequest;

MagicQueue = require("../app/magic_queue");


/*
  TODO
  * limit the number of pending requests ?
  * manage the database limit
  * documentation
  * set models status according to events, and update the cache
  * manage connectivity
  * request db persistence
  * set default values for MAX et MIN interval

  Manage status code errors to cancel the request
 */

defaultEventMap = {
  'syncing': 'syncing',
  'pending': 'pending',
  'synced': 'synced',
  'unsynced': 'unsynced'
};

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
  return request.model.trigger(ctx.eventMap['unsynced']);
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
    request.model.trigger(ctx.eventMap['pending']);
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
    return request.model.trigger(ctx.eventMap['synced']);
  }).fail(function(error) {
    console.log('[pushRequest] -- Sync failed');
    deferred.resolve(request.model.attributes);
    request.model.trigger(ctx.eventMap['pending']);
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
    return request.model.trigger(ctx.eventMap['synced']);
  }).fail(function(error) {
    console.log('[consume] -- Sync failed', error);
    ctx.pendingRequests.retrieveHead();
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
  if ((request.methods['destroy'] != null) && (request.methods['create'] != null)) {
    ctx.pendingRequests.retrieveItem(request.key);
    return null;
  }
  if (((request.methods['create'] != null) || (request.methods['destroy'] != null)) && (request.methods['update'] != null)) {
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
  function RequestManager(eventMap) {
    if (eventMap == null) {
      eventMap = {};
    }
    this.eventMap = _.extend(defaultEventMap, eventMap);
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
    return pushRequest(this, request);
  };

  return RequestManager;

})();

});

define('mnemosyne',['require','exports','module','../app/request_manager'],function (require, exports, module) {var Mnemosyne, RequestManager, cacheRead, cacheWrite, defaultConstants, defaultOptions, load, read, serverRead, serverWrite, store, wrapPromise,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

RequestManager = require("../app/request_manager");


/*
  TODO
  * set db infos
  * documentation
  * manage default options
  * manage key conflicts
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

defaultOptions = {
  forceRefresh: false,
  invalidCache: false
};

defaultConstants = {
  ttl: 600 * 1000,
  cache: true,
  allowExpiredCache: true
};

read = function(ctx, model, options, deferred) {
  if (((typeof model.getKey === "function" ? model.getKey() : void 0) == null) || !model.constants.cache) {
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
    return model.trigger(ctx.eventMap['synced']);
  }
};

serverRead = function(ctx, model, options, fallbackItem, deferred) {
  console.log("Sync from server");
  return Backbone.sync('read', model, options).done(function() {
    console.log("Succeed sync from server");
    return cacheWrite(ctx, model.getKey(), arguments[0], model.constants.ttl).always(function() {
      model.trigger(ctx.eventMap['synced']);
      return deferred.resolve.apply(this, arguments);
    });
  }).fail(function(error) {
    console.log("Fail sync from server");
    if ((fallbackItem != null) && model.constants.allowExpiredCache) {
      if (typeof options.success === "function") {
        options.success(fallbackItem.value, 'success', null);
      }
      if (deferred != null) {
        deferred.resolve(fallbackItem.value);
      }
      return model.trigger(ctx.eventMap['synced']);
    } else {
      deferred.reject.apply(this, arguments);
      return model.trigger(ctx.eventMap['unsynced']);
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
  if (ttl == null) {
    ttl = 600000;
  }
  expiredDate = (new Date()).getTime() + ttl;
  console.log("Try to write cache");
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
  return cacheWrite(ctx, model.getKey(), model.attributes, model.constants.ttl).done(function() {
    return ctx.safeSync(method, model, options).done(function() {
      return deferred.resolve.apply(this, arguments);
    }).fail(function() {
      return deferred.reject.apply(this, arguments);
    });
  }).fail(function() {
    console.log("fail");
    deferred.reject.apply(this, arguments);
    return model.trigger(ctx.eventMap['unsynced']);
  });
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
  }
});


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

module.exports = Mnemosyne = (function(_super) {
  var _context;

  __extends(Mnemosyne, _super);

  _context = null;

  function Mnemosyne() {
    Mnemosyne.__super__.constructor.apply(this, arguments);
    _context = this;
  }

  Mnemosyne.prototype.cacheWrite = function(model) {
    model.constants = _.defaults(model.constants || {}, defaultConstants);
    return cacheWrite(_context, model.getKey(), model.attributes, model.constants.ttl);
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


  /*
    Cancel all pending requests.
   */

  Mnemosyne.prototype.clear = function() {
    return Mnemosyne.__super__.clear.apply(this, arguments);
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
    options = _.defaults(options, defaultOptions);
    model.constants = _.defaults(model.constants || {}, defaultConstants);
    deferred = $.Deferred();
    console.log(model.getKey());
    model.trigger(_context.eventMap['syncing']);
    switch (method) {
      case 'read':
        read(_context, model, options, deferred);
        break;
      default:
        serverWrite(_context, method, model, options, deferred);
    }
    return deferred;
  };

  return Mnemosyne;

})(RequestManager);

});


  return require('mnemosyne');
}));