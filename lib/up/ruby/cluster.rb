# backtick_javascript: true
require 'etc'
require 'random/formatter'
require 'socket'
require 'up_ext'

module Up
  module Ruby
    class Cluster < Up::Ruby::Server
      def initialize(app:, host: 'localhost', port: 3000, scheme: 'http',
                     ca_file: nil, cert_file: nil, key_file: nil,
                     pid_file: nil,
                     logger: Logger.new(STDERR), workers: nil)
        super(app: app, host: host, port: port)
        @pid_file = pid_file
        @secret = Random.uuid
        @workers = workers || Etc.nprocessors
        @members = []
        @localhost_addr = TCPSocket.getaddress('localhost')
      end

      def listen
        raise "already running" unless @members.empty?
        ::Up.instance_variable_set(:@instance, self)
        @workers.times do
          @members << fork do
            @member_id = @members.size + 1
            super
            exit
          end
        end
        unless @member_id
          File.write(@pid_file, Process.pid.to_s) if @pid_file
          puts "Server PID: #{Process.pid}"
          install_signal_handlers
          Process.waitall
        end
      end

      def stop
        if Up::CLI::stoppable?
          kill_members
          super
        end
      end

      private

      def install_signal_handlers
        Signal.trap('CHLD') do
          unless members_alive?
            warn "\nError: a cluster worker died!"
            kill_members
          end
        end
        Signal.trap('INT') do
          warn "\nReceived CTRL-C!"
          kill_members
        end
        Signal.trap('TERM') do
          warn "\nReceived TERM signal!"
          kill_members
        end
      end

      def kill_members
        Signal.trap('CHLD', 'IGNORE')
        STDERR.print "Stopping all workers: "
        @members.each do |mid|
          Process.kill('INT', mid) rescue nil
          STDERR.print '.'
        end
        Signal.trap('CHLD', 'DEFAULT')
        @members.clear
        warn "\nCluster stopped."
      end

      def members_alive?
        @workers.times do |i|
          TCPSocket.new(@localhost_addr , @port + i + 1).close
        end
        true
      rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL
        false
      end
    end
  end
end
