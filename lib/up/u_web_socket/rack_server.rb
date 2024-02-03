require 'up/u_web_socket/server'

module Up
  module UWebSocket
    module RackServer
      def self.run(app, options = {})
        raise "already running" if @server
        @server = Up::UWebSocket::Server.new(app: app, **options).listen
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
  ::Rackup::Handler.register('up', Up::UWebSocket::RackServer) if defined?(::Rackup::Handler)
rescue StandardError
end
