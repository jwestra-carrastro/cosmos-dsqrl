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

require 'openc3/microservices/microservice'
require 'openc3/models/interface_model'
require 'openc3/models/router_model'
require 'openc3/models/interface_status_model'
require 'openc3/models/router_status_model'
require 'openc3/topics/telemetry_topic'
require 'openc3/topics/command_topic'
require 'openc3/topics/command_decom_topic'
require 'openc3/topics/interface_topic'
require 'openc3/topics/router_topic'

module OpenC3
  class InterfaceCmdHandlerThread
    def initialize(interface, tlm, logger: nil, scope:)
      @interface = interface
      @tlm = tlm
      @scope = scope
      @logger = logger
      @logger = Logger unless @logger
    end

    def start
      @thread = Thread.new do
        run()
      rescue Exception => err
        @logger.error "#{@interface.name}: Command handler thread died: #{err.formatted}"
        raise err
      end
    end

    def stop
      OpenC3.kill_thread(self, @thread)
    end

    def graceful_kill
      InterfaceTopic.shutdown(@interface, scope: @scope)
    end

    def run
      InterfaceTopic.receive_commands(@interface, scope: @scope) do |topic, msg_hash|
        OpenC3.with_context(msg_hash) do
          # Check for a raw write to the interface
          if topic =~ /CMD}INTERFACE/
            if msg_hash['shutdown']
              @logger.info "#{@interface.name}: Shutdown requested"
              return
            end
            if msg_hash['connect']
              @logger.info "#{@interface.name}: Connect requested"
              params = []
              if msg_hash['params']
                params = JSON.parse(msg_hash['params'], :allow_nan => true, :create_additions => true)
              end
              @interface = @tlm.attempting(*params)
              next 'SUCCESS'
            end
            if msg_hash['disconnect']
              @logger.info "#{@interface.name}: Disconnect requested"
              @tlm.disconnect(false)
              next 'SUCCESS'
            end
            if msg_hash['raw']
              if @interface.connected?
                @logger.info "#{@interface.name}: Write raw"
                # A raw interface write results in an UNKNOWN packet
                command = System.commands.packet('UNKNOWN', 'UNKNOWN')
                command.received_count += 1
                command = command.clone
                command.buffer = msg_hash['raw']
                command.received_time = Time.now
                CommandTopic.write_packet(command, scope: @scope)
                @interface.write_raw(msg_hash['raw'])
                next 'SUCCESS'
              else
                next "Interface not connected: #{@interface.name}"
              end
            end
            if msg_hash.key?('log_raw')
              if msg_hash['log_raw'] == 'true'
                @logger.info "#{@interface.name}: Enable raw logging"
                @interface.start_raw_logging
              else
                @logger.info "#{@interface.name}: Disable raw logging"
                @interface.stop_raw_logging
              end
              next 'SUCCESS'
            end
          end

          target_name = msg_hash['target_name']
          cmd_name = msg_hash['cmd_name']
          cmd_params = nil
          cmd_buffer = nil
          hazardous_check = nil
          if msg_hash['cmd_params']
            cmd_params = JSON.parse(msg_hash['cmd_params'], :allow_nan => true, :create_additions => true)
            range_check = ConfigParser.handle_true_false(msg_hash['range_check'])
            raw = ConfigParser.handle_true_false(msg_hash['raw'])
            hazardous_check = ConfigParser.handle_true_false(msg_hash['hazardous_check'])
          elsif msg_hash['cmd_buffer']
            cmd_buffer = msg_hash['cmd_buffer']
          end

          begin
            begin
              if cmd_params
                command = System.commands.build_cmd(target_name, cmd_name, cmd_params, range_check, raw)
              elsif cmd_buffer
                if target_name
                  command = System.commands.identify(cmd_buffer, [target_name])
                else
                  command = System.commands.identify(cmd_buffer, @cmd_target_names)
                end
                unless command
                  command = System.commands.packet('UNKNOWN', 'UNKNOWN')
                  command.received_count += 1
                  command = command.clone
                  command.buffer = cmd_buffer
                end
              else
                raise "Invalid command received:\n #{msg_hash}"
              end
              command.received_time = Time.now
            rescue => e
              @logger.error "#{@interface.name}: #{msg_hash}"
              @logger.error "#{@interface.name}: #{e.formatted}"
              next e.message
            end

            if hazardous_check
              hazardous, hazardous_description = System.commands.cmd_pkt_hazardous?(command)
              # Return back the error, description, and the formatted command
              # This allows the error handler to simply re-send the command
              next "HazardousError\n#{hazardous_description}\n#{System.commands.format(command)}" if hazardous
            end

            begin
              if @interface.connected?
                @interface.write(command)
                CommandTopic.write_packet(command, scope: @scope)
                CommandDecomTopic.write_packet(command, scope: @scope)
                InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
                next 'SUCCESS'
              else
                next "Interface not connected: #{@interface.name}"
              end
            rescue => e
              @logger.error "#{@interface.name}: #{e.formatted}"
              next e.message
            end
          rescue => e
            @logger.error "#{@interface.name}: #{e.formatted}"
            next e.message
          end
        end
      end
    end
  end

  class RouterTlmHandlerThread
    def initialize(router, tlm, logger: nil, scope:)
      @router = router
      @tlm = tlm
      @scope = scope
      @logger = logger
      @logger = Logger unless @logger
    end

    def start
      @thread = Thread.new do
        run()
      rescue Exception => err
        @logger.error "#{@router.name}: Telemetry handler thread died: #{err.formatted}"
        raise err
      end
    end

    def stop
      OpenC3.kill_thread(self, @thread)
    end

    def graceful_kill
      RouterTopic.shutdown(@router, scope: @scope)
    end

    def run
      RouterTopic.receive_telemetry(@router, scope: @scope) do |topic, msg_hash|
        # Check for commands to the router itself
        if /CMD}ROUTER/.match?(topic)
          if msg_hash['shutdown']
            @logger.info "#{@router.name}: Shutdown requested"
            return
          end
          if msg_hash['connect']
            @logger.info "#{@router.name}: Connect requested"
            params = []
            if msg_hash['params']
              params = JSON.parse(msg_hash['params'], :allow_nan => true, :create_additions => true)
            end
            @router = @tlm.attempting(*params)
          end
          if msg_hash['disconnect']
            @logger.info "#{@router.name}: Disconnect requested"
            @tlm.disconnect(false)
          end
          if msg_hash.key?('log_raw')
            if msg_hash['log_raw'] == 'true'
              @logger.info "#{@router.name}: Enable raw logging"
              @router.start_raw_logging
            else
              @logger.info "#{@router.name}: Disable raw logging"
              @router.stop_raw_logging
            end
          end
          next 'SUCCESS'
        end

        if @router.connected?
          target_name = msg_hash["target_name"]
          packet_name = msg_hash["packet_name"]

          packet = System.telemetry.packet(target_name, packet_name)
          packet.stored = ConfigParser.handle_true_false(msg_hash["stored"])
          packet.received_time = Time.from_nsec_from_epoch(msg_hash["time"].to_i)
          packet.received_count = msg_hash["received_count"].to_i
          packet.buffer = msg_hash["buffer"]

          begin
            @router.write(packet)
            RouterStatusModel.set(@router.as_json(:allow_nan => true), scope: @scope)
            next 'SUCCESS'
          rescue => e
            @logger.error "#{@router.name}: #{e.formatted}"
            next e.message
          end
        end
      end
    end
  end

  class InterfaceMicroservice < Microservice
    UNKNOWN_BYTES_TO_PRINT = 16

    def initialize(name)
      super(name)
      @interface_or_router = self.class.name.to_s.split("Microservice")[0].upcase.split("::")[-1]
      @scope = name.split("__")[0]
      interface_name = name.split("__")[2]
      if @interface_or_router == 'INTERFACE'
        @interface = InterfaceModel.get_model(name: interface_name, scope: @scope).build
      else
        @interface = RouterModel.get_model(name: interface_name, scope: @scope).build
      end
      @interface.name = interface_name
      # Map the interface to the interface's targets
      @interface.target_names.each do |target_name|
        target = System.targets[target_name]
        target.interface = @interface
      end
      @interface.tlm_target_names.each do |target_name|
        # Initialize the target's packet counters based on the Topic stream
        # Prevents packet count resetting to 0 when interface restarts
        System.telemetry.packets(target_name).each do |packet_name, packet|
          topic = "#{@scope}__TELEMETRY__{#{target_name}}__#{packet_name}"
          msg_id, msg_hash = Topic.get_newest_message(topic)
          if msg_id
            packet.received_count = msg_hash['received_count'].to_i
          else
            packet.received_count = 0
          end
        end
      end
      if @interface.connect_on_startup
        @interface.state = 'ATTEMPTING'
      else
        @interface.state = 'DISCONNECTED'
      end
      if @interface_or_router == 'INTERFACE'
        InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      else
        RouterStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      end

      @interface_thread_sleeper = Sleeper.new
      @cancel_thread = false
      @connection_failed_messages = []
      @connection_lost_messages = []
      @mutex = Mutex.new
      if @interface_or_router == 'INTERFACE'
        @handler_thread = InterfaceCmdHandlerThread.new(@interface, self, logger: @logger, scope: @scope)
      else
        @handler_thread = RouterTlmHandlerThread.new(@interface, self, logger: @logger, scope: @scope)
      end
      @handler_thread.start
    end

    # Called to connect the interface/router. It takes optional parameters to
    # rebuilt the interface/router. Once we set the state to 'ATTEMPTING' the
    # run method handles the actual connection.
    def attempting(*params)
      unless params.empty?
        @interface.disconnect()
        # Build New Interface, this can fail if passed bad parameters
        new_interface = @interface.class.new(*params)
        @interface.copy_to(new_interface)

        # Replace interface for targets
        @interface.target_names.each do |target_name|
          target = System.targets[target_name]
          target.interface = new_interface
        end
        @interface = new_interface
      end

      @interface.state = 'ATTEMPTING'
      if @interface_or_router == 'INTERFACE'
        InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      else
        RouterStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      end
      @interface # Return the interface/router since we may have recreated it
    # Need to rescue Exception so we cover LoadError
    rescue Exception => error
      @logger.error("Attempting connection failed with params #{params} due to #{error.message}")
      if SignalException === error
        @logger.info "#{@interface.name}: Closing from signal"
        @cancel_thread = true
      end
      @interface # Return the original interface/router in case of error
    end

    def run
      begin
        if @interface.read_allowed?
          @logger.info "#{@interface.name}: Starting packet reading"
        else
          @logger.info "#{@interface.name}: Starting connection maintenance"
        end
        while true
          break if @cancel_thread

          case @interface.state
          when 'DISCONNECTED'
            # Just wait to see if we should connect later
            @interface_thread_sleeper.sleep(1)
          when 'ATTEMPTING'
            begin
              @mutex.synchronize do
                # We need to make sure connect is not called after stop() has been called
                connect() unless @cancel_thread
              end
            rescue Exception => connect_error
              handle_connection_failed(connect_error)
              break if @cancel_thread
            end
          when 'CONNECTED'
            if @interface.read_allowed?
              begin
                packet = @interface.read
                if packet
                  handle_packet(packet)
                  @count += 1
                else
                  @logger.info "#{@interface.name}: Internal disconnect requested (returned nil)"
                  handle_connection_lost()
                  break if @cancel_thread
                end
              rescue Exception => err
                handle_connection_lost(err)
                break if @cancel_thread
              end
            else
              @interface_thread_sleeper.sleep(1)
              handle_connection_lost() if !@interface.connected?
            end
          end
        end
      rescue Exception => error
        unless SystemExit === error or SignalException === error
          @logger.error "#{@interface.name}: Packet reading thread died: #{error.formatted}"
          OpenC3.handle_fatal_exception(error)
        end
        # Try to do clean disconnect because we're going down
        disconnect(false)
      end
      if @interface_or_router == 'INTERFACE'
        InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      else
        RouterStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      end
      @logger.info "#{@interface.name}: Stopped packet reading"
    end

    def handle_packet(packet)
      InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      packet.received_time = Time.now.sys unless packet.received_time

      if packet.stored
        # Stored telemetry does not update the current value table
        identified_packet = System.telemetry.identify_and_define_packet(packet, @tlm_target_names)
      else
        # Identify and update packet
        if packet.identified?
          begin
            # Preidentifed packet - place it into the current value table
            identified_packet = System.telemetry.update!(packet.target_name,
                                                         packet.packet_name,
                                                         packet.buffer)
          rescue RuntimeError
            # Packet identified but we don't know about it
            # Clear packet_name and target_name and try to identify
            @logger.warn "#{@interface.name}: Received unknown identified telemetry: #{packet.target_name} #{packet.packet_name}"
            packet.target_name = nil
            packet.packet_name = nil
            identified_packet = System.telemetry.identify!(packet.buffer,
                                                           @tlm_target_names)
          end
        else
          # Packet needs to be identified
          identified_packet = System.telemetry.identify!(packet.buffer,
                                                         @tlm_target_names)
        end
      end

      if identified_packet
        identified_packet.received_time = packet.received_time
        identified_packet.stored = packet.stored
        identified_packet.extra = packet.extra
        packet = identified_packet
      else
        unknown_packet = System.telemetry.update!('UNKNOWN', 'UNKNOWN', packet.buffer)
        unknown_packet.received_time = packet.received_time
        unknown_packet.stored = packet.stored
        unknown_packet.extra = packet.extra
        packet = unknown_packet
        json_hash = CvtModel.build_json_from_packet(packet)
        CvtModel.set(json_hash, target_name: packet.target_name, packet_name: packet.packet_name, scope: scope)
        num_bytes_to_print = [UNKNOWN_BYTES_TO_PRINT, packet.length].min
        data = packet.buffer(false)[0..(num_bytes_to_print - 1)]
        prefix = data.each_byte.map { | byte | sprintf("%02X", byte) }.join()
        @logger.warn "#{@interface.name} #{packet.target_name} packet length: #{packet.length} starting with: #{prefix}"
      end

      # Write to stream
      packet.received_count += 1
      TelemetryTopic.write_packet(packet, scope: @scope)
    end

    def handle_connection_failed(connect_error)
      @error = connect_error
      @logger.error "#{@interface.name}: Connection Failed: #{connect_error.formatted(false, false)}"
      case connect_error
      when SignalException
        @logger.info "#{@interface.name}: Closing from signal"
        @cancel_thread = true
      when Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::ENOTSOCK, Errno::EHOSTUNREACH, IOError
        # Do not write an exception file for these extremely common cases
      else
        if RuntimeError === connect_error and (connect_error.message =~ /canceled/ or connect_error.message =~ /timeout/)
          # Do not write an exception file for these extremely common cases
        else
          @logger.error "#{@interface.name}: #{connect_error.formatted}"
          unless @connection_failed_messages.include?(connect_error.message)
            OpenC3.write_exception_file(connect_error)
            @connection_failed_messages << connect_error.message
          end
        end
      end
      disconnect() # Ensure we do a clean disconnect
    end

    def handle_connection_lost(err = nil, reconnect: true)
      if err
        @error = err
        @logger.info "#{@interface.name}: Connection Lost: #{err.formatted(false, false)}"
        case err
        when SignalException
          @logger.info "#{@interface.name}: Closing from signal"
          @cancel_thread = true
        when Errno::ECONNABORTED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EBADF, Errno::ENOTSOCK, IOError
          # Do not write an exception file for these extremely common cases
        else
          @logger.error "#{@interface.name}: #{err.formatted}"
          unless @connection_lost_messages.include?(err.message)
            OpenC3.write_exception_file(err)
            @connection_lost_messages << err.message
          end
        end
      else
        @logger.info "#{@interface.name}: Connection Lost"
      end
      disconnect(reconnect) # Ensure we do a clean disconnect
    end

    def connect
      @logger.info "#{@interface.name}: Connecting ..."
      @interface.connect
      @interface.state = 'CONNECTED'
      if @interface_or_router == 'INTERFACE'
        InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      else
        RouterStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      end
      @logger.info "#{@interface.name}: Connection Success"
    end

    def disconnect(allow_reconnect = true)
      return if @interface.state == 'DISCONNECTED' && !@interface.connected?

      # Synchronize the calls to @interface.disconnect since it takes an unknown
      # amount of time. If two calls to disconnect stack up, the if statement
      # should avoid multiple calls to disconnect.
      @mutex.synchronize do
        begin
          @interface.disconnect if @interface.connected?
        rescue => e
          @logger.error "Disconnect: #{@interface.name}: #{e.formatted}"
        end
      end

      # If the interface is set to auto_reconnect then delay so the thread
      # can come back around and allow the interface a chance to reconnect.
      if allow_reconnect and @interface.auto_reconnect and @interface.state != 'DISCONNECTED'
        attempting()
        if !@cancel_thread
          # @logger.debug "reconnect delay: #{@interface.reconnect_delay}"
          @interface_thread_sleeper.sleep(@interface.reconnect_delay)
        end
      else
        @interface.state = 'DISCONNECTED'
        if @interface_or_router == 'INTERFACE'
          InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
        else
          RouterStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
        end
      end
    end

    # Disconnect from the interface and stop the thread
    def stop
      @logger.info "#{@interface.name}: stop requested"
      @mutex.synchronize do
        # Need to make sure that @cancel_thread is set and the interface disconnected within
        # mutex to ensure that connect() is not called when we want to stop()
        @cancel_thread = true
        @handler_thread.stop
        @interface_thread_sleeper.cancel
        @interface.disconnect
        if @interface_or_router == 'INTERFACE'
          valid_interface = InterfaceStatusModel.get_model(name: @interface.name, scope: @scope)
        else
          valid_interface = RouterStatusModel.get_model(name: @interface.name, scope: @scope)
        end
        valid_interface.destroy if valid_interface
      end
    end

    def shutdown(sig = nil)
      @logger.info "#{@interface.name}: shutdown requested"
      stop()
      super()
    end

    def graceful_kill
      # Just to avoid warning
    end
  end
end

OpenC3::InterfaceMicroservice.run if __FILE__ == $0
