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

module OpenC3
  class NotificationModel
    attr_reader :time, :severity, :url, :title, :body

    def initialize(time:, severity:, url:, title:, body:)
      @time = time
      @severity = severity
      @url = url
      @title = title
      @body = body
    end

    def as_json(*a)
      { "time" => @time,
        "severity" => @severity,
        "url" => @url,
        "title" => @title,
        "body" => @body }
    end
  end
end
