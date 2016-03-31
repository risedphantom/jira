require 'simple_config'
require 'colorize'
require 'json'
require 'git'
require 'jira'
require_relative 'lib/check'
require_relative 'lib/repo'
require_relative 'lib/issue'

WORKDIR = SimpleConfig.git.workdir

post_to_ticket = ENV.fetch('ROOT_BUILD_CAUSE_REMOTECAUSE', nil) == 'true' ? true : false

fail_on_jscs = ENV.fetch('FAIL_ON_JSCS', false)
FAIL_ON_JSCS = fail_on_jscs ? !fail_on_jscs.empty? : false

TRANSITION = 'WTF'.freeze

Dir.mkdir WORKDIR unless Dir.exist? WORKDIR

# Workflow
# Collect data about release and Issue
unless (triggered_issue = SimpleConfig.jira.issue)
  print "No issue - no cry!\n"
  exit 2
end

jira = JIRA::Client.new SimpleConfig.jira.to_h
# noinspection RubyArgCount
issue = jira.Issue.jql("key = #{triggered_issue}")
raise "WTF??? Issue search returned #{issue.length} elements!" if (issue.is_a? Array) && (issue.length > 1)
issue = issue[0] if issue.is_a? Array

err_struct = Struct.new(:name, :detail)
errors = []

fail_release = false

branches = issue.related['branches']

exit 0 if branches.empty?

branches.each do |branch|
  branch_name = branch['name']
  repo_name = branch['repository']['name']
  repo_url = branch['repository']['url']
  # Checkout repo
  puts "Working with #{repo_name}".green
  g_rep = GitRepo.new repo_url, repo_name, workdir: WORKDIR

  g_rep.checkout 'master'
  g_rep.git.pull
  g_rep.git.branch(branch_name).delete rescue Git::GitExecuteError # rubocop:disable Style/RescueModifier
  begin
    g_rep.git.checkout branch_name
  rescue Git::GitExecuteError => e
    puts "Branch #{branch_name} does not exist any more...\n#{e.message}"
    next
  end

  # g_rep.checkout branch_name
  puts 'Merging new version'.green
  g_rep.merge! "origin/#{branch_name}"

  # Try to merge master to branch
  unless ENV['NO_MERGE']
    begin
      g_rep.merge! 'master'
    rescue Git::GitExecuteError => e
      errors << err_struct.new('Merge', "Failed to merge master to branch #{branch_name}.
Git had this to say: {noformat}#{e.message}{noformat}")
      fail_release = true
      g_rep.abort_merge!
    end
    g_rep.checkout branch_name
  end

  puts 'JSCS/JSHint'.green

  # JSCS; JSHint
  unless ENV['NO_JSCS']
    res_text = g_rep.check_diff 'HEAD'
    unless res_text.empty?
      errors << err_struct.new('JSCS/JSHint', "Checking branch #{branch_name}:\n{noformat}#{res_text}{noformat}")
      fail_release = true if FAIL_ON_JSCS
    end
  end

  puts 'NPM Test'.green
  # NPM test
  test_out = ''
  test_out = g_rep.run_tests! unless ENV['NO_TESTS']
  if test_out.code > 0
    fail_release = true
    errors << err_struct.new('NPM Test', "Exitcode: #{test_out.code} {noformat}#{test_out.out}{noformat}")
  end
end

comment_text = "Automatic code review complete.\n".green

# If something failed:
if fail_release
  comment_text = "There were some errors:\n\t#{errors.map(&:name).join("\n\t")}".red

  # return issue to "In Progress"
  if issue.has_transition? TRANSITION
    puts 'TRANSITIONING DISABLED'
    issue.transition TRANSITION
  else
    puts "No transition #{TRANSITION} available.".red
    comment_text = "Unable to transition issue to \"In Progress\" state.\n".red + comment_text
  end

else
  comment_text << "\nMerge master: #{ENV['NO_MERGE'] ? 'SKIPPED' : 'PASSED'}
JSCS/JSHint: #{ENV['NO_JSCS'] ? 'SKIPPED' : 'PASSED'}
npm test: #{ENV['NO_TEST'] ? 'SKIPPED' : 'PASSED'}\n"
  unless errors.empty?
    comment_text << "There were some errors:\n#{errors.map(&:name).join("\n")}".red
  end
end

puts 'Errors:'.red unless errors.empty?
errors.each do |error|
  puts error.name.red
  puts error.detail
end

comment_text << "\nBuild URL: #{ENV.fetch('BUILD_URL', 'none')}"
puts 'Summary comment text:'.green
puts comment_text
issue.post_comment comment_text if post_to_ticket

exit 1 unless error.empty?
