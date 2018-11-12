RAILS_REQUIREMENT = "~> 5.1.6".freeze

require "fileutils"
require "shellwords"

module Gemfile
  class GemInfo
    def initialize(name)
      @name=name
      @group=[]
      @opts={}
    end
    attr_accessor :name, :version
    attr_reader :group, :opts

    def opts=(new_opts={})
      new_group = new_opts.delete(:group)
      if (new_group && self.group != new_group)
        @group = ([self.group].flatten + [new_group].flatten).compact.uniq.sort
      end
      @opts = (self.opts || {}).merge(new_opts)
    end

    def group_key()
      @group
    end

    def gem_args_string
      args = ["'#{@name}'"]
      args << "'#{@version}'" if @version
      @opts.each do |name,value|
        args << ":#{name}=>#{value.inspect}"
      end
      args.join(', ')
    end
  end

  @geminfo = {}

  class << self
    # add(name, version, opts={})
    def add(name, *args)
      name = name.to_s
      version = args.first && !args.first.is_a?(Hash) ? args.shift : nil
      opts = args.first && args.first.is_a?(Hash) ? args.shift : {}
      @geminfo[name] = (@geminfo[name] || GemInfo.new(name)).tap do |info|
        info.version = version if version
        info.opts = opts
      end
    end

    def write
      File.open('Gemfile', 'a') do |file|
        file.puts
        grouped_gem_names.sort.each do |group, gem_names|
          indent = ""
          unless group.empty?
            file.puts "group :#{group.join(', :')} do" unless group.empty?
            indent="  "
          end
          gem_names.sort.each do |gem_name|
            file.puts "#{indent}gem #{@geminfo[gem_name].gem_args_string}"
          end
          file.puts "end" unless group.empty?
          file.puts
        end
      end
    end

    private
    #returns {group=>[...gem names...]}, ie {[:development, :test]=>['rspec-rails', 'mocha'], :assets=>[], ...}
    def grouped_gem_names
      {}.tap do |_groups|
        @geminfo.each do |gem_name, geminfo|
          (_groups[geminfo.group_key] ||= []).push(gem_name)
        end
      end
    end
  end
end

def add_gem(*all)
  Gemfile.add(*all)
end

def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("turing-rails-template-"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      "https://github.com/iandouglas/turing-rails-template.git",
      tempdir
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{turing-rails-template/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def assert_valid_options
  valid_options = {
    # skip_turbolinks: true,
    # skip_spring: true,
    skip_gemfile: false,
    skip_bundle: false,
    skip_git: false,
    skip_test_unit: false,
    edge: false
  }
  valid_options.each do |key, expected|
    next unless options.key?(key)
    actual = options[key]
    unless actual == expected
      fail Rails::Generators::Error, "Unsupported option: #{key}=#{actual}"
    end
  end
end

def assert_minimum_rails_version
  requirement = Gem::Requirement.new(RAILS_REQUIREMENT)
  rails_version = Gem::Version.new(Rails::VERSION::STRING)
  return if requirement.satisfied_by?(rails_version)

  prompt = "This template requires Rails #{RAILS_REQUIREMENT}. "\
           "You are using #{rails_version}. Continue anyway?"
  exit 1 if no?(prompt)
end

def assert_postgresql
  return if IO.read("Gemfile") =~ /^\s*gem ['"]pg['"]/
  fail Rails::Generators::Error,
       "This template requires PostgreSQL, "\
       "but the pg gem isn’t present in your Gemfile."
end

def preexisting_git_repo?
  @preexisting_git_repo ||= (File.exist?(".git") || :nope)
  @preexisting_git_repo == true
end

def run_with_clean_bundler_env(cmd)
  success = if defined?(Bundler)
              Bundler.with_clean_env { run(cmd) }
            else
              run(cmd)
            end
  unless success
    puts "Command failed, exiting: #{cmd}"
    exit(1)
  end
end


### START

assert_minimum_rails_version
assert_valid_options
assert_postgresql

add_template_repository_to_source_path

add_gem 'bcrypt', '~> 3.1.7'
add_gem 'rspec-rails', :group => [:development, :test]
add_gem 'factory_bot_rails', :group => [:development, :test]
add_gem 'launchy', :group => [:development, :test]
add_gem 'brakeman', :group => [:development, :test]
add_gem 'pry', :group => [:development, :test]
add_gem 'shoulda-matchers', '~> 3.1', :group => [:development, :test]
add_gem 'simplecov', :group => [:development, :test]
Gemfile.write

# remove turbolinks
gsub_file 'Gemfile', /gem 'turbolinks'\n/, ''
gsub_file 'Gemfile', /gem 'turbolinks', '~> 5'\n/, ''
gsub_file 'app/assets/javascripts/application.js', "//= require turbolinks\n", ''
gsub_file 'app/views/layouts/application.html.erb', /, 'data-turbolinks-track' => true/, ''
gsub_file 'app/views/layouts/application.html.erb', /, 'data-turbolinks-track' => 'reload'/, ''

copy_file "simplecov", ".simplecov", force: true

run_with_clean_bundler_env "bundle install"

binstubs = %w[
  brakeman bundler
]
run_with_clean_bundler_env "bundle binstubs #{binstubs.join(' ')} --force"

git :init unless preexisting_git_repo?
empty_directory ".git/safe"

rails_command("generate rspec:install")
copy_file "rspec", ".rspec", force: true

rails_command("db:drop")
rails_command("db:create")
rails_command("db:migrate")

# Set up the spec folders for RSpec
run_with_clean_bundler_env "mkdir spec/models"
run_with_clean_bundler_env "mkdir spec/features"
run_with_clean_bundler_env "mkdir spec/factories"
run_with_clean_bundler_env "touch spec/factories/config.rb"

append_to_file "spec/factories/config.rb" do
  "FactoryBot.define do\nend\n"
end

insert_into_file "spec/rails_helper.rb", before: "RSpec.configure do |config|\n" do
  "require 'simplecov'\nSimpleCov.start\n"
end
insert_into_file "spec/rails_helper.rb", before: "RSpec.configure do |config|\n" do
  "Shoulda::Matchers.configure do |config|\n  config.integrate do |with|\n    with.test_framework :rspec\n    with.library :rails\n  end\nend\n"
end
insert_into_file "spec/rails_helper.rb", after: "RSpec.configure do |config|\n" do
  "  config.include FactoryBot::Syntax::Methods\n"
end
insert_into_file "spec/rails_helper.rb", after: "RSpec.configure do |config|\n" do
  "  config.after(:each) do\n    FactoryBot.reload\n  end\n"
end

rails_command("generate controller Welcome index")
route "root to: 'welcome#index'"
copy_file 'welcome.html.erb', 'app/views/welcome/index.html.erb', force: true
copy_file 'welcome_test.rb', 'spec/features/welcome_spec.rb', force: true

run "rm -rf app/views/welcome/RAILS_ENV=development.html.erb"
run "rm -rf app/helpers/welcome_helper.rb"
run "rm -rf app/assets/javascripts/welcome.coffee"
run "rm -rf app/assets/stylesheets/welcome.scss"
run "rm -rf spec/helpers"
run "rm -rf spec/controllers"
run "rm -rf spec/views"

gsub_file 'config/routes.rb', /  get 'welcome\/index'\n/, ''
gsub_file 'config/routes.rb', /  get 'welcome\/RAILS_ENV=development'\n/, ''

run "rspec"
