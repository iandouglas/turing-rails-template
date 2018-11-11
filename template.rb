RAILS_REQUIREMENT = "~> 5.1.6".freeze

def apply_template!
  assert_minimum_rails_version
  assert_valid_options
  assert_postgresql
  template "Gemfile.tt", force: true

  copy_file "simplecov", ".simplecov"

  run_with_clean_bundler_env "bin/setup"

  binstubs = %w[
    brakeman bundler
  ]
  binstubs.push("capistrano", "unicorn") if apply_capistrano?
  run_with_clean_bundler_env "bundle binstubs #{binstubs.join(' ')} --force"

  git :init unless preexisting_git_repo?
  empty_directory ".git/safe"

  run_with_clean_bundler_env "bundle install"
  run_with_clean_bundler_env "bin/rake g rspec:install"
  run_with_clean_bundler_env "rails generate rspec:install"

  # Set up the spec folders for RSpec
  run_with_clean_bundler_env "mkdir spec/models"
  run_with_clean_bundler_env "mkdir spec/features"
  run_with_clean_bundler_env "mkdir spec/factories"
  run_with_clean_bundler_env "touch spec/factories/config.rb"

  append_to_file "spec/factories/config.rb" do
    "FactoryBot.define do\nend"
  end

  insert_into_file "spec/rails_helper.rb", before: "RSpec.configure do |config|\n" do
    "require 'simplecov'\nSimpleCov.start"
  end
  insert_into_file "spec/rails_helper.rb", before: "RSpec.configure do |config|\n" do
    "Shoulda::Matchers.configure do |config|\n  config.integrate do |with|\n    with.test_framework :rspec\n    with.library :rails\n  end\nend"
  end
  insert_into_file "spec/rails_helper.rb", after: "RSpec.configure do |config|\n" do
    "  config.include FactoryBot::Syntax::Methods\n"
  end
  insert_into_file "spec/rails_helper.rb", after: "RSpec.configure do |config|\n" do
    "  before(:each) { FactoryBot.reload} \n"
  end
end

require "fileutils"
require "shellwords"

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
apply_template!
