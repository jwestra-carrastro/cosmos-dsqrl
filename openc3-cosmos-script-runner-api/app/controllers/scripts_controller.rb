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

require 'json'

class ScriptsController < ApplicationController
  # Check for a class inheriting from OpenC3::Suite or OpenC3::TestSuite
  # e.g. class MyClass < OpenC3::Suite
  SUITE_REGEX = /\s*class\s+\w+\s+<\s+(OpenC3|Cosmos)::(Suite|TestSuite)\s+/

  def index
    return unless authorization('script_view')
    render :json => Script.all(params[:scope])
  end

  def delete_temp
    return unless authorization('script_edit')
    render :json => Script.delete_temp(params[:scope])
  end

  def body
    return unless authorization('script_view')
    user = user_info(request.headers['HTTP_AUTHORIZATION'])
    username = user['username']

    file = Script.body(params[:scope], params[:name])
    if file
      success = true
      locked = Script.locked?(params[:scope], params[:name])
      unless locked
        Script.lock(params[:scope], params[:name], username || 'Someone else')
      end
      breakpoints = Script.get_breakpoints(params[:scope], params[:name])
      results = {
        contents: file,
        breakpoints: breakpoints,
        locked: locked
      }
      if (file =~ SUITE_REGEX)
        results_suites, results_error, success = Script.process_suite(params[:name], file, username: username, scope: params[:scope])
        results['suites'] = results_suites
        results['error'] = results_error
        results['success'] = success
      end
      # Using 'render :json => results' results in a raw json string like:
      # {"contents":"{\"json_class\":\"String\",\"raw\":[35,226,128...]}","breakpoints":[],"locked":false}
      render plain: JSON.generate(results)
    else
      head :not_found
    end
  end

  def create
    return unless authorization('script_edit')
    user = user_info(request.headers['HTTP_AUTHORIZATION'])
    username = user['username']
    Script.create(params.permit(:scope, :name, :text, breakpoints: []))
    results = {}
    if (params[:text] =~ SUITE_REGEX)
      results_suites, results_error, success = Script.process_suite(params[:name], params[:text], username: username, scope: params[:scope])
      results['suites'] = results_suites
      results['error'] = results_error
      results['success'] = success
    end
    OpenC3::Logger.info("Script created: #{params[:name]}", scope: params[:scope], user: user) if success
    render :json => results
  rescue => e
    render(json: { status: 'error', message: e.message }, status: 500)
  end

  def run
    return unless authorization('script_run')
    user = user_info(request.headers['HTTP_AUTHORIZATION'])
    username = user['username']
    suite_runner = params[:suiteRunner] ? params[:suiteRunner].as_json(:allow_nan => true) : nil
    disconnect = params[:disconnect] == 'disconnect'
    environment = params[:environment]
    running_script_id = Script.run(params[:scope], params[:name], suite_runner, disconnect, environment, username: username)
    if running_script_id
      OpenC3::Logger.info("Script started: #{params[:name]}", scope: params[:scope], user: user)
      render :plain => running_script_id.to_s
    else
      head :not_found
    end
  end

  def lock
    return unless authorization('script_edit')
    user = user_info(request.headers['HTTP_AUTHORIZATION'])
    username = user['username']
    username ||= 'Someone else' # Generic name that makes sense in the lock toast in Script Runner (EE has the actual username)
    Script.lock(params[:scope], params[:name], username)
    render status: 200
  end

  def unlock
    return unless authorization('script_edit')
    user = user_info(request.headers['HTTP_AUTHORIZATION'])
    username = user['username']
    username ||= 'Someone else'
    locked_by = Script.locked?(params[:scope], params[:name])
    Script.unlock(params[:scope], params[:name]) if username == locked_by
    render status: 200
  end

  def destroy
    return unless authorization('script_edit')
    Script.destroy(*params.require([:scope, :name]))
    OpenC3::Logger.info("Script destroyed: #{params[:name]}", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
    head :ok
  rescue => e
    render(json: { status: 'error', message: e.message }, status: 500)
  end

  def syntax
    return unless authorization('script_run')
    script = Script.syntax(request.body.read)
    if script
      render :json => script
    else
      head :error
    end
  end

  def instrumented
    return unless authorization('script_view')
    script = Script.instrumented(params[:name], request.body.read)
    if script
      render :json => script
    else
      head :error
    end
  end

  def delete_all_breakpoints
    return unless authorization('script_edit')
    OpenC3::Store.del("#{params[:scope]}__script-breakpoints")
    head :ok
  end
end
