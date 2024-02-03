# backtick_javascript: true
require 'up/cli'
require 'up/bun/rack_env'

module Up
  module Bun
    class Server
      def initialize(app:, host: 'localhost', port: 3000, scheme: 'http', ca_file: nil, cert_file: nil, key_file: nil)
        @app = app
        @scheme    = scheme || 'http'
        raise "unsupported scheme #{@scheme}" unless %w[http https].include?(@scheme)
        @host      = host || 'localhost'
        @port      = port&.to_i || 3000
        @config    = { handler: self.class.name, engine: "bun/#{`process.version`}", port: port, scheme: scheme, host: host }.freeze
        @ca_file   = ca_file
        @cert_file = cert_file
        @key_file  = key_file
        @server = nil
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
          const oubr = Opal.Up.Bun.RackEnv;
          const oubs = Opal.Up.Bun.Server;

          var server_options = {
            port: #@port,
            hostname: #@host,
            development: false,
            fetch(req) {
              const rack_res = #@app.$call(oubr.$new(req, #@config));
              const hdr = new Headers();
              oubs.handle_headers(rack_res[1]);
              var body = '';
              body = oubs.handle_response(rack_res[2], body);
              return new Response(body, {status: rack_res[0], statusText: 'OK', headers: hdr});
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
