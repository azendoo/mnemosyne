'use strict'

# Simple finite state machine for synchronization of models/collections
# Four states: unsynced, syncing, synced and pending
# Several transitions between them
# Fires Backbone events on every transition
# (unsynced, syncing, synced, pending; syncStateChange)
# Provides shortcut methods to call handlers when a given state is reached
# (named after the events above)

UNSYNCED = 'unsynced'
SYNCING  = 'syncing'
PENDING  = 'pending'
SYNCED   = 'synced'

STATE_CHANGE = 'syncStateChange'

SyncMachine =
  _syncState: UNSYNCED
  _previousSyncState: null

  # Get the current state
  # ---------------------

  syncState: ->
    @_syncState

  isUnsynced: ->
    @_syncState is UNSYNCED

  isSynced: ->
    @_syncState is SYNCED

  isSyncing: ->
    @_syncState is SYNCING

  isPending: ->
    @_syncState is PENDING

  # Transitions
  # -----------

  unsync: ->
    if @_syncState in [SYNCING, PENDING, SYNCED]
      @_previousSync = @_syncState
      @_syncState = UNSYNCED
      @trigger @_syncState, this, @_syncState
      @trigger STATE_CHANGE, this, @_syncState
    # when UNSYNCED do nothing
    return

  beginSync: ->
    if @_syncState in [UNSYNCED, SYNCED, PENDING]
      @_previousSync = @_syncState
      @_syncState = SYNCING
      @trigger @_syncState, this, @_syncState
      @trigger STATE_CHANGE, this, @_syncState
    # when SYNCING do nothing
    return

  pendingSync: ->
    if @_syncState is SYNCING
      @_previousSync = @_syncState
      @_syncState = PENDING
      @trigger @_syncState, this, @_syncState
      @trigger STATE_CHANGE, this, @_syncState
    # when PENDING do nothing
    return

  finishSync: ->
    if @_syncState in [SYNCING, PENDING]
      @_previousSync = @_syncState
      @_syncState = SYNCED
      @trigger @_syncState, this, @_syncState
      @trigger STATE_CHANGE, this, @_syncState
    # when SYNCED, UNSYNCED do nothing
    return

  abortSync: ->
    if @_syncState in SYNCING
      @_syncState = @_previousSync
      @_previousSync = @_syncState
      @trigger @_syncState, this, @_syncState
      @trigger STATE_CHANGE, this, @_syncState
    # when UNSYNCED, SYNCED do nothing
    return


# Create shortcut methods to bind a handler to a state change
# -----------------------------------------------------------

for event in [UNSYNCED, SYNCING, SYNCED, PENDING, STATE_CHANGE]
  do (event) ->
    SyncMachine[event] = (callback, context = this) ->
      @on event, callback, context
      callback.call(context) if @_syncState is event

# You’re frozen when your heart’s not open.
Object.freeze? SyncMachine

# Return our creation.
module.exports = SyncMachine
