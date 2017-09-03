Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

GroupClan = require '../models/group_clan'
Clan = require '../models/clan'
Player = require '../models/player'
User = require '../models/user'
ClashRoyaleClanRecord = require '../models/clash_royale_clan_record'
ClashRoyalePlayerRecord = require '../models/clash_royale_player_record'
UserPlayer = require '../models/user_player'
# ClashRoyaleTopClan = require '../models/clash_royale_top_clan'
CacheService = require './cache'
PushNotificationService = require './push_notification'
ClashRoyaleAPIService = require './clash_royale_api'
config = require '../config'

MAX_TIME_TO_COMPLETE_MS = 60 * 30 * 1000 # 30min
CLAN_STALE_TIME_S = 3600 * 12 # 12hr
MIN_TIME_BETWEEN_UPDATES_MS = 60 * 20 * 1000 # 20min
TWENTY_THREE_HOURS_S = 3600 * 23
BATCH_REQUEST_SIZE = 50
GAME_ID = config.CLASH_ROYALE_ID

class ClashRoyaleClan

  updateClan: ({userId, clan, tag}) ->
    unless tag and clan
      return Promise.resolve null

    diff = {
      lastUpdateTime: new Date()
      clanId: tag
      data: clan
      # players: players
    }

    Clan.getByClanIdAndGameId tag, GAME_ID
    .then (existingClan) ->
      ClashRoyaleClanRecord.upsert {
        clanId: tag
        clanRecordTypeId: config.CLASH_ROYALE_CLAN_DONATIONS_RECORD_ID
        scaledTime: ClashRoyaleClanRecord.getScaledTimeByTimeScale 'week'
        diff: {value: clan.donations}
      }

      ClashRoyaleClanRecord.upsert {
        clanId: tag
        clanRecordTypeId: config.CLASH_ROYALE_CLAN_TROPHIES_RECORD_ID
        scaledTime: ClashRoyaleClanRecord.getScaledTimeByTimeScale 'week'
        diff: {value: clan.trophies}
      }

      playerIds = _.map clan.memberList, ({tag}) -> tag.replace '#', ''
      Promise.all [
        UserPlayer.getAllByPlayerIdsAndGameId playerIds, GAME_ID
        Player.getAllByPlayerIdsAndGameId playerIds, GAME_ID
      ]
      .then ([existingUserPlayers, existingPlayers]) ->
        _.map existingUserPlayers, (existingUserPlayer) ->
          player = _.find clan.memberList, {
            tag: "##{existingUserPlayer.playerId}"
          }
          donations = player.donations
          clanChestCrowns = player.clanChestCrowns
          ClashRoyalePlayerRecord.upsert {
            playerId: existingUserPlayer.playerId
            gameRecordTypeId: config.CLASH_ROYALE_DONATIONS_RECORD_ID
            scaledTime: ClashRoyalePlayerRecord.getScaledTimeByTimeScale 'week'
            diff: {value: donations, playerId: existingUserPlayer.playerId}
          }
          ClashRoyalePlayerRecord.upsert {
            playerId: existingUserPlayer.playerId
            gameRecordTypeId: config.CLASH_ROYALE_CLAN_CROWNS_RECORD_ID
            scaledTime: ClashRoyalePlayerRecord.getScaledTimeByTimeScale 'week'
            diff: {
              value: clanChestCrowns, playerId: existingUserPlayer.playerId
            }
          }

        newPlayers = _.filter _.map clan.memberList, (player) ->
          unless _.find existingPlayers, {id: player.tag.replace('#', '')}
            # ClashRoyaleAPIService.updatePlayerById playerId, {
            #   priority: 'normal'
            # }
            # .then ->
            {
              # only set to true when clan is claimed
              # hasUserId: true
              id: player.tag.replace '#', ''
              updateFrequency: 'none'
              data:
                name: player.name
                trophies: player.trophies
                expLevel: player.expLevel
                arena: player.arena
                clan:
                  badgeId: clan.badgeId
                  name: clan.name
                  tag: clan.tag
            }
        Player.batchCreateByGameId GAME_ID, newPlayers

      (if existingClan
        Clan.updateByClanIdAndGameId tag, GAME_ID, diff
      else
        Clan.createByGameId GAME_ID, _.defaults {id: diff.clanId}, diff
        .then ({id}) ->
          Clan.createGroup {
            userId: userId
            name: clan.name
            clanId: diff.clanId
          }
          .then (group) ->
            GroupClan.updateByClanIdAndGameId tag, GAME_ID, {groupId: group.id}
      ).catch (err) ->
        console.log 'clan err', err

  updateStale: ({force} = {}) ->
    Clan.getStaleByGameId GAME_ID, {
      type: 'data'
      staleTimeS: if force then 0 else CLAN_STALE_TIME_S
    }
    .map ({id}) -> id
    .then (clanIds) ->
      console.log 'staleclan', clanIds.length, new Date()
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
  #             @updateByClanId clanId, {
  #               userId: userId, priority: 'normal'
  #             }
  #
  #       .then ->
  #         ClashRoyaleTopClan.upsertByRank rank, {
  #           clanId: clanId
  #         }


module.exports = new ClashRoyaleClan()
