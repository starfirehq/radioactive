Promise = require 'bluebird'

Event = require '../models/event'
PushNotificationService = require './push_notification'
config = require '../config'

class EventService
  notifyForStart: ->
    Event.getAllStartingNow()
    .then (events) ->
      Promise.each events, (event) ->
        Event.updateById event.id, {hasStarted: true}
        PushNotificationService.sendToEvent event, {
          title: 'Event starting' # TODO: change to titleObj
          type: PushNotificationService.TYPES.EVENT
          text: "#{event.name} starts in 5 minutes"
          data:
            path:
              key: 'event'
              params:
                id: event.id
        }

module.exports = new EventService()
