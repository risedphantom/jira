module Scenarios
  ##
  # DeployRelease scenario
  class DeployRelease
    def run
      raise 'No stage!' unless ENV['STAGE']
      jira = JIRA::Client.new SimpleConfig.jira.to_h
      issue = jira.Issue.find SimpleConfig.jira.issue

      # Get unique labels from release issue and all linked issues
      labels = issue.labels
      issue.linked_issues('deployes').each do |linked_issue|
        labels.concat(linked_issue.labels)
      end
      labels = labels.uniq

      prs = issue.related['pullRequests']

      puts 'Checking for wrong PRs names:'

      prs.each do |pr|
        prname = pr['name'].dup
        if pr['name'].strip!.nil?
          puts "[#{prname}] - OK"
        else
          puts "[#{prname}] - WRONG! Stripped. Bad guy: #{pr['author']['name']}"
        end
      end

      git_style_release = SimpleConfig.jira.issue.tr('-', ' ').downcase.capitalize

      prs.select! { |pr| (/^((#{SimpleConfig.jira.issue})|(#{git_style_release}))/.match pr['name']) && pr['status'] != 'DECLINED' }

      if prs.empty?
        puts 'No pull requests for this task!'
        exit 1
      end

      puts 'Selected PRs:'
      puts prs.map { |pr| pr['name'] }
      pp prs

      prop_values = { 'STAGE' => ENV['STAGE'] }

      prs.each do |pr|
        repo_name = pr['url'].split('/')[-3]
        unless pr['destination']['branch'].include? 'master'
          puts "WTF? Why is this Pull Request here? o_O (destination: #{pr['destination']['branch']}"
          next
        end
        prop_values["#{repo_name.upcase}_BRANCH"] = pr['source']['branch']
        project_labels = labels.select { |label| label.start_with? "#{repo_name}_" }.map { |label| label.remove("#{repo_name}_") }
        prop_values["#{repo_name.upcase}_LABELS"] = project_labels.join(',') unless project_labels.empty?
      end

      pp prop_values

      JavaProperties.write prop_values, './.properties'

      exit 0
    end
  end
end
