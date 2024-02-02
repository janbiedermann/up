require 'opal/platform'
require 'nodejs/file'
require 'nodejs/require'
require 'opal-parser'
require 'rack/builder'
require 'up/rack_builder_patch'

module Up
  module CLI
    def self.try_file(filename)
      return nil unless File.exist? filename
      ::Rack::Builder.parse_file filename
    end

    def self.get_app(filename = 'config.ru')
      app = nil
      filename ||= 'config.ru'
      app = try_file filename
      if File.exist?("#{filename}.ru")
        filename = "#{filename}.ru"
        app ||= try_file filename
      end
      raise "Something wrong with #{filename}\n" unless app
      app
    end

    def self.call
      app = get_app
      Up::UwsRack.run(app)
    end
  end
end
