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

require 'openc3/models/scope_model'

class ScopesController < ModelController
  def initialize
    @model_class = OpenC3::ScopeModel
  end

  def index
    # No authorization required
    render :json => @model_class.names(scope: params[:scope])
  end

  def create(update_model = false)
    return unless authorization('superadmin')
    super(update_model)
  rescue Exception => e
    render(:json => { :status => 'error', :message => e.message }, :status => 500) and return
  end

  def destroy
    return unless authorization('superadmin')
    result = OpenC3::ProcessManager.instance.spawn(["ruby", "/openc3/bin/openc3cli", "destroyscope", params[:id]], "scope_uninstall", params[:id], Time.now + 2.hours, scope: 'DEFAULT')
    render :json => result
  rescue Exception => e
    render(:json => { :status => 'error', :message => e.message }, :status => 500) and return
  end
end
