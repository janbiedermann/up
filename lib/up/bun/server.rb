# backtick_javascript: true
require 'logger'
require 'up/cli'

module Up
  module Bun
    class Server
      def initialize(app:, host: 'localhost', port: 3000, scheme: 'http', ca_file: nil, cert_file: nil, key_file: nil, logger: Logger.new(STDERR))
        @app = app
        @scheme    = scheme || 'http'
        raise "unsupported scheme #{@scheme}" unless %w[http https].include?(@scheme)
        @host      = host || 'localhost'
        @port      = port&.to_i || 3000
        @config    = { handler: self.class.name, engine: "bun/#{`process.version`}", port: port, scheme: scheme, host: host, logger: logger }.freeze
        @ca_file   = ca_file
        @cert_file = cert_file
        @key_file  = key_file
        @default_input = IO.new
        @server    = nil
        @logger    = logger
        @t_factory = proc { |filename, _content_type| File.new(filename, 'a+') }
      end

      %x{
        self.handle_headers = function(rack_headers, bun_hdr) {
          if (rack_headers.$$is_hash) {
            var header, k, v;
            for(header of rack_headers) {
              k = header[0];
              if (!k.startsWith('rack.')) {
                v = header[1];
                if (v.$$is_array) {
                  v = v.join("\n");
                }
                bun_hdr.set(k, v);
              }
            }
          }
        }

        self.handle_response = function(parts, body) {
          if (parts["$respond_to?"]('each')) {
            // this is not technically correct, just to make things work
            #{`parts`.each { |part| `body = body + part` }}
          } else if (parts["$respond_to?"]('call')) {
            body = parts.$call();
          }
          #{`parts`.close if `parts`.respond_to?(:close)}
          return body;
        }
      }
      def listen
        raise "already running" if @server
        %x{
          const oubs = Opal.Up.Bun.Server;

          var server_options = {
            port: #@port,
            hostname: #@host,
            development: false,
            fetch(req) {
              const env = new Map();
              env.set('rack.errors',#{STDERR});
              env.set('rack.input', #@default_input);
              env.set('rack.logger', #@logger);
              env.set('rack.multipart.buffer_size', 4096);
              env.set('rack.multipart.tempfile_factory', #@t_factory);
              env.set('rack.url_scheme', #@scheme);
              env.set('SCRIPT_NAME', "");
              env.set('SERVER_PROTOCOL', req.httpVersion);
              env.set('HTTP_VERSION', req.httpVersion);
              env.set('SERVER_NAME', #@host);
              env.set('SERVER_PORT', #@port);
              env.set('QUERY_STRING', "");
              env.set('REQUEST_METHOD', req.method);
              env.set('PATH_INFO', req.url);
              var hdr, hds = req.headers;
              for (hdr in hds) { env.set('HTTP_' + hdr.toUpperCase().replaceAll('-', '_'), hds[hdr]); }
              const rack_res = #@app.$call(env);
              const hdrs = new Headers();
              oubs.handle_headers(rack_res[1], hdrs);
              var body = '';
              body = oubs.handle_response(rack_res[2], body);
              return new Response(body, {status: rack_res[0], statusText: 'OK', headers: hdrs});
            }
          };
          if (#@scheme === 'https') {
            server_options.tls = {
              key: Bun.file(#@key_file),
              cert: Bun.file(#@cert_file),
              ca: Bun.file(#@ca_file)
            };
          }
      
          #@server = Bun.serve(server_options);
          console.log(`Server is running on ${#@scheme}://${#@host}:${#@port}`);
        }
      end

      def stop
        if Up::CLI::stoppable?
          `#@server.stop()`
          @server = nil
        end
      end
    end
  end
end
