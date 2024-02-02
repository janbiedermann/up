module Up
  module UwsRack
    def self.run(app, options = {})
      Up::UWebSocket.listen(app: app, port: options[:port], host: options[:host])
      true
    end

    def self.shutdown
      Up::UWebSocket.stop
    end
  end
end

ENV['RACK_HANDLER'] ||= 'up'

begin
  ::Rackup::Handler.register('up', Up::UwsRack) if defined?(::Rackup::Handler)
rescue StandardError
end
