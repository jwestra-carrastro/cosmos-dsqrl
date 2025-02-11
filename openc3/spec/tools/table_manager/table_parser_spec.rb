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

require 'spec_helper'
require 'openc3'
require 'openc3/tools/table_manager/table_config'
require 'openc3/tools/table_manager/table_parser'
require 'tempfile'

module OpenC3

  describe TableParser do

    describe "process_file" do
      before(:each) do
        @tc = TableConfig.new
      end

      it "complains if there are not enough parameters" do
        tf = Tempfile.new('unittest')
        tf.puts("TABLE table")
        tf.close
        expect { @tc.process_file(tf.path) }.to raise_error(ConfigParser::Error, /Not enough parameters for TABLE/)
        tf.unlink

        tf = Tempfile.new('unittest')
        tf.puts("TABLE table BIG_ENDIAN ROW_COLUMN")
        tf.close
        expect { @tc.process_file(tf.path) }.to raise_error(ConfigParser::Error, /Not enough parameters for TABLE/)
        tf.unlink
      end

      it "complains if there are too many parameters" do
        tf = Tempfile.new('unittest')
        tf.puts "TABLE table LITTLE_ENDIAN KEY_VALUE 'Table' extra"
        tf.close
        expect { @tc.process_file(tf.path) }.to raise_error(ConfigParser::Error, /Too many parameters for TABLE/)
        tf.unlink

        tf = Tempfile.new('unittest')
        tf.puts "TABLE table LITTLE_ENDIAN ROW_COLUMN 2 'Table' extra"
        tf.close
        expect { @tc.process_file(tf.path) }.to raise_error(ConfigParser::Error, /Too many parameters for TABLE/)
        tf.unlink
      end

      it "complains about invalid type" do
        tf = Tempfile.new('unittest')
        tf.puts 'TABLE table LITTLE_ENDIAN FOUR_DIMENSIONAL "Table"'
        tf.close
        expect { @tc.process_file(tf.path) }.to raise_error(ConfigParser::Error, /Invalid display type FOUR_DIMENSIONAL/)
        tf.unlink
      end

      it "complains about invalid endianness" do
        tf = Tempfile.new('unittest')
        tf.puts 'TABLE table MIDDLE_ENDIAN KEY_VALUE "Table"'
        tf.close
        expect { @tc.process_file(tf.path) }.to raise_error(ConfigParser::Error, /Invalid endianness MIDDLE_ENDIAN/)
        tf.unlink
      end

      it "processes table, endianness, type, description" do
        tf = Tempfile.new('unittest')
        tf.puts 'TABLE table LITTLE_ENDIAN KEY_VALUE "Table"'
        tf.close
        @tc.process_file(tf.path)
        tbl = @tc.table("TABLE")
        expect(tbl.table_name).to eql "TABLE"
        expect(tbl.default_endianness).to eql :LITTLE_ENDIAN
        expect(tbl.type).to eql :KEY_VALUE
        expect(tbl.description).to eql "Table"
        tf.unlink
      end

      it "complains if a table is redefined" do
        tf = Tempfile.new('unittest')
        tf.puts 'TABLE table LITTLE_ENDIAN KEY_VALUE "Packet 1"'
        tf.puts 'TABLE table LITTLE_ENDIAN KEY_VALUE "Packet 2"'
        tf.close
        @tc.process_file(tf.path)
        expect(@tc.warnings).to include("Table TABLE redefined.")
        tf.unlink
      end

    end # describe "process_file"
  end
end

