require 'up/ruby/rack_env'
require 'up_ext'

module Up
  module Ruby
    module RackServer
      def self.run(app, options = {})
        raise "already running" if @server
        @server = Up::Ruby::Server.new(app: app, **options).listen
        true
      end

      def self.shutdown
        @server&.stop
        @server = nil
      end
    end
  end
end

ENV['RACK_HANDLER'] ||= 'up'

begin
  ::Rackup::Handler.register('up', Up::Ruby::RackServer) if defined?(::Rackup::Handler)
rescue StandardError
end
