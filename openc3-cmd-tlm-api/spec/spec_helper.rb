# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved

# This file was generated by the `rails generate rspec:install` command. Conventionally, all
# specs live under a `spec` directory, which RSpec adds to the `$LOAD_PATH`.
# The generated `.rspec` file contains `--require spec_helper` which will cause
# this file to always be loaded, without a need to explicitly require it in any
# files.
#
# Given that it is always loaded, you are encouraged to keep this file as
# light-weight as possible. Requiring heavyweight dependencies from this file
# will add to the boot time of your test suite on EVERY test run, even for an
# individual file that may not need all of that loaded. Instead, consider making
# a separate helper file that requires the additional dependencies and performs
# the additional setup, and require it from the spec files that actually need
# it.
#
# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration

# NOTE: You MUST require simplecov before anything else!
if !ENV['OPENC3_NO_SIMPLECOV']
  require 'simplecov'
  if ENV['GITHUB_WORKFLOW']
    require 'simplecov-cobertura'
    SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
  else
    SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
  end
  SimpleCov.start do
    merge_timeout 60 * 60 # merge the last hour of results
    add_filter '/spec/' # no coverage on spec files
    root = File.dirname(__FILE__)
    root.to_s
  end
  SimpleCov.at_exit do
    OpenC3.disable_warnings do
      Encoding.default_external = Encoding::UTF_8
      Encoding.default_internal = nil
    end
    SimpleCov.result.format!
  end
end

# Disable Redis and Fluentd in the Logger
ENV['OPENC3_NO_STORE'] = 'true'
# Set some passwords
ENV['OPENC3_API_PASSWORD'] = 'openc3'
# Set internal openc3 password
ENV['OPENC3_SERVICE_PASSWORD'] = 'openc3service'
# Set redis host
ENV['OPENC3_REDIS_HOSTNAME'] = '127.0.0.1'
# Set redis port
ENV['OPENC3_REDIS_PORT'] = '6379'
# Set redis host
ENV['OPENC3_REDIS_EPHEMERAL_HOSTNAME'] = '127.0.0.1'
# Set redis port
ENV['OPENC3_REDIS_EPHEMERAL_PORT'] = '6380'
# Set redis username
ENV['OPENC3_REDIS_USERNAME'] = 'openc3'
# Set redis password
ENV['OPENC3_REDIS_PASSWORD'] = 'openc3password'
# Set minio password
ENV['OPENC3_MINIO_USERNAME'] = 'openc3minio'
# Set minio password
ENV['OPENC3_MINIO_PASSWORD'] = 'openc3miniopassword'
# Set openc3 scope
ENV['OPENC3_SCOPE'] = 'DEFAULT'

$openc3_scope = ENV['OPENC3_SCOPE']
$openc3_token = ENV['OPENC3_API_PASSWORD']

def setup_system(targets = ["SYSTEM", "INST", "EMPTY"])
  require 'openc3/system'
  dir = File.join(__dir__, '..', '..', 'openc3', 'spec', 'install', 'config', 'targets')
  OpenC3::System.class_variable_set(:@@instance, nil)
  OpenC3::System.instance(targets, dir)
  require 'openc3/utilities/logger'
  OpenC3::Logger.stdout = false
end

def mock_redis
  require 'redis'
  require 'mock_redis'
  redis = MockRedis.new
  allow(Redis).to receive(:new).and_return(redis)
  OpenC3::Store.instance_variable_set(:@instance, nil)
  OpenC3::EphemeralStore.instance_variable_set(:@instance, nil)
  redis
end

SPEC_DIR = File.dirname(__FILE__)

RSpec.configure do |config|
  config.before(:all) do
    # Most tests want to disable authorization for simplicity
    $openc3_authorize = false
  end

  # rspec-expectations config goes here. You can use an alternate
  # assertion/expectation library such as wrong or the stdlib/minitest
  # assertions if you prefer.
  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4. It makes the `description`
    # and `failure_message` of custom matchers include text for helper methods
    # defined using `chain`, e.g.:
    #     be_bigger_than(2).and_smaller_than(4).description
    #     # => "be bigger than 2 and smaller than 4"
    # ...rather than:
    #     # => "be bigger than 2"
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # rspec-mocks config goes here. You can use an alternate test double
  # library (such as bogus or mocha) by changing the `mock_with` option here.
  config.mock_with :rspec do |mocks|
    # Prevents you from mocking or stubbing a method that does not exist on
    # a real object. This is generally recommended, and will default to
    # `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end

  # This option will default to `:apply_to_host_groups` in RSpec 4 (and will
  # have no way to turn it off -- the option exists only for backwards
  # compatibility in RSpec 3). It causes shared context metadata to be
  # inherited by the metadata hash of host groups and examples, rather than
  # triggering implicit auto-inclusion in groups with matching metadata.
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # This allows you to limit a spec run to individual examples or groups
  # you care about by tagging them with `:focus` metadata. When nothing
  # is tagged with `:focus`, all examples get run. RSpec also provides
  # aliases for `it`, `describe`, and `context` that include `:focus`
  # metadata: `fit`, `fdescribe` and `fcontext`, respectively.
  config.filter_run_when_matching :focus

  # Allows RSpec to persist some state between runs in order to support
  # the `--only-failures` and `--next-failure` CLI options. We recommend
  # you configure your source control system to ignore this file.
  config.example_status_persistence_file_path = "spec/examples.txt"

  # Limits the available syntax to the non-monkey patched syntax that is
  # recommended. For more details, see:
  #   - http://rspec.info/blog/2012/06/rspecs-new-expectation-syntax/
  #   - http://www.teaisaweso.me/blog/2013/05/27/rspecs-new-message-expectation-syntax/
  #   - http://rspec.info/blog/2014/05/notable-changes-in-rspec-3/#zero-monkey-patching-mode
  config.disable_monkey_patching!

  # This setting enables warnings. It's recommended, but in some cases may
  # be too noisy due to issues in dependencies.
  # config.warnings = true

  # Many RSpec users commonly either run the entire suite or an individual
  # file, and it's useful to allow more verbose output when running an
  # individual spec file.
  if config.files_to_run.one?
    # Use the documentation formatter for detailed output,
    # unless a formatter has already been configured
    # (e.g. via a command-line flag).
    config.default_formatter = "doc"
  end

  # Print the 10 slowest examples and example groups at the
  # end of the spec run, to help surface which specs are running
  # particularly slow.
  # config.profile_examples = 10

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = :random

  # Seed global randomization in this process using the `--seed` CLI option.
  # Setting this allows you to use `--seed` to deterministically reproduce
  # test failures related to randomization by passing the same `--seed` value
  # as the one that triggered the failure.
  Kernel.srand config.seed
end
