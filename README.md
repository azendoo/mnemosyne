mnemosyne
===========

Make your app offline

License
=======

MIT


# Api documentation (DRAFT)
### constructor

### reset()
Reset the entire module!
```
mnemosyne = new Mnemosyne();
mnemosyne.reset();
```
### sync(method, model, options)
See Backbonejs documentation for sync method.
Mnemosyne also add some options to allow you to customize the behaviour.

```
options:
  forceRefresh: boolean, default value false
```

Your model should have those attributes
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


- `sync(method, model, options)`
  Try to sync the model.
  As this method is asynchronous, it returns a `$.Deferred` object.
  [(See jQuery documentation)](http://api.jquery.com/category/deferred-object/)

  If the request succeeds, the deferred is resolved, and the `synced` event
  is triggered on the model.

  // TODO



- `getPendingRequests()`
  Return an array containing all pending requests

- `retrySync()`
  Reset the timer and try a new synchronization.

- `clear()`
  Clear all pending requests.


- `cancelPendingRequests(key)`
  Cancel the selected pending request.

- `cacheWrite(model)`
  Save the model attributes in cache.

- `cacheRead(key)`
  Load attributes from cache.

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
