# backtick_javascript: true
require 'etc'
require 'random/formatter'
require 'up_ext'

module Up
  module Ruby
    class Cluster < Up::Ruby::Server
      def initialize(app:, host: 'localhost', port: 3000, scheme: 'http', ca_file: nil, cert_file: nil, key_file: nil, logger: Logger.new(STDERR), workers: nil)
        super(app: app, host: host, port: port)
        @secret = Random.uuid
        @workers = workers || Etc.nprocessors
        @members = []
      end

      def listen
        raise "already running" unless @members.empty?
        @workers.times do
          @members << fork do
            @member_id = @members.size + 1
            super
          end
        end

        Process.waitall
        @members.each do |member|
          Process.kill("KILL", member)
        end
      end

      def stop
        if Up::CLI::stoppable?
          @members.each { |m| Process.kill(m) } 
          @members.clear
        end
      end
    end
  end
end
