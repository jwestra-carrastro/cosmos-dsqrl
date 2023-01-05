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
require 'openc3/topics/topic'

module OpenC3
  class TextLogMicroservice < Microservice
    def initialize(name)
      super(name)
      @config['options'].each do |option|
        case option[0].upcase
        when 'CYCLE_TIME' # Maximum time between log files
          @cycle_time = option[1].to_i
        when 'CYCLE_SIZE' # Maximum size of a log file
          @cycle_size = option[1].to_i
        else
          @logger.error("Unknown option passed to microservice #{@name}: #{option}")
        end
      end

      # These settings limit the log file to 10 minutes or 50MB of data, whichever comes first
      @cycle_time = 600 unless @cycle_time # 10 minutes
      @cycle_size = 50_000_000 unless @cycle_size # ~50 MB
    end

    def run
      setup_tlws()
      while true
        break if @cancel_thread

        Topic.read_topics(@topics) do |topic, msg_id, msg_hash, redis|
          break if @cancel_thread

          log_data(topic, msg_id, msg_hash, redis)
        end
      end
    end

    def setup_tlws
      @tlws = {}
      @topics.each do |topic|
        topic_split = topic.gsub(/{|}/, '').split("__") # Remove the redis hashtag curly braces
        scope = topic_split[0]
        log_name = topic_split[1]
        remote_log_directory = "#{scope}/text_logs/#{log_name}"
        @tlws[topic] = TextLogWriter.new(remote_log_directory, true, @cycle_time, @cycle_size, nil, nil, false)
      end
    end

    def log_data(topic, msg_id, msg_hash, redis)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      keys = msg_hash.keys
      keys.delete("time")
      entry = keys.reduce("") { |data, key| data + "#{key}: #{msg_hash[key]}\t" }
      @tlws[topic].write(msg_hash["time"].to_i, entry, topic, msg_id)
      @count += 1
      diff = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start # seconds as a float
      @metric.add_sample(name: "log_duration_seconds", value: diff, labels: {})
    rescue => err
      @error = err
      @logger.error("#{@name} error: #{err.formatted}")
    end

    def shutdown
      # Make sure all the existing logs are properly closed down
      threads = []
      @tlws.each do |topic, tlw|
        threads.concat(tlw.shutdown)
      end
      # Wait for all the logging threads to move files to buckets
      threads.flatten.compact.each do |thread|
        thread.join
      end
      super()
    end
  end
end

OpenC3::TextLogMicroservice.run if __FILE__ == $0
