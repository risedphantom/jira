require 'rest-client'
require 'json'

##
# This module extends Git
module Git
  ##
  # Add methods for Git::Base
  class Base
    # Create pull request from src branch to dst
    # By default: from local branch to master
    def create_pullrequest(src: current_branch, dst: 'master', repo: remote.url.repo, username: nil, password: nil, oauth: nil)
      request = { title: "#{src} #{repo}",
                  source: { branch: { name: src },
                            repository: { full_name: repo } },
                  destination: { branch: { name: dst } } }
      begin
        url = "https://#{username}:#{password}@api.bitbucket.org/2.0/repositories/#{repo}/pullrequests"
        RestClient.post url, request.to_json, content_type: :json
      rescue StandardError => e
        puts "Error: #{e}; URL: #{url}; PARAMS: #{request}"
      end
      end

    def create_pullrequest_new(username, password, src)
      request = { title: "#{src} #{remote.url.repo}",
                  source: { branch: { name: src },
                            repository: { full_name: remote.url.repo } },
                  destination: { branch: { name: 'master' } } }
      begin
        url = "https://#{username}:#{password}@api.bitbucket.org/2.0/repositories/#{remote.url.repo}/pullrequests"
        RestClient.post url, request.to_json, content_type: :json
      rescue StandardError => e
        puts "Error: #{e}; URL: #{url}; PARAMS: #{request}"
      end
    end
  end
end
