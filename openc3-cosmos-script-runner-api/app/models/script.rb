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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'tempfile'
require 'openc3/utilities/target_file'
require 'openc3/script/suite'
require 'openc3/script/suite_runner'
require 'openc3/tools/test_runner/test'

OpenC3.require_file 'openc3/utilities/store'

class Script < OpenC3::TargetFile
  def self.all(scope)
    super(scope, nil, include_temp: true) # No path matchers
  end

  def self.lock(scope, name, username)
    name = name.split('*')[0] # Split '*' that indicates modified
    OpenC3::Store.hset("#{scope}__script-locks", name, username)
  end

  def self.unlock(scope, name)
    name = name.split('*')[0] # Split '*' that indicates modified
    OpenC3::Store.hdel("#{scope}__script-locks", name)
  end

  def self.locked?(scope, name)
    name = name.split('*')[0] # Split '*' that indicates modified
    locked_by = OpenC3::Store.hget("#{scope}__script-locks", name)
    locked_by ||= false
    locked_by
  end

  def self.get_breakpoints(scope, name)
    breakpoints = OpenC3::Store.hget("#{scope}__script-breakpoints", name.split('*')[0]) # Split '*' that indicates modified
    return JSON.parse(breakpoints, :allow_nan => true, :create_additions => true) if breakpoints
    []
  end

  def self.process_suite(name, contents, new_process: true, username: nil, scope:)
    start = Time.now
    temp = Tempfile.new(%w[suite .rb])

    # Remove any carriage returns which ruby doesn't like
    temp.write(contents.gsub(/\r/, ' '))
    temp.close

    # We open a new ruby process so as to not pollute the API with require
    results = nil
    success = true
    if new_process
      runner_path = File.join(RAILS_ROOT, 'scripts', 'run_suite_analysis.rb')
      process = ChildProcess.build('ruby', runner_path.to_s, scope, temp.path)
      process.cwd = File.join(RAILS_ROOT, 'scripts')

      # Check for offline access token
      model = nil
      model = OpenC3::OfflineAccessModel.get_model(name: username, scope: scope) if username and username != ''

      # Set proper secrets for running script
      process.environment['SECRET_KEY_BASE'] = nil
      process.environment['OPENC3_REDIS_USERNAME'] = ENV['OPENC3_SR_REDIS_USERNAME']
      process.environment['OPENC3_REDIS_PASSWORD'] = ENV['OPENC3_SR_REDIS_PASSWORD']
      process.environment['OPENC3_BUCKET_USERNAME'] = ENV['OPENC3_SR_BUCKET_USERNAME']
      process.environment['OPENC3_BUCKET_PASSWORD'] = ENV['OPENC3_SR_BUCKET_PASSWORD']
      process.environment['OPENC3_SR_REDIS_USERNAME'] = nil
      process.environment['OPENC3_SR_REDIS_PASSWORD'] = nil
      process.environment['OPENC3_SR_BUCKET_USERNAME'] = nil
      process.environment['OPENC3_SR_BUCKET_PASSWORD'] = nil
      process.environment['OPENC3_API_CLIENT'] = ENV['OPENC3_API_CLIENT']
      if model and model.offline_access_token
        auth = OpenC3::OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
        valid_token = auth.get_token_from_refresh_token(model.offline_access_token)
        if valid_token
          process.environment['OPENC3_API_TOKEN'] = model.offline_access_token
        else
          model.offline_access_token = nil
          model.update
          raise "offline_access token invalid for script"
        end
      else
        process.environment['OPENC3_API_USER'] = ENV['OPENC3_API_USER']
        if ENV['OPENC3_API_PASSWORD'] || ENV['OPENC3_SERVICE_PASSWORD']
          process.environment['OPENC3_API_PASSWORD'] = ENV['OPENC3_API_PASSWORD'] || ENV['OPENC3_SERVICE_PASSWORD']
        else
          raise "No authentication available for script"
        end
      end
      process.environment['GEM_HOME'] = ENV['GEM_HOME']

      # Spawned process should not be controlled by same Bundler constraints as spawning process
      ENV.each do |key, value|
        if key =~ /^BUNDLE/
          process.environment[key] = nil
        end
      end
      process.environment['RUBYOPT'] = nil # Removes loading bundler setup
      process.environment['OPENC3_SCOPE'] = scope

      stdout = Tempfile.new("child-stdout")
      stdout.sync = true
      stderr = Tempfile.new("child-stderr")
      stderr.sync = true
      process.io.stdout = stdout
      process.io.stderr = stderr
      process.start
      process.wait
      stdout.rewind
      stdout_results = stdout.read
      stdout.close
      stdout.unlink
      stderr.rewind
      stderr_results = stderr.read
      stderr.close
      stderr.unlink
      success = process.exit_code == 0
    else
      require temp.path
      stdout_results = OpenC3::SuiteRunner.build_suites.as_json(:allow_nan => true).to_json(:allow_nan => true)
    end
    temp.delete
    puts "Processed #{name} in #{Time.now - start} seconds"
    # Make sure we're getting the last line which should be the suite
    puts "Stdout Results:#{stdout_results}:"
    puts "Stderr Results:#{stderr_results}:"
    stdout_results = stdout_results.split("\n")[-1] if stdout_results
    return stdout_results, stderr_results, success
  end

  def self.create(params)
    super(params[:scope], params[:name], params[:text])
    breakpoints = params[:breakpoints]
    OpenC3::Store.hset("#{params[:scope]}__script-breakpoints", params[:name], breakpoints.as_json(:allow_nan => true).to_json(:allow_nan => true)) if breakpoints
  end

  def self.destroy(scope, name)
    super(scope, name)
    OpenC3::Store.hdel("#{scope}__script-breakpoints", name)
  end

  def self.run(
    scope,
    name,
    suite_runner = nil,
    disconnect = false,
    environment = nil,
    username: ''
  )
    RunningScript.spawn(scope, name, suite_runner, disconnect, environment, username: username)
  end

  def self.instrumented(filename, text)
    {
      'title' => 'Instrumented Script',
      'description' =>
        RunningScript.instrument_script(
          text,
          filename,
          true,
        ).split("\n").as_json(:allow_nan => true).to_json(:allow_nan => true),
    }
  end

  def self.syntax(text)
    check_process = IO.popen('ruby -c -rubygems 2>&1', 'r+')
    check_process.write("require 'openc3'; require 'openc3/script'; " + text)
    check_process.close_write
    results = check_process.readlines
    check_process.close
    if results
      if results.any?(/Syntax OK/)
        return(
          {
            'title' => 'Syntax Check Successful',
            'description' => results.as_json(:allow_nan => true).to_json(:allow_nan => true),
          }
        )
      else
        # Results is an array of strings like this: ":2: syntax error ..."
        # Normally the procedure comes before the first colon but since we
        # are writing to the process this is blank so we throw it away
        results.map! { |result| result.split(':')[1..-1].join(':') }
        return(
          { 'title' => 'Syntax Check Failed', 'description' => results.as_json(:allow_nan => true).to_json(:allow_nan => true) }
        )
      end
    else
      return(
        {
          'title' => 'Syntax Check Exception',
          'description' => 'Ruby syntax check unexpectedly returned nil',
        }
      )
    end
  end
end
