module Up
  module BunRack
    def self.run(app, options = {})
      Up::Bun.listen(app: app, port: options[:port], host: options[:host])
      true
    end

    def self.shutdown
      Up::Bun.stop
    end
  end
end

ENV['RACK_HANDLER'] ||= 'up'

begin
  ::Rackup::Handler.register('up', Up::BunRack) if defined?(::Rackup::Handler)
rescue StandardError
end
