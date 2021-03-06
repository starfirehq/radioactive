_ = require 'lodash'
Promise = require 'bluebird'

CacheService = require '../services/cache'
GroupClan = require './group_clan'
Group = require './group'
GroupUser = require './group_user'
Conversation = require './conversation'
ClashRoyaleClan = require './clash_royale_clan'
config = require '../config'

STALE_INDEX = 'stale'
CLAN_ID_GAME_KEY_INDEX = 'clanIdGameId'

ONE_DAY_S = 3600 * 24
CODE_LENGTH = 6

class ClanModel
  constructor: ->
    @GameClans =
      "#{'clash-royale'}": ClashRoyaleClan

  getByClanIdAndGameKey: (clanId, gameKey, {preferCache, retry} = {}) =>
    get = =>
      prefix = CacheService.PREFIXES.GROUP_CLAN_CLAN_ID_GAME_KEY
      cacheKey = "#{prefix}:#{clanId}:#{gameKey}"
      getGroupClan = ->
        GroupClan.getByClanIdAndGameKey clanId, gameKey
      Promise.all [
        if preferCache
          CacheService.preferCache cacheKey, getGroupClan, {
            ignoreNull: true, expireSeconds: ONE_DAY_S
          }
        else
          getGroupClan()

        @GameClans[gameKey].getById clanId
      ]
      .then ([groupClan, gameClan]) ->
        if groupClan and gameClan
          _.merge groupClan, gameClan

    if preferCache
      prefix = CacheService.PREFIXES.CLAN_CLAN_ID_GAME_KEY
      cacheKey = "#{prefix}:#{clanId}:#{gameKey}"
      CacheService.preferCache cacheKey, get, {
        expireSeconds: ONE_DAY_S, ignoreNull: true
      }
    else
      get()

  upsertByClanIdAndGameKey: (clanId, gameKey, diff) =>
    prefix = CacheService.PREFIXES.GROUP_CLAN_CLAN_ID_GAME_KEY
    cacheKey = "#{prefix}:#{clanId}:#{gameKey}"
    CacheService.preferCache cacheKey, ->
      GroupClan.create {clanId, gameKey}
    , {ignoreNull: true, expireSeconds: ONE_DAY_S}
    .then =>
      @GameClans[gameKey].upsertById clanId, diff

    # .tap ->
    #   key = CacheService.PREFIXES.CLAN_PLAYERS + ':' + clanId
    #   CacheService.deleteByKey key

  createGroup: ({userId, creatorId, name, clanId}) ->
    Group.create {
      name: name
      creatorId: creatorId
      mode: 'private'
      gameKeys: ['clash-royale']
      clanIds: [clanId]
    }
    .tap (group) ->
      Promise.all _.filter [
        if userId
          GroupUser.upsert {groupId: group.id, userId: userId}
        Conversation.upsert {
          groupId: group.id
          data:
            name: 'general'
          type: 'channel'
        }
      ]
    .tap (group) ->
      GroupClan.updateByClanIdAndGameKey clanId, 'clash-royale', {
        groupId: group.id
      }

  sanitizePublic: _.curry (requesterId, clan) ->
    sanitizedClan = _.pick clan, [
      'id'
      'gameKey'
      'clanId'
      'groupId'
      'creatorId'
      'code'
      'data'
      'players'
      'group'
      'lastUpdateTime'
      'embedded'
    ]
    sanitizedClan

  sanitize: _.curry (requesterId, clan) ->
    sanitizedClan = _.pick clan, [
      'id'
      'gameKey'
      'clanId'
      'groupId'
      'creatorId'
      'code'
      'data'
      'password'
      'players'
      'group'
      'lastUpdateTime'
      'embedded'
    ]
    sanitizedClan

module.exports = new ClanModel()
