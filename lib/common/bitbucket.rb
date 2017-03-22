$LOAD_PATH << '/home/dshmelev/Develop/onetwotrip/tinybucket/lib/'
require 'tinybucket'

Tinybucket.configure do |config|
  config.oauth_token = ENV['BITBUCKET_OAUTH_TOKEN']
  config.oauth_secret = ENV['BITBUCKET_OAUTH_SECRET']
end

BITBUCKET = Tinybucket.new
