module Scenarios
  ##
  # FreezeRelease scenario
  class FreezeRelease
    def with(instance, &block)
      instance.instance_eval(&block)
      instance
    end

    def run
      LOGGER.info "Starting freeze_release for #{SimpleConfig.jira.issue}"
      jira  = JIRA::Client.new SimpleConfig.jira.to_h
      issue = jira.Issue.find(SimpleConfig.jira.issue)
      issue.post_comment <<-BODY
      {panel:title=Release notify!|borderStyle=dashed|borderColor=#ccc|titleBGColor=#E5A443|bgColor=#F1F3F1}
        Запущено формирование релизных веток(!)
        Ожидайте сообщение о завершении
      {panel}
      BODY

      begin
        release_issues = []
        # prepare release candidate branches
        issue.related['branches'].each do |branch|
          repo_path = git_repo(branch['repository']['url'])
          repo_path.chdir do
            `git fetch --prune`
          end
          unless branch['name'].match "^#{SimpleConfig.jira.issue}-pre"
            LOGGER.error "[SKIP] #{branch['repository']['name']}/#{branch['name']} - incorrect branch name"
            next
          end
          # Check for case when issue has correct name, but was deleted from issue
          unless repo_path.is_branch? branch['name']
            LOGGER.error "[SKIP] #{branch['repository']['name']}/#{branch['name']} - branch doesn't exist"
            next
          end
          release_issues << branch
        end

        if release_issues.empty?
          LOGGER.error 'There is no -pre branches in release ticket'
          exit(1)
        end

        release_issues.each do |branch| # rubocop:disable Metrics/BlockLength
          today      = Time.new.strftime('%d.%m.%Y')
          old_branch = branch['name']
          new_branch = "#{SimpleConfig.jira.issue}-release-#{today}"
          repo_path  = git_repo(branch['repository']['url'])

          # copy -pre to -release
          LOGGER.info "Working with #{repo_path.remote.url.repo}"
          unless repo_path.is_branch? old_branch
            LOGGER.error "Branch #{old_branch} doesn't exists"
            exit(1)
          end

          LOGGER.info "Copying #{old_branch} to #{new_branch} branch"
          cur_branch = repo_path.current_branch
          with repo_path do
            checkout(old_branch)
            pull
            branch(new_branch).delete if is_branch?(new_branch)
            branch(new_branch).create
            checkout cur_branch
          end

          LOGGER.info "Pushing #{new_branch} and deleting #{old_branch} branch"
          with repo_path do
            push(repo_path.remote('origin'), new_branch) # push -release to origin
            branch(old_branch).delete_both if old_branch != 'master' # delete -pre from local/remote
            LOGGER.info "Creating PR from #{new_branch} to #{cur_branch}"
            create_pullrequest(
              SimpleConfig.bitbucket[:username],
              SimpleConfig.bitbucket[:password],
              new_branch
            )
          end
        end

        LOGGER.info 'Get all labels again'
        issue = jira.Issue.find(SimpleConfig.jira.issue)
        release_labels = []
        issue.api_pullrequests.each do |br|
          LOGGER.info("Repo: #{br.repo_slug}")
          release_labels << br.repo_slug
        end
        if release_labels.empty?
          LOGGER.error 'Made empty labels array! I will skip set up new labels step'
        else
          LOGGER.info "Add labels: #{release_labels.uniq} to release #{issue.key}"
          issue.save(fields: { labels: release_labels })
          issue.fetch
        end
      rescue StandardError => e
        issue.post_comment <<-BODY
        {panel:title=Release notify!|borderStyle=dashed|borderColor=#ccc|titleBGColor=#E5A443|bgColor=#F1F3F1}
         Не удалось собрать релизные ветки (x)
         Подробности в логе таски https://jenkins.twiket.com/view/RELEASE/job/freeze_release/
        {panel}
        BODY
        LOGGER.error "Не удалось собрать релизные ветки, ошибка: #{e.message}, трейс:\n\t#{e.backtrace.join("\n\t")}"
        exit(1)
      end
      issue.post_comment <<-BODY
      {panel:title=Release notify!|borderStyle=dashed|borderColor=#ccc|titleBGColor=#E5A443|bgColor=#F1F3F1}
        Формирование релизных веток завершено (/)
      {panel}
      BODY
    end
  end
end
