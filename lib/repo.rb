require 'addressable/uri'
require 'open3'
require 'git'
require 'git/bitbucket'

##
# This class represents a git repo
class GitRepo
  attr_reader :git

  def initialize(url)
    @git = Git.get_branch(url)
    @has_jscs = nil
    @has_jshint = nil
  end

  def delete_branch!(branch)
    raise ArgumentError, 'Can not remove branch master' if branch == 'master'
    @git.branch(branch).delete
    @git.chdir do
      out = `git push -q origin :#{branch}`
      p $CHILD_STATUS
      p out
    end
  end

  def prepare_branch(source, destination, clean = false)
    @git.fetch
    @git.branch(source).checkout
    @git.pull
    if clean
      @git.branch(destination)
      delete_branch! destination
      @git.branch(destination).checkout
    else
      @git.branch(destination).checkout
      @git.merge(source,
                 "CI: merge source branch #{source} to release #{destination}")
    end
  end

  def jscs?
    @has_jscs = File.readable? @git.dir.to_s + '/.jscsrc' if @has_jscs.nil?
    @has_jscs
  end
  alias has_jscs? jscs?

  def jshint?
    @has_jshint = File.readable? @git.dir.to_s + '/.jshintrc' if @has_jshint.nil?
    @has_jshint
  end
  alias has_jshint? jshint?

  def checkout(commit = nil)
    unless commit
      yield self if block_given?
      return
    end

    current = @git.revparse 'HEAD'
    @git.checkout commit

    if block_given? # rubocop:disable Style/GuardClause
      yield self
      @git.checkout current
    end
  end

  def commits_between(commit1, commit2)
    @git.log.between(commit1, commit2)
  end

  def check_jscs(filename, ranges = [])
    return '' unless has_jscs?
    run_check "jscs -c '#{@git.dir}/.jscsrc' -r inline #{@git.dir}/#{filename}", filename, ranges
  end

  def check_jshint(filename, ranges = [])
    return '' unless has_jshint?
    run_check "jshint -c '#{@git.dir}/.jshintrc' #{@git.dir}/#{filename}", filename, ranges
  end

  def get_diff(new_commit, old_commit = nil)
    old_commit ||= @git.merge_base new_commit, 'master'
    @git.diff old_commit, new_commit
  end

  def changed_files(new_commit, old_commit = nil)
    diff = get_diff new_commit, old_commit
    diff.map(&:path)
  end

  def check_diff(new_commit, old_commit = nil)
    diff = get_diff new_commit, old_commit
    puts "#{diff.each.to_a.length} files to check"
    out = []
    diff.each do |file|
      ranges = diffed_lines file.patch
      this_out = ''
      next unless File.extname(file.path) == '.js'
      this_out += check_jscs file.path, ranges
      this_out += check_jshint file.path, ranges
      out << this_out unless this_out.empty?
    end
    out.join "\n"
  end

  def current_commit
    @git.revparse 'HEAD'
  end

  def merge!(source = 'master', dest = nil)
    checkout dest if dest
    @git.merge source
  end

  def abort_merge!
    begin
      mergehead = @git.revparse 'MERGE_HEAD'
    rescue StandardError
      Git::GitExecuteError
    end

    return unless mergehead

    begin
      @git.lib.send(:command, 'merge', '--abort')
    rescue StandardError
      Git::GitExecuteError
    end
  end

  def chdir(&block)
    @git.chdir(&block)
  end

  # :nocov:
  def run_tests!
    test_struct = Struct.new(:code, :out)
    errors = test_struct.new
    errors.code = 0
    errors.out = ''
    @git.chdir do
      t = Thread.new do
        puts 'NPM install'
        errors.out += `npm install 2>&1`
        errors.code += $CHILD_STATUS.exitstatus
        puts 'NPM test'
        errors.out += `npm test 2>&1`
        errors.code += $CHILD_STATUS.exitstatus
      end
      t.join
    end
    errors
  end
  # :nocov:

  def method_missing(*args)
    method_name = args.shift
    super unless @git.respond_to? method_name
    @git.send method_name, *args
  end

  private

  # :nocov:
  def run_check(command, filename, ranges)
    text = ''
    run_command(command)[0].each_line do |line|
      if (l_text = format_line line, ranges)
        text << "#{filename}: line #{l_text}\n"
      end
    end
    text
  end
  # :nocov:

  def format_line(line, ranges)
    return nil unless (md = /\.js: line (\d+)(,?.*)$/.match(line))
    return nil unless ranges.detect { |r| r.cover? md[1].to_i }
    "#{md[1]}#{md[2]}\n"
  end

  def diffed_lines(diff)
    ranges = []
    diff.each_line do |l|
      return [] if l =~ /^Binary files ([^ ]+) and ([^ ]+) differ$/ # skip binary files
      return [0..1] if l =~ /@@ -0,0 +\d+ @@/                       # return [0..1] for a new file
      next unless (md = /^@@ -\d+(?:,\d+)? \+(\d+),(\d+) @@/.match(l))
      ranges << ((md[1].to_i)..(md[1].to_i + md[2].to_i))
    end
    if ranges.empty? && !diff.empty?
      puts diff
      puts 'Diff without marks or unknown marks!'
    end
    ranges
  end

  def run_command(command, commit = nil)
    raise ArgumentError.new, 'Empty or nil command!' if command.nil? || command.empty?

    out = ''
    if commit
      checkout commit do |_|
        out = Open3.capture2e(command)
      end
    else
      out = Open3.capture2e(command)
    end

    if block_given?
      out[0].split("\n").each { |line| yield line }
      return out[1]
    end
    out
  end
end

# :nocov:
def git_repo(url, opts = {})
  git_repo = Git.get_branch(url)
  # Removal of existing branches
  opts[:delete_branches].to_a.each do |branch|
    next unless git_repo.find_branch? branch
    git_repo.chdir do
      `git fetch --prune`
    end
    if git_repo.is_local_branch? branch
      puts "Found pre release branch: #{branch}. Deleting local...".red
      git_repo.lib.branch_delete branch
    end
    if git_repo.is_remote_branch? branch
      puts "Found pre release branch: #{branch}. Deleting remote...".red
      git_repo.lib.branch_delete_remote branch
    end
  end
  git_repo
end

def clean_branch(repo, branch)
  return if branch == 'master'
  repo.branch('master').checkout
  repo.branch(branch).delete
  repo.chdir do
    `git push -q origin :#{branch}`
  end
end

def prepare_branch(repo, source, destination, clean = false)
  repo.fetch
  repo.branch(source).checkout
  repo.pull('origin', source)
  # destination branch should be checked out or has no effect on actual FS
  if clean
    repo.branch(destination).checkout
    clean_branch(repo, destination)
  end
  repo.branch(destination).checkout
  repo.merge(source,
             "CI: merge source branch #{source} to release #{destination}")
end
# :nocov:
