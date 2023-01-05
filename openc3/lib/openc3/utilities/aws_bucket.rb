# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/bucket'
module Aws
  autoload(:S3, 'openc3/utilities/s3_autoload.rb')
end

module OpenC3
  class AwsBucket < Bucket
    CREATE_CHECK_COUNT = 100 # 10 seconds

    def initialize
      @client = Aws::S3::Client.new
    end

    def create(bucket)
      unless exist?(bucket)
        @client.create_bucket({ bucket: bucket })
        count = 0
        until exist?(bucket) or count > CREATE_CHECK_COUNT
          sleep(0.1)
          count += 1
        end
      end
      bucket
    end

    def ensure_public(bucket)
      policy = <<~EOL
      {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Action": [
              "s3:GetBucketLocation",
              "s3:ListBucket"
            ],
            "Effect": "Allow",
            "Principal": {
              "AWS": [
                "*"
              ]
            },
            "Resource": [
              "arn:aws:s3:::#{bucket}"
            ],
            "Sid": ""
          },
          {
            "Action": [
              "s3:GetObject"
            ],
            "Effect": "Allow",
            "Principal": {
              "AWS": [
                "*"
              ]
            },
            "Resource": [
              "arn:aws:s3:::#{bucket}/*"
            ],
            "Sid": ""
          }
        ]
      }
      EOL
      @client.put_bucket_policy({ bucket: bucket, policy: policy })
    end

    def exist?(bucket)
      @client.head_bucket({ bucket: bucket })
      true
    rescue Aws::S3::Errors::NotFound
      false
    end

    def delete(bucket)
      if exist?(bucket)
        @client.delete_bucket({ bucket: bucket })
      end
    end

    def get_object(bucket:, key:, path: nil)
      if path
        @client.get_object(bucket: bucket, key: key, response_target: path)
      else
        @client.get_object(bucket: bucket, key: key)
      end
    # If the key is not found return nil
    rescue Aws::S3::Errors::NoSuchKey
      nil
    end

    def list_objects(bucket:, prefix: nil, max_request: 1000, max_total: 100_000)
      token = nil
      result = []
      while true
        resp = @client.list_objects_v2(bucket: bucket, prefix: prefix, max_keys: max_request)
        result.concat(resp.contents)
        break if result.length >= max_total
        break unless resp.is_truncated
        token = resp.next_continuation_token
      end
      # Array of objects with key and size methods
      result
    end

    # Lists the directories under a specified path
    def list_directories(bucket:, path:)
      # Trailing slash is important in AWS S3 when listing files
      # See https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Types/ListObjectsV2Output.html#common_prefixes-instance_method
      if path[-1] != '/'
        path += '/'
      end
      token = nil
      result = []
      while true
        resp = @client.list_objects_v2({
          bucket: bucket,
          max_keys: 1000,
          prefix: path,
          delimiter: '/',
          continuation_token: token
        })
        resp.common_prefixes.each do |item|
          # If path was DEFAULT/targets_modified/ then the
          # results look like DEFAULT/targets_modified/INST/
          result << item.prefix.split('/')[-1]
        end
        break unless resp.is_truncated
        token = resp.next_continuation_token
      end
      result
    end

    # put_object fires off the request to store but does not confirm
    def put_object(bucket:, key:, body:, content_type: nil, cache_control: nil, metadata: nil)
      @client.put_object(bucket: bucket, key: key, body: body,
        content_type: content_type, cache_control: cache_control, metadata: metadata)
    end

    # @returns [Boolean] Whether the file exists
    def check_object(bucket:, key:)
      @client.wait_until(:object_exists,
        {
          bucket: bucket,
          key: key
        },
        {
          max_attempts: 30,
          delay: 0.1, # seconds
        }
      )
      true
    rescue Aws::Waiters::Errors::TooManyAttemptsError
      false
    end

    def delete_object(bucket:, key:)
      @client.delete_object(bucket: bucket, key: key)
    end

    def delete_objects(bucket:, keys:)
      @client.delete_objects(bucket: bucket, delete: { objects: keys.map {|key| { key: key } } })
    end

    def presigned_request(bucket:, key:, method:, internal: true)
      s3_presigner = Aws::S3::Presigner.new

      if internal
        prefix = '/'
      else
        prefix = '/files/'
      end

      url, headers = s3_presigner.presigned_request(method, bucket: bucket, key: key)
      return {
        :url => prefix + url.split('/')[3..-1].join('/'),
        :headers => headers,
        :method => method.to_s.split('_')[0],
      }
    end
  end
end
