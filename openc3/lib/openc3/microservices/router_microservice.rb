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

require 'openc3/microservices/interface_microservice'

module OpenC3
  class RouterMicroservice < InterfaceMicroservice
    def handle_packet(packet)
      @count += 1
      RouterStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      if !packet.identified?
        # Need to identify so we can find the target
        identified_packet = System.commands.identify(packet.buffer(false), @cmd_target_names)
        packet = identified_packet if identified_packet
      end

      begin
        RouterTopic.route_command(packet, @cmd_target_names, scope: @scope)
        @count += 1
      rescue Exception => err
        @error = err
        @logger.error "Error routing command from #{@interface.name}\n#{err.formatted}"
      end
    end
  end
end

OpenC3::RouterMicroservice.run if __FILE__ == $0
