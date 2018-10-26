$LOAD_PATH << '/home/dshmelev/Develop/onetwotrip/tinybucket/lib/'
require 'tinybucket'

Tinybucket.configure do |config|
  config.oauth_token = ENV['BITBUCKET_OAUTH_TOKEN']
  config.oauth_secret = ENV['BITBUCKET_OAUTH_SECRET']
  LOGGER.info "Token: #{config.oauth_token}"
  LOGGER.info "Token: #{config.oauth_secret}"
end

BITBUCKET = Tinybucket.new
