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

require 'openc3/utilities/target_file'

class Screen < OpenC3::TargetFile
  def self.all(scope, target)
    result = super(scope, ['screens'])
    screens = []
    result.each do |path|
      filename = path.split('*')[0] # Don't differentiate modified - TODO: Should we?
      split_filename = filename.split('/')
      target_name = split_filename[0]
      next unless target == target_name
      next unless File.extname(filename) == ".txt"
      screen_name = File.basename(filename, ".txt")
      next if screen_name[0] == '_' # underscore filenames are partials
      screens << screen_name.upcase # Screen names are upcase
    end
    screens
  end

  def self.find(scope, target, screen)
    name = screen.split('*')[0].downcase # Split '*' that indicates modified - Filenames are lowercase
    body(scope, "#{target}/screens/#{name}.txt")
  end

  def self.create(scope, target, screen, text)
    name = "#{target}/screens/#{screen.downcase}.txt"
    super(scope, name, text)
  end

  def self.destroy(scope, target, screen)
    name = "#{target}/screens/#{screen.downcase}.txt"
    super(scope, name)
  end
end
