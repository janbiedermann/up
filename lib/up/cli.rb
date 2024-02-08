require 'optparse'
require 'up/version'

module Up
  module CLI
    class Options < OptionParser
      attr_reader :options
      def initialize
        super
        @options = {}
        self.banner = 'Usage: up [options]'
        separator ''
        on('-h', '--help', 'Show this message') do
          puts self
          exit
        end
        on('-p', '--port PORT', String, 'Port number the server will listen to') do |port|
          options[:port] = port.to_i
        end
        on('-b', '--bind ADDRESS', String, 'Address the server will listen to') do |host|
          options[:host] = host
        end
        on('-s', '--secure', "Use secure sockets.\nWhen using secure sockets, the -a, -c and -k options must be provided") do
          options[:scheme] = 'https'
        end
        on('-a', '--ca-file FILE', String, 'File with CA certs') do |ca_file|
          options[:ca_file] = ca_file
        end
        on('-c', '--cert-file FILE', String, 'File with the servers certificate') do |cert_file|
          options[:cert_file] = cert_file
        end
        on('-k', '--key-file FILE', String, 'File with the servers certificate') do |key_file|
          options[:key_file] = key_file
        end
        on('-l', '--log-file FILE', String, 'log file') do |log_file|
          options[:logger] = Logger.new(File.new(log_file, 'a+'))
        end
        on('-v', '--version', 'Show version') do
          puts "Up! v#{Up::VERSION}"
          exit
        end
      end

      def parse!
        super
        if options[:scheme] == 'https'
          if !options[:ca_file] || !options[:cert_file] || !options[:key_file]
            puts "When using -s or --secure the -a,-c- and -k options must be given too!"
            exit 2
          end
        end
      end
    end

    class << self
      if RUBY_ENGINE != 'opal'
        def setup_bun
          bun_cmd = `which bun`
          if !bun_cmd || bun_cmd.empty?
            puts "Please install bun first!"
            exit 2
          end
          true
        end
          
        def setup_node
          node_cmd = `which node`
          if !node_cmd || node_cmd.empty?
            puts "Please install node first!"
            exit 2
          end
          true
        end

        def setup_u_web_socket
          setup_node
          npm_cmd = `which npm`
          if !npm_cmd || npm_cmd.empty?
            puts "Please install npm first!"
            exit 2
          end
          npm_cmd.chop! if npm_cmd.end_with?("\n")
          have_uws = `npm list|grep uWebSockets.js@20`
          `npm i uNetworking/uWebSockets.js#v20.41.0` if have_uws.empty?
          true
        end
      end

      def get_options
        options = Up::CLI::Options.new
        options.parse!
        options.options
      rescue OptionParser::InvalidOption => e
        $stderr.puts "#{$0}: #{e.message} (-h will show valid options)"
        exit 64
      end

      def get_gems_for_cmd
        # Opal does not yet support gems, so lets read the Gemfile and simply add each gem
        # to the Opal load path and require it, works for some gems, fails for others
        gems = ""
        if File.exist?("Gemfile")
          lines = File.readlines('Gemfile')
          lines.each do |line|
            m = /gem ['"](\w+)['"]/.match(line)
            gems << " -g #{m[1]} -r #{m[1]}" if m && m[1] != 'opal-up'
          end
        end
        gems
      end

      def try_file(filename)
        return nil unless File.exist? filename
        ::Rack::Builder.parse_file filename
      end

      def get_app(filename = 'config.ru')
        app = nil
        filename ||= 'config.ru'
        app = try_file(filename)
        unless app
          filename = "#{filename}.ru"
          app = try_file(filename)
        end
        raise "Something wrong with #{filename}\n" unless app
        app
      end

      def stoppable?
        sleep 0.1
        puts 'deflating request chain links'
        sleep 0.1
        puts 'optimizing response distortion'
        sleep 0.1
        print 'releasing boost pressure: '
        3.times do
          sleep 0.2
          print '.'
        end
        3.times do 
          puts "\n\033[5;31;47mRED ALERT: boost pressure to high, cannot open release valve!1!!!\033[0m"
          sleep 0.1
          print '.'
          sleep 0.1
        end
        puts 'stopping engines failed, for further help see:'
        puts 'https://www.youtube.com/watch?v=ecBco63zvas'
        sleep 0.2
        puts "Just kidding :)"
        true
      end
    end
  end
end
