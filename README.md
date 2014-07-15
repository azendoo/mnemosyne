mnemosyne
===========

Make your app offline

License
=======

MIT


# Api documentation (DRAFT)

Mnemosyne overrides **Backbone** `sync` method allowing caching requests.

- `sync(method, model, options)`
  Try to sync the model/collection as Backbone method do.
  [(See Backbonejs documentation)](http://backbonejs.org/) for sync method.
  Mnemosyne also add some options to allow you to customize the behaviour.

  ```
  options:
    forceRefresh: boolean, default value false
  ```

  Your model/collection should have those attributes
  ```
  cache:
    enabled: boolean, default value false
    allowExpiredCache: boolean, default value true
    ttl: integer value in seconds, default value 600 # 10min
  ```

  The `ttl` defines a date from we have to refetch the data from server.
  If the `ttl` is expired and the `allowExpiredCache` is set to `true`,
  then the cache value is returned, and a **silent** fetch occurs. If the
  `allowExpiredCache` is set to `false`, then the cache value is not used, and a
  fetch occurs.


  As this method is asynchronous, it returns a `$.Deferred` object.
  [(See jQuery documentation)](http://api.jquery.com/category/deferred-object/)

  If the request succeeds, the deferred is resolved, and the `synced` event
  is triggered on the model.


- `subscribe(event, key, callback)`
  Allow to register callbacks on severals events.
  `event` supported list is:
    - `connectionLost` fired when the connection is lost
    - `connectionRecovered` fired when the connection is recovered


- `unsubscribe(event, key)`
  Remove the registered callback.

- `getPendingRequests()`
  Return an array containing all pending requests.

- `retrySync()`
  Reset the timer and try a new synchronization.

- `clear()`
  Clear all pending requests, remove all pendings models and collections.

- `cancelPendingRequests(key)`
  Cancel the selected pending request.

- `cacheWrite(model)`
  Save the model attributes in cache.

- `cacheRead(key)`
  Load attributes from cache.

- `cacheRemove(key)`
  Remove the item corresponding to the key and returns it.

# Events
Severals events can be triggered on models to allow views to listen and react.

- `'syncing'` DRAFT
  The model starts synchronization.

- `'pending'` DRAFT
  The synchronization with the server is not yet possible, but an other try
  will be triggered later.

- `'synced'` DRAFT
  The synchronization is a success.

- `'unsynced'` DRAFT
  The synchronization has failed or has been cancelled.
