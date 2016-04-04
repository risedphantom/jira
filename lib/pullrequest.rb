require 'git'
require 'erb'

module JIRA
  ##
  # This class represent PullRequest
  class PullRequest
    attr_reader :pr, :git_config, :changed_files, :reviewers

    def initialize(git_config, hash)
      raise ArgumentError, 'Missing git config' unless git_config
      begin
        valid?(hash)
      rescue => e
        puts e
        @pr = {}
        return false
      end
      @pr = hash
      @git_config = git_config
    end

    def empty?
      @pr.empty?
    end

    def src
      parse_url @pr['source']['url']
    end

    def dst
      parse_url @pr['destination']['url']
    end

    def authors
      @pr['author']['name']
    end

    def url
      @pr['url']
    end

    def name
      @pr['name']
    end

    def reviewers
      @reviewers ||= reviewers_by_files(changed_files)
    end

    def changed_files
      @changed_files ||= files
    end

    def send_notify
      yield ERB.new(File.read('views/review_mail.erb')).result(binding) unless reviewers.empty?
    end

    private

    def reviewers_by_files(files)
      files.map do |file|
        review_files(file)
      end.flatten.uniq
    end

    def files
      repo.gtree("origin/#{dst.branch}").diff('HEAD').stats[:files].keys.select do |file|
        review_files?(file)
      end
    end

    def review_files(file)
      if file == '.gitattributes'
        [@git_config[:reviewer]]
      else
        repo.get_attrs(file)[@git_config[:reviewer_key]]
      end
    end

    def review_files?(file)
      !review_files(file).empty?
    end

    def repo
      @repo ||= Git.get_branch dst.to_s
      @repo.merge "origin/#{src.branch}"
      @repo
    end

    def parse_url(url)
      Git::Utils.url_to_ssh url
    end

    def valid?(input)
      src = parse_url(input['source']['url'])
      dst = parse_url(input['destination']['url'])
      raise 'Source and Destination repos in PR are different' unless src.to_repo_s == dst.to_repo_s
    end
  end
end
