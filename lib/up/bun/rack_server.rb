require 'up/bun/server'

module Up
  module Bun
    module RackServer
      def self.run(app, options = {})
        raise "already running" if @server
        @server = Up::Bun::Server.new(app: app, **options).listen
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
  ::Rackup::Handler.register('up', Up::Bun::RackServer) if defined?(::Rackup::Handler)
rescue StandardError
end
