# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'

config = require '../../config'

iap =
  '690fire':
    platforms: ['ios', 'android']
    name: '690 Fire'
    priceCents: "#{0.99 * 100}"
    data:
      fireAmount: 690

  '4550fire':
    platforms: ['web']
    name: '4550 Fire'
    priceCents: "#{4.99 * 100}"
    data:
      fireAmount: 4550

module.exports = _.flatten _.map iap, (value, key) ->
  platforms = value.platforms
  delete value.platforms
  _.map platforms, (platform) ->
    _.defaults {platform, key}, value
# coffeelint: enable=max_line_length,cyclomatic_complexity
