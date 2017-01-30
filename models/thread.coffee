_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

THREADS_TABLE = 'threads'
CREATOR_ID_INDEX = 'creatorId'
LAST_UPDATE_TIME_INDEX = 'lastUpdateTime'

defaultThread = (thread) ->
  unless thread?
    return null

  _.defaults thread, {
    id: uuid.v4()
    creatorId: null
    groupId: null
    title: null
    body: null
    summary: null
    headerImage: null
    type: 'text'
    upvotes: 0
    downvotes: 0
    upvoteIds: []
    downvoteIds: []
    data: {}
    lastUpdateTime: new Date()
    addTime: new Date()
  }

class ThreadModel
  RETHINK_TABLES: [
    {
      name: THREADS_TABLE
      options: {}
      indexes: [
        {name: CREATOR_ID_INDEX}
        {name: LAST_UPDATE_TIME_INDEX}
      ]
    }
  ]

  create: (thread) ->
    thread = defaultThread thread

    r.table THREADS_TABLE
    .insert thread
    .run()
    .then ->
      thread

  getById: (id) ->
    r.table THREADS_TABLE
    .get id
    .run()
    .then defaultThread

  getAll: ({limit} = {}) ->
    limit ?= 10

    r.table THREADS_TABLE
    .orderBy {index: r.desc(LAST_UPDATE_TIME_INDEX)}
    .limit limit
    .run()
    .map defaultThread

  updateById: (id, diff) ->
    r.table THREADS_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table THREADS_TABLE
    .get id
    .delete()
    .run()

  hasPermissionByIdAndUser: (id, user, {level} = {}) =>
    unless user
      return false

    @getById id
    .then (thread) =>
      @hasPermission thread, user, {level}

  hasPermission: (thread, user, {level} = {}) ->
    unless thread and user
      return false

    level ?= 'member'

    return switch level
      when 'admin'
      then thread.creatorId is user.id
      # member
      else thread.userIds?.indexOf(user.id) isnt -1

  sanitize: _.curry (requesterId, thread) ->
    _.pick thread, [
      'id'
      'creatorId'
      'creator'
      'type'
      'title'
      'summary'
      'headerImage'
      'body'
      'data'
      'comments'
      'commentCount'
      'score'
      'addTime'
      'lastUpdateTime'
      'embedded'
    ]

module.exports = new ThreadModel()
