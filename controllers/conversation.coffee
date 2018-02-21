_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
Conversation = require '../models/conversation'
Group = require '../models/group'
GroupAuditLog = require '../models/group_audit_log'
GroupUser = require '../models/group_user'
Language = require '../models/language'
Event = require '../models/event'
EmbedService = require '../services/embed'
config = require '../config'

defaultEmbed = [EmbedService.TYPES.CONVERSATION.USERS]
lastMessageEmbed = [
  EmbedService.TYPES.CONVERSATION.LAST_MESSAGE
  EmbedService.TYPES.CONVERSATION.USERS
]

class ConversationCtrl
  create: ({userIds, groupId, name, description}, {user}) ->
    userIds ?= []
    userIds = _.uniq userIds.concat [user.id]

    name = name and _.kebabCase(name.toLowerCase()).replace(/[^0-9a-z-]/gi, '')

    if groupId
      conversation = Conversation.getByGroupIdAndName groupId, name
      hasPermission = GroupUser.hasPermissionByGroupIdAndUser groupId, user, [
        GroupUser.PERMISSIONS.MANAGE_INFO
      ]
      .then (hasPermission) ->
        unless hasPermission
          router.throw {status: 400, info: 'You don\'t have permission'}
        hasPermission
    else
      conversation = Conversation.getByUserIds userIds
      hasPermission = Promise.resolve true

    Promise.all [conversation, hasPermission]
    .then ([conversation, hasPermission]) ->
      if groupId
        GroupAuditLog.upsert {
          groupId
          userId: user.id
          actionText: Language.get 'audit.addChannel', {
            replacements:
              channel: name
            language: user.language
          }
        }
      return conversation or Conversation.upsert({
        userIds
        groupId
        data: {name, description}
        type: if groupId then 'channel' else 'pm'
      }, {userId: user.id})

  updateById: ({id, name, description, isSlowMode, slowModeCooldown}, {user}) ->
    name = name and _.kebabCase(name.toLowerCase()).replace(/[^0-9a-z-]/gi, '')

    Conversation.getById id
    .tap (conversation) ->
      groupId = conversation.groupId
      GroupUser.hasPermissionByGroupIdAndUser groupId, user, [
        GroupUser.PERMISSIONS.MANAGE_INFO
      ]
      .then (hasPermission) ->
        unless hasPermission
          router.throw {status: 400, info: 'You don\'t have permission'}
      .then ->
        GroupAuditLog.upsert {
          groupId: conversation.groupId
          userId: user.id
          actionText: Language.get 'audit.updateChannel', {
            replacements:
              channel: name or conversation.name
            language: user.language
          }
        }
        Conversation.upsert {
          id: conversation.id
          userId: conversation.userId
          groupId: conversation.groupId
          data: _.defaults {
            name, description, isSlowMode, slowModeCooldown
          }, conversation.data
        }

  getAll: ({}, {user}) ->
    Conversation.getAllByUserId user.id
    .map EmbedService.embed {embed: lastMessageEmbed}
    .map Conversation.sanitize null

  getById: ({id}, {user}) ->
    Conversation.getById id
    .then EmbedService.embed {embed: defaultEmbed}
    .tap (conversation) ->
      Promise.all [
        if conversation.groupId
          groupId = conversation.groupId
          GroupUser.hasPermissionByGroupIdAndUser groupId, user, [
            GroupUser.PERMISSIONS.READ_MESSAGE
          ], {channelId: id}
          .then (hasPermission) ->
            unless hasPermission
              router.throw status: 400, info: 'no permission'
        else if conversation.eventId
          Event.hasPermissionByIdAndUser conversation.eventId, user
          .then (hasPermission) ->
            unless hasPermission
              router.throw status: 400, info: 'no permission'
        else if not _.find(conversation.userIds, (userId) ->
          "#{userId}" is "#{user.id}"
        )
          router.throw status: 400, info: 'no permission'
          Promise.resolve null

        # TODO: different way to track if read (groups get too large)
        # should store lastReadTime on user for each group
        if conversation.groupId
          Promise.resolve null
        else
          Conversation.markRead conversation, user.id
      ]
    .then Conversation.sanitize null


module.exports = new ConversationCtrl()
