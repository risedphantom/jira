module Scenarios
  ##
  # CreateRelease scenario
  class CreateRelease
    def run
      params = SimpleConfig.release
      puts "Create release from filter #{params[:filter]} with name #{params[:release_name]}".green

      client = JIRA::Client.new SimpleConfig.jira.to_h


      issues = client.Issue.jql('filter=%s' % [params[:filter]])
      project = client.Project.find(params[:project])
      release = client.Issue.build
      release.save({"fields"=>{"summary"=>params[:release_name],"project"=>{"id"=>project.id},"issuetype"=>{"name"=>"Release"}}})
      release.fetch
      puts "Start to link issues to release #{release.key}".green

      issues.each{ |issue| issue.link(release.key) }

      puts "Create new release #{release.key} from filter #{params[:filter]}".green
    end
  end
end
