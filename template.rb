require "fileutils"
require "shellwords"

# Copied from: https://github.com/mattbrictson/rails-template
# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("jumpstart-"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      "https://github.com/excid3/jumpstart.git",
      tempdir,
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{jumpstart/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def rails_version
  @rails_version ||= Gem::Version.new(Rails::VERSION::STRING)
end

def rails_5?
  Gem::Requirement.new(">= 5.2.0", "< 6.0.0.beta1").satisfied_by? rails_version
end

def rails_6?
  Gem::Requirement.new(">= 6.0.0.beta1", "< 7").satisfied_by? rails_version
end

def add_gems
  gem "administrate", github: "excid3/administrate", branch: "jumpstart"
  gem "bootstrap", "~> 4.5"
  gem "devise", "~> 4.7" # Flexible authentication solution for Rails
  gem "devise-bootstrapped", github: "excid3/devise-bootstrapped", branch: "bootstrap4"
  gem "devise_masquerade", "~> 1.2"
  gem "font-awesome-sass", "~> 5.13"
  gem "friendly_id", "~> 5.3"
  gem "gravatar_image_tag", github: "mdeering/gravatar_image_tag"
  gem "mini_magick", "~> 4.10"
  gem "name_of_person", "~> 1.1"
  gem "omniauth-facebook", "~> 5.0" # OmniAuth strategy for Facebook
  gem "omniauth-github", "~> 1.3" # OmniAuth strategy for GitHub
  gem "omniauth-twitter", "~> 1.4" # OmniAuth strategy for Twitter
  gem "sidekiq", "~> 6.0.7" # Sidekiq is used to process background jobs with the help of Redis
  gem "sidekiq-unique-jobs", "~> 6.0.22" # Ensures that Sidekiq jobs are unique when enqueued
  gem "sitemap_generator", "~> 6.1" # SitemapGenerator is a framework-agnostic XML Sitemap generator
  gem "email_validator", "~> 2.0" # Email validator for Rails and ActiveModel
  gem "envied", "~> 0.9" # Ensure presence and type of your app's ENV-variables
  gem "httparty", "~> 0.18" # Makes http fun! Also, makes consuming restful web services dead easy
  gem "inline_svg", "~> 1.7" # Embed SVG documents in your Rails views and style them with CSS
  gem 'pagy', '~> 3.8' # A Scope & Engine based, clean, powerful, customizable and sophisticated paginator
  gem "nokogiri", "~> 1.10" # HTML, XML, SAX, and Reader parser
  gem "strong_migrations", "~> 0.6" # Catch unsafe migrations
  gem "whenever", require: false

  group :development, :test do
    gem "amazing_print", "~> 1.1" # Great Ruby debugging companion: pretty print Ruby objects to visualize their structure
    gem "bullet", "~> 6.1" # help to kill N+1 queries and unused eager loading
    gem "capybara", "~> 3.32" # Capybara is an integration testing tool for rack based web applications
    gem "faker", "~> 2.11" # A library for generating fake data such as names, addresses, and phone numbers
    gem "parallel_tests", "~> 2.32" # Run Test::Unit / RSpec / Cucumber / Spinach in parallel
    gem "pry-byebug", "~> 3.8" # Combine 'pry' with 'byebug'. Adds 'step', 'next', 'finish', 'continue' and 'break' commands to control execution
    gem "rspec-rails", "~> 4.0" # rspec-rails is a testing framework for Rails 3+
    gem "rubocop", "~> 0.84", require: false # Automatic Ruby code style checking tool
    gem "rubocop-performance", "~> 1.6", require: false # A collection of RuboCop cops to check for performance optimizations in Ruby code
    gem "rubocop-rails", "~> 2.5", require: false # Automatic Rails code style checking tool
    gem "rubocop-rspec", "~> 1.39", require: false # Code style checking for RSpec files
    gem "spring", "~> 2.1" # Preloads your application so things like console, rake and tests run faster
    gem "spring-commands-rspec", "~> 1.0" # rspec command for spring
  end

  if rails_5?
    gsub_file "Gemfile", /gem 'sqlite3'/, "gem 'sqlite3', '~> 1.3.0'"
    gem "webpacker", "~> 4.0.1"
  end
end

def set_application_name
  # Add Application Name to Config
  if rails_5?
    environment "config.application_name = Rails.application.class.parent_name"
  else
    environment "config.application_name = Rails.application.class.module_parent_name"
  end

  # Announce the user where he can change the application name in the future.
  puts "You can change application name inside: ./config/application.rb"
end

def add_users
  # Install Devise
  generate "devise:install"

  # Configure Devise
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
              env: "development"
  route "root to: 'home#index'"

  # Devise notices are installed via Bootstrap
  generate "devise:views:bootstrapped"

  # Create Devise User
  generate :devise, "User",
           "first_name",
           "last_name",
           "announcements_last_read_at:datetime",
           "admin:boolean"

  # Set admin default to false
  in_root do
    migration = Dir.glob("db/migrate/*").max_by { |f| File.mtime(f) }
    gsub_file migration, /:admin/, ":admin, default: false"
  end

  if Gem::Requirement.new("> 5.2").satisfied_by? rails_version
    gsub_file "config/initializers/devise.rb",
      /  # config.secret_key = .+/,
      "  config.secret_key = Rails.application.credentials.secret_key_base"
  end

  # Add Devise masqueradable to users
  inject_into_file("app/models/user.rb", "omniauthable, :masqueradable, :trackable, :", after: "devise :")
end

def add_webpack
  # Rails 6+ comes with webpacker by default, so we can skip this step
  return if rails_6?

  # Our application layout already includes the javascript_pack_tag,
  # so we don't need to inject it
  rails_command "webpacker:install"
end

def add_javascript
  run "yarn add expose-loader jquery popper.js bootstrap data-confirm-modal local-time"

  if rails_5?
    run "yarn add turbolinks @rails/actioncable@pre @rails/actiontext@pre @rails/activestorage@pre @rails/ujs@pre"
  end

  content = <<-JS
const webpack = require('webpack')
environment.plugins.append('Provide', new webpack.ProvidePlugin({
  $: 'jquery',
  jQuery: 'jquery',
  Rails: '@rails/ujs'
}))
  JS

  insert_into_file "config/webpack/environment.js", content + "\n", before: "module.exports = environment"
end

def copy_templates
  remove_file "app/assets/stylesheets/application.css"

  copy_file "Procfile"
  copy_file "Procfile.dev"
  copy_file ".foreman"

  copy_file ".editorconfig"
  copy_file ".erb-lint.yml"
  copy_file ".eslintrc.js"
  copy_file ".nvmrc"
  copy_file ".prettierignore"
  copy_file ".rspec"
  copy_file ".robocop_todo.yml"
  copy_file ".robocop.yml"
  copy_file ".ruby-version.yml"

  directory "app", force: true
  directory "config", force: true
  directory "lib", force: true

  route "get '/terms', to: 'home#terms'"
  route "get '/privacy', to: 'home#privacy'"
end

def add_sidekiq
  environment "config.active_job.queue_adapter = :sidekiq"

  insert_into_file "config/routes.rb",
    "require 'sidekiq/web'\n\n",
    before: "Rails.application.routes.draw do"

  content = <<-RUBY
    authenticate :user, lambda { |u| u.admin? } do
      mount Sidekiq::Web => '/sidekiq'
    end
  RUBY
  insert_into_file "config/routes.rb", "#{content}\n\n", after: "Rails.application.routes.draw do\n"
end

def add_announcements
  generate "model Announcement published_at:datetime announcement_type name description:text"
  route "resources :announcements, only: [:index]"
end

def add_notifications
  generate "model Notification recipient_id:bigint actor_id:bigint read_at:datetime action:string notifiable_id:bigint notifiable_type:string"
  route "resources :notifications, only: [:index]"
end

def add_administrate
  generate "administrate:install"

  append_to_file "app/assets/config/manifest.js" do
    "//= link administrate/application.css\n//= link administrate/application.js"
  end

  gsub_file "app/dashboards/announcement_dashboard.rb",
    /announcement_type: Field::String/,
    "announcement_type: Field::Select.with_options(collection: Announcement::TYPES)"

  gsub_file "app/dashboards/user_dashboard.rb",
    /email: Field::String/,
    "email: Field::String,\n    password: Field::String.with_options(searchable: false)"

  gsub_file "app/dashboards/user_dashboard.rb",
    /FORM_ATTRIBUTES = \[/,
    "FORM_ATTRIBUTES = [\n    :password,"

  gsub_file "app/controllers/admin/application_controller.rb",
    /# TODO Add authentication logic here\./,
    "redirect_to '/', alert: 'Not authorized.' unless user_signed_in? && current_user.admin?"

  environment do <<-RUBY
    # Expose our application's helpers to Administrate
    config.to_prepare do
      Administrate::ApplicationController.helper #{@app_name.camelize}::Application.helpers
    end
  RUBY   end
end

def add_multiple_authentication
  insert_into_file "config/routes.rb",
                   ', controllers: { omniauth_callbacks: "users/omniauth_callbacks" }',
                   after: "  devise_for :users"

  generate "model Service user:references provider uid access_token access_token_secret refresh_token expires_at:datetime auth:text"

  template = "" "
    env_creds = Rails.application.credentials[Rails.env.to_sym] || {}
    %i{ facebook twitter github }.each do |provider|
      if options = env_creds[provider]
        config.omniauth provider, options[:app_id], options[:app_secret], options.fetch(:options, {})
      end
    end
    " "".strip

  insert_into_file "config/initializers/devise.rb", "  " + template + "\n\n",
                   before: "  # ==> Warden configuration"
end

def add_whenever
  run "wheneverize ."
end

def add_envied
  rails_command "envied init:rails"
  rails_command "envied extract"
end

def add_friendly_id
  generate "friendly_id"

  insert_into_file(
    Dir["db/migrate/**/*friendly_id_slugs.rb"].first,
    "[5.2]",
    after: "ActiveRecord::Migration",
  )
end

def stop_spring
  run "spring stop"
end

def add_sitemap
  rails_command "sitemap:install"
end

# Main setup
add_template_repository_to_source_path

add_gems

after_bundle do
  set_application_name
  stop_spring
  add_users
  add_webpack
  add_javascript
  add_announcements
  add_notifications
  add_multiple_authentication
  add_sidekiq
  add_friendly_id
  add_envied

  copy_templates
  add_whenever
  add_sitemap

  # Migrate
  rails_command "db:create"
  rails_command "db:migrate"

  # Migrations must be done before this
  add_administrate

  # Commit everything to git
  git :init
  git add: "."
  git commit: %Q{ -m 'Initial commit' }

  say
  say "Jumpstart app successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "cd #{app_name} - Switch to your new app's directory."
  say "foreman start - Run Rails, sidekiq, and webpack-dev-server."
end
