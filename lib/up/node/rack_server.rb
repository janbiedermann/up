require 'up/node/server'

module Up
  module Node
    module RackServer
      def self.run(app, options = {})
        raise "already running" if @server
        @server = Up::Node::Server.new(app: app, **options).listen
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
  ::Rackup::Handler.register('up', Up::Node::RackServer) if defined?(::Rackup::Handler)
rescue StandardError
end
