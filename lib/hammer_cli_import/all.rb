#
# Copyright (c) 2014 Red Hat Inc.
#
# This file is part of hammer-cli-import.
#
# hammer-cli-import is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# hammer-cli-import is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with hammer-cli-import.  If not, see <http://www.gnu.org/licenses/>.
#

require 'hammer_cli'
require 'hammer_cli_import'

module HammerCLIImport
  class ImportCommand
    class AllCommand < HammerCLI::AbstractCommand
      command_name 'all'
      desc 'Load ALL data from a specified directory that is in spacewalk-export format.'

      option ['--directory'], 'DIR_PATH', 'stargate-export directory', :default => '/tmp/exports'
      option ['--entities'], 'entity[,entity...]', 'Import specific entities', :default => 'all'
      option ['--list-entities'], :flag, 'List entities we understand', :default => false
      option ['--into-org-id'], 'ORG_ID', 'Import all organizations into one specified by id'
      option ['--merge-users'], :flag, 'Merge pre-created users (except admin)', :default => false
      option ['--dry-run'], :flag, 'Show what we would have done, if we\'d been allowed', :default => false

      # An ordered-list of the entities we know how to import
      class << self; attr_accessor :entity_order end
      @entity_order = %w(organization user host-collection repository-enable repository
                         content-view activation-key template-snippet)

      #
      # A list of what we know how to do.
      # The map has entries of
      #   import-entity => {sat5-export-name, import-classname, entities-we-are-dependent-on, should-import}
      # The code will look for classes HammerCLIImport::ImportCommand::<import-classname>
      # It will look in ~/exports/<Sat5-export-name>.csv for data
      #
      class << self; attr_accessor :known end
      @known = {
        'activation-key' =>
                    {'export-file' => 'activation-keys',
                     'import-class' => 'ActivationKeyImportCommand',
                     'depends-on' => 'organization',
                     'import' => false },
        'content-view' =>
                    {'export-file' => 'CHANNELS/export',
                     'import-class' => 'LocalRepositoryImportCommand',
                     'depends-on' => 'repository',
                     'import' => false },
        'repository' =>
                    {'export-file' => 'repositories',
                     'import-class' => 'RepositoryImportCommand',
                     'depends-on' => 'organization',
                     'import' => false },
        'host-collection' =>
                    {'export-file' => 'system-groups',
                     'import-class' => 'SystemGroupImportCommand',
                     'depends-on' => 'organization',
                     'import' => false },
        'organization' =>
                    {'export-file' => 'users',
                     'import-class' => 'OrganizationImportCommand',
                     'depends-on' => '',
                     'import' => false },
        'repository-enable' =>
                    {'export-file' => 'channels',
                     'import-class' => 'RepositoryEnableCommand',
                     'depends-on' => 'organization',
                     'import' => false },
        'template-snippet' =>
                    {'export-file' => 'kickstart-scripts',
                     'import-class' => 'TemplateSnippetImportCommand',
                     'import' => false },
        'user' =>
                    {'export-file' => 'users',
                     'import-class' => 'UserImportCommand',
                     'depends-on' => 'organization',
                     'import' => false }
      }

      def do_list
        puts 'Entities I understand:'
        AllCommand.entity_order.each do |an_entity|
          puts "  #{an_entity}"
        end
      end

      # What are we being asked to import?
      # Marks what we asked for, and whatever those things are dependent on, to import
      def set_import_targets
        to_import = option_entities.split(',')
        AllCommand.known.each_key do |key|
          AllCommand.known[key]['import'] = (to_import.include?(key) || to_import.include?('all'))
          next if AllCommand.known[key]['depends-on'].nil?

          depends_on = AllCommand.known[key]['depends-on'].split(',')
          depends_on.each do |entity_name|
            AllCommand.known[entity_name]['import'] = true
          end
        end
      end

      # Some subcommands have their own special args
      # This is the function that will know them all
      #
      # 'user' needs --new-passwords and may need --merge-users
      # 'organization' may need --into-org-id
      # 'content-view needs --dir, and knows its own --csv-file in that dir
      #
      # TODO: add existence-check and throw if file doesn't exist
      def build_args(key, filename)
        args = ['--csv-file', filename]
        case key
        when 'organization'
          args << '--into-org-id' << option_into_org_id unless option_into_org_id.nil?
        when 'content-view'
          args = ['--csv-file', "#{option_directory}/CHANNELS/export.csv"]
          args << '--dir' << "#{option_directory}/CHANNELS"
        when 'user'
          pwd_filename = "passwords_#{Time.now.utc.iso8601}.csv"
          args << '--new-passwords' << pwd_filename
          args << '--merge-users' if option_merge_users?
        end
        return args
      end

      # Do the import(s)
      def import_from
        AllCommand.entity_order.each do |key|
          a_map = AllCommand.known[key]

          if a_map['import']
            import_file = "#{option_directory}/#{a_map['export-file']}.csv"
            # TODO: catch thrown error and skip with message
            args = build_args(key, import_file)
            puts format('Import %-20s using %s', key, args.join(' '))
            if File.exist? import_file

              #############################################################
              # MAGIC! We create a class from the class-name-string here! #
              #############################################################
              import_class = HammerCLIImport::ImportCommand.const_get(a_map['import-class'])
              unless option_dry_run?
                import_class.new(args).run(args)
              end
            else
              puts "...SKIPPING, no file #{import_file} available."
            end
          end
        end
      end

      def execute
        if option_list_entities?
          do_list
        else
          set_import_targets
          import_from
        end
        HammerCLI::EX_OK
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
