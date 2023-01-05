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

require 'openc3/models/target_model'
require 'openc3/microservices/microservice'
require 'openc3/utilities/bucket'
require 'openc3/utilities/bucket_utilities'

module OpenC3
  class CleanupMicroservice < Microservice
    def run
      split_name = @name.split("__")
      target_name = split_name[-1]
      target = TargetModel.get_model(name: target_name, scope: @scope)

      bucket = Bucket.getClient()
      while true
        break if @cancel_thread

        @state = 'GETTING_OBJECTS'
        start_time = Time.now
        [
         ["#{@scope}/raw_logs/cmd/#{target_name}", target.cmd_log_retain_time],
         ["#{@scope}/decom_logs/cmd/#{target_name}", target.cmd_decom_log_retain_time],
         ["#{@scope}/raw_logs/tlm/#{target_name}", target.tlm_log_retain_time],
         ["#{@scope}/decom_logs/tlm/#{target_name}", target.tlm_decom_log_retain_time],
         ["#{@scope}/reduced_minute_logs/tlm/#{target_name}", target.reduced_minute_log_retain_time],
         ["#{@scope}/reduced_hour_logs/tlm/#{target_name}", target.reduced_hour_log_retain_time],
         ["#{@scope}/reduced_day_logs/tlm/#{target_name}", target.reduced_day_log_retain_time],
        ].each do |prefix, retain_time|
          next unless retain_time
          time = start_time - retain_time
          oldest_list = BucketUtilities.files_between_time(ENV['OPENC3_LOGS_BUCKET'], prefix, nil, time)
          if oldest_list.length > 0
            @state = 'DELETING_OBJECTS'
            oldest_list.each_slice(1000) do |slice|
              bucket.delete_objects(bucket: ENV['OPENC3_LOGS_BUCKET'], keys: slice)
              @logger.info("Deleted #{slice.length} #{target_name} log files")
            end
          end
        end

        @count += 1
        @state = 'SLEEPING'
        break if @microservice_sleeper.sleep(target.cleanup_poll_time)
      end
    end
  end
end

OpenC3::CleanupMicroservice.run if __FILE__ == $0
