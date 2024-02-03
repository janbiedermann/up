require 'up/u_web_socket/cluster'

module Up
  module UWebSocket
    module RackCluster
      def self.run(app, options = {})
        raise "already running" if @server
        @server = Up::UWebSocket::Cluster.new(app: app, **options).listen
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
  ::Rackup::Handler.register('up', Up::UWebSocket::RackCluster) if defined?(::Rackup::Handler)
rescue StandardError
end
