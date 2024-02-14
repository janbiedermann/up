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
        unless @member_id
          install_signal_handlers
          Process.waitall
        end
      end

      def stop
        if Up::CLI::stoppable?
          kill_members
        end
      end

      private

      def install_signal_handlers
        Signal.trap('CHLD') do
          warn "\nError: a cluster member died!"
          kill_members
        end
        Signal.trap('INT') do
          warn "\nReceived CTRL-C!"
          kill_members
        end
      end

      def kill_members
        Signal.trap('CHLD', 'IGNORE')
        STDERR.print "Stopping workers: "
        @members.each do |mid|
          Process.kill('INT', mid) rescue nil
          STDERR.print '.'
        end
        @members.clear
        warn "\nCluster stopped."
        Signal.trap('CHLD', 'DEFAULT')
      end
    end
  end
end
