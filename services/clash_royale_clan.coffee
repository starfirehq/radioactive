Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

Clan = require '../models/clan'
Player = require '../models/player'
# ClashRoyaleTopClan = require '../models/clash_royale_top_clan'
CacheService = require './cache'
PushNotificationService = require '../services/push_notification'
ClashRoyaleKueService = require '../services/clash_royale_kue'
User = require '../models/user'
config = require '../config'

MAX_TIME_TO_COMPLETE_MS = 60 * 30 * 1000 # 30min
CLAN_STALE_TIME_S = 3600 * 12 # 12hr
MIN_TIME_BETWEEN_UPDATES_MS = 60 * 20 * 1000 # 20min
TWENTY_THREE_HOURS_S = 3600 * 23
BATCH_REQUEST_SIZE = 50
GAME_ID = config.CLASH_ROYALE_ID

processingP = 0

class ClashRoyaleClan
  formatClan: (clan) ->
    _.pick clan, ['name', 'badge', 'type', 'description', 'trophies',
      'minTrophies', 'donations', 'region']

  formatClanPlayer: (player) ->
    {
      playerId: player.tag
      role: player.role
      donations: player.donations
      clanChestCrowns: player.clanChestCrowns
    }

  updateClan: ({userId, clan, tag}) =>
    unless tag and clan
      processingP -= 1
      return Promise.resolve null

    players = _.map clan.members, @formatClanPlayer

    diff = {
      lastUpdateTime: new Date()
      clanId: tag
      data: @formatClan clan
      players: players
    }

    playerIds = _.map players, 'playerId'
    Player.getAllByPlayerIdsAndGameId playerIds, GAME_ID
    .then (players) ->
      Promise.map playerIds, (playerId) ->
        unless _.find players, {playerId}
          ClashRoyaleKueService.refreshByPlayerTag playerId, {
            priority: 'normal'
          }
          .then ->
            Player.upsertByPlayerIdAndGameId playerId, GAME_ID, {
              hasUserId: true
            }

    Clan.upsertByClanIdAndGameId tag, GAME_ID, diff
    .catch (err) ->
      console.log 'clan err', err

  updateStaleClan: ({force} = {}) ->
    Clan.getStaleByGameId GAME_ID, {
      type: 'data'
      staleTimeS: if force then 0 else CLAN_STALE_TIME_S
    }
    .map ({clanId}) -> clanId
    .then (clanIds) ->
      console.log 'staledata', clanIds.length, new Date()
      Clan.updateByClanIdsAndGameId clanIds, GAME_ID, {
        lastUpdateTime: new Date()
      }
      clanIdChunks = _.chunk clanIds, BATCH_REQUEST_SIZE
      Promise.map clanIdChunks, (clanIds) ->
        tagsStr = clanIds.join ','
        request "#{config.CR_API_URL}/clans/#{tagsStr}", {
          json: true
          qs:
            callbackUrl:
              "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updateClan"
        }
        .catch (err) ->
          console.log 'err staleClan'
          console.log err

  processUpdateClan: ({userId, tag, clan}) =>
    console.log clan
    @updateClan {userId, tag, clan}

  # getTopClans: ->
  #   request "#{config.CR_API_URL}/clans/top", {json: true}
  #
  # updateTopClans: =>
  #   if config.ENV is config.ENVS.DEV
  #     return
  #   @getTopClans().then (topClans) =>
  #     Promise.map topClans, (clan, index) =>
  #       rank = index + 1
  #       clanId = clan.clanTag
  #       Clan.getByClanIdAndGameId clanId, GAME_ID
  #       .then (player) =>
  #         if player?.verifiedUserId
  #           Clan.updateById player.id, {
  #             data:
  #               trophies: clan.trophies
  #               name: clan.name
  #           }
  #         else
  #           User.create {}
  #           .then ({id}) =>
  #             userId = id
  #             @refreshByClanId clanId, {
  #               userId: userId, priority: 'normal'
  #             }
  #
  #       .then ->
  #         ClashRoyaleTopClan.upsertByRank rank, {
  #           clanId: clanId
  #         }


module.exports = new ClashRoyaleClan()
