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

pullrequests = issue.pullrequests(SimpleConfig.git.to_h)
                    .filter_by_status('OPEN')
                    .filter_by_source_url(SimpleConfig.jira.issue)

exit 0 if pullrequests.valid?

pullrequests.each do |pr|
  src_branch = pr.src.branch
  dst_branch = pr.dst.branch

  # Checkout repo
  puts "Clone/Open with #{pr.dst} branch #{dst_branch}".green

  begin
    g_rep = GitRepo.new pr.dst.full_url
  rescue Git::GitExecuteError => e
    puts "Branch #{dst_branch} does not exist any more...\n#{e.message}".red
    next
  end

  unless ENV['NO_MERGE']
    puts "Merging code from #{src_branch} version".green
    begin
      g_rep.merge! "origin/#{src_branch}"
    rescue Git::GitExecuteError => e
      errors << err_struct.new('Merge', "Failed to merge #{src_branch} to branch #{dst_branch}.
Git had this to say: {noformat}#{e.message}{noformat}")
      fail_release = true
      g_rep.abort_merge!
    end
  end

  # JSCS; JSHint
  unless ENV['NO_JSCS']
    puts 'Checking JSCS/JSHint'.green
    res_text = g_rep.check_diff 'HEAD', 'HEAD~1'
    unless res_text.empty?
      errors << err_struct.new('JSCS/JSHint', "Checking pullrequest '#{pr.name}':\n{noformat}#{res_text}{noformat}")
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

exit 1 unless errors.empty?
