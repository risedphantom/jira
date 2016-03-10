source 'https://rubygems.org'
gem 'jira-ruby'
gem 'json'
gem 'rest-client'
gem 'slop', '4.1.0'
gem 'git', git: 'https://github.com/onetwotrip/ruby-git.git',
           branch: 'develop'
gem 'ottinfra-codereview', git: 'https://github.com/onetwotrip/ott_infra-codereview.git'
gem 'ottinfra-sendmail', git: 'https://github.com/onetwotrip/ott_infra-sendmail.git',
                         branch: 'develop'
gem 'SimpleConfig', git: 'https://github.com/onetwotrip/SimpleConfig'
gem 'addressable'
gem 'java-properties'
gem 'sendgrid-ruby'

group :test, :development do
  gem 'rake'
  gem 'rspec'
  gem 'rubocop'
end
group :test do
  gem 'simplecov', '~>0.11.1'
  gem 'codeclimate-test-reporter'
end

# Specify your gem's dependencies in jira.gemspec
gemspec
