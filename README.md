mnemosyne
===========

Make your app offline

License
=======

MIT


# Mnemosyne documentation (DRAFT)
Mnemosyne overrides **Backbone** `sync` method allowing caching requests.

- `sync(method, model, options)`
  Try to sync the model/collection as Backbone method do.
  [(See Backbonejs documentation)](http://backbonejs.org/) for sync method.
  Mnemosyne also add some options to allow you to customize the behaviour:

  ```javascript
  options:{
    forceRefresh: false // default value
  }
  ```

  Your model / collection should have those attributes:
  ```javascript
  //default values
  cache:{
    enabled: false,
    allowExpiredCache: true,
    ttl: 0 // value in seconds
  }
  ```
  The `ttl` defines the time to live of the value before considering it expired.
  If the `ttl` is expired and the `allowExpiredCache` is set to `true`,
  then the cache value is returned, and a **silent** fetch occurs. If the
  `allowExpiredCache` is set to `false`, then the cache value is not used, and a
  fetch occurs.

  As this method is asynchronous, it returns a `$.Deferred` object.
  [(See jQuery documentation)](http://api.jquery.com/category/deferred-object/)
  If the request succeeds, the deferred is resolved, and the `synced` event
  is triggered on the model.

  # Collection cache synchronisation

  Your model changes but your collection cache is not updated? Don't worry, just
  implement `getParentKeys` method in your model and Mnemosyne will handle the rest.

  `getParentKeys` returns a function computing a array of parent collections keys.
  You can use only `strings` or use `objects` to pass a filter function.

  This `filter` function will decide if you **keep** the value in the collection parent
  cache. (true to keep, false to remove).

  Example

  ```javascript
    MyAwesomeModel = Backbone.Model.extends({
      getParentKeys: function(){
        return [
          'awesome/always',
          {key: 'cool/sometimes', filter: function(model){return model.isCool()}}
        ];
      }
    });
  ```



- `getPendingRequests()`
  Return an array containing all pending requests.

- `retrySync()`
  Reset the timer and try a new synchronization.

- `cancelAllPendingRequests()`
  Clear all pending requests and unsaved models.

- `cancelPendingRequests(key)`
  Cancel the selected pending request.

- `cacheWrite(key, value)`
  Write the value in cache. You can give a model / collection as only arguments.

- `cacheRead(key)`
  Load attributes from cache. You can give a model / collection as only arguments.

- `cacheRemove(key)`
  Remove the item corresponding to the key and returns it.
  You can give a model / collection as only arguments.

- `cacheClear()`
  Wipe all the cache and call `Mnemosyne.cancelAllPendingRequests` method.

  ** Important **

  There is currently no smart cache memory management, and as it is stored in
  local storage, it is highly probable which one day the cache turn full.
  In this case, the cache is automatically cleared. However you can choose to
  keep some key in cache, passing them to Mnemosyne constructor.

  ```javascript
    mnemosyne = new Mnemosyne({
      protectedKeys: ['some', 'protected', 'keys']
    });
  ```

- `subscribe(event, key, callback)`
  Allow to register callbacks on severals events.

  `event` supported list is:
    - `connectionLost` fired when the connection is lost
    - `connectionRecovered` fired when the connection is recovered

  `key` is used to unregister easily callbacks even when using anonymous function.

  Example

  ```javascript
    mnemosyne = new Mnemosyme();
    mnemosyne.subscribe('connectionLost', 'myFuncKey', function(isOnline){
      console.info("You are offline");
    });
    // Will print "You are offline" on 'connectionLost'

  ```

- `unsubscribe(key)`
  Remove the registered callback.

  Example

  ```javascript
    mnemosyne.unsubscribe('myFuncKey');
    // Will unregister 'myFuncKey' callback

  ```


# Events
Severals events can be triggered on models to allow views to listen and react.

- `'syncing'`
  The model starts synchronization.

- `'pending'`
  The synchronization with the server is not yet possible, but an other try
  will be triggered later.

- `'synced'`
  The synchronization is a success.

- `'unsynced'`
  The synchronization has failed or has been cancelled.
