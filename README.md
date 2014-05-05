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
Your model should have those attributes
```
cache:
    useCache: boolean, default value false
    allowExpiredCache: boolean, default value true
    ttl: integer value in seconds, default value 600 # 10min
```

The `ttl` defines a date from we have to refetch the data from server.
If the `ttl` is expired and the `allowExpiredCache` is set to `true`,
then the cache value is returned, and a **silent** fetch occurs. If the 
`allowExpiredCache` is set to `false`, then the cache value is not used, and a
fetch occurs.


You can also set some `options`
```
forceRefresh: boolean, default value false
invalideCache: boolean, default value false
```

- `getPendingRequests()`

- `retryRequest(index)`

- `cancelPendingRequests()`

- `cancelPendingRequest(index)`

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
