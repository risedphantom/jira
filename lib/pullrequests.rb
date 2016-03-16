require 'pullrequest'

module JIRA
  ##
  # This class represents an array of PullRequests
  class PullRequests
    attr_reader :valid_msg
    attr_reader :prs

    def initialize(*arr)
      @prs = []
      arr.each do |pr|
        add(pr)
      end
    end

    def add(pr)
      raise TypeError, "Expected PullRequest value. Got #{pr.class}" unless pr.instance_of?(PullRequest)
      @prs.push pr
    end

    def valid?
      !empty? && !duplicates?
    rescue => e
      @valid_msg = p(e)
      return false
    end

    def empty?
      raise 'Has no PullRequests' if @prs.empty?
    end

    def filter_by(key, *args)
      @prs.keep_if do |pr|
        value = key.split('_').inject(pr.pr) { |a, e| a[e] }
        args.any? { |word| value.include?(word) }
      end
      self
    end

    def grep_by(key, *args)
      self.class.new(
        *@prs.select do |pr|
          args.include? key.split('_').inject(pr.pr) { |a, e| a[e] }
        end
      )
    end

    def each
      @prs.each do |pr|
        yield pr
      end
    end

    def method_missing(m, *args, &block)
      if (key = m[/filter_by_(\w+)/, 1])
        filter_by(key, *args)
      elsif (key = m[/grep_by_(\w+)/, 1])
        grep_by(key, *args)
      else
        super
      end
    end

    private

    def duplicates?
      urls = @prs.map { |i| i.pr['source']['url'] }
      raise "PullRequests has duplication: #{urls.join ','}" if urls.uniq.length != urls.length
    end
  end
end
