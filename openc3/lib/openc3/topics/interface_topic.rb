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

require 'openc3/topics/topic'

module OpenC3
  class InterfaceTopic < Topic
    # Generate a list of topics for this interface. This includes the interface itself
    # and all the targets which are assigned to this interface.
    def self.topics(interface, scope:)
      topics = []
      topics << "{#{scope}__CMD}INTERFACE__#{interface.name}"
      interface.cmd_target_names.each do |target_name|
        topics << "{#{scope}__CMD}TARGET__#{target_name}"
      end
      topics
    end

    def self.receive_commands(interface, scope:)
      while true
        Topic.read_topics(InterfaceTopic.topics(interface, scope: scope)) do |topic, msg_id, msg_hash, redis|
          result = yield topic, msg_hash
          ack_topic = topic.split("__")
          ack_topic[1] = 'ACK' + ack_topic[1]
          ack_topic = ack_topic.join("__")
          Topic.write_topic(ack_topic, { 'result' => result, 'id' => msg_id }, '*', 100)
        end
      end
    end

    def self.write_raw(interface_name, data, scope:)
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'raw' => data }, '*', 100)
    end

    def self.connect_interface(interface_name, *interface_params, scope:)
      if interface_params && !interface_params.empty?
        Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'connect' => 'true', 'params' => JSON.generate(interface_params) }, '*', 100)
      else
        Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'connect' => 'true' }, '*', 100)
      end
    end

    def self.disconnect_interface(interface_name, scope:)
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'disconnect' => 'true' }, '*', 100)
    end

    def self.start_raw_logging(interface_name, scope:)
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'log_raw' => 'true' }, '*', 100)
    end

    def self.stop_raw_logging(interface_name, scope:)
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'log_raw' => 'false' }, '*', 100)
    end

    def self.shutdown(interface, scope:)
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface.name}", { 'shutdown' => 'true' }, '*', 100)
      sleep 1 # Give some time for the interface to shutdown
      InterfaceTopic.clear_topics(InterfaceTopic.topics(interface, scope: scope))
    end
  end
end
