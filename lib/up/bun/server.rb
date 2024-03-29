# backtick_javascript: true
require 'logger'
require 'stringio'
require 'up/cli'
require 'up/client'

module Up
  class << self
    def publish(channel, message)
      raise 'no instance running' unless @instance
      @instance&.publish(channel, message)
    end
  end

  module Bun
    class Server
      def initialize(app:, host: 'localhost', port: 3000, scheme: 'http',
                     ca_file: nil, cert_file: nil, key_file: nil,
                     pid_file: nil,
                     logger: Logger.new(STDERR))
        @app = app
        @scheme    = scheme || 'http'
        raise "unsupported scheme #{@scheme}" unless %w[http https].include?(@scheme)
        @host      = host || 'localhost'
        @port      = port&.to_i || 3000
        @config    = { handler: self.class.name, engine: "bun/#{`process.version`}", port: port, scheme: scheme, host: host, logger: logger }.freeze
        @ca_file   = ca_file
        @cert_file = cert_file
        @key_file  = key_file
        @pid_file  = pid_file
        @default_input = StringIO.new('', 'r')
        @server    = nil
        @logger    = logger
      end

      %x{
        self.handle_headers = function(rack_headers, bun_hdr) {
          if (rack_headers.$$is_hash) {
            var header, v;
            for(header of rack_headers) {
              v = header[1];
              if (v.$$is_array) {
                v = v.join("\n");
              }
              bun_hdr.set(header[0].toLowerCase(), v);
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
        ::Up.instance_variable_set(:@instance, self)
        File.write(@pid_file, `process.pid.toString()`) if @pid_file
        puts "Server PID: #{`process.pid`}"
        %x{
          const oubs = Opal.Up.Bun.Server;
          const ouwc = Opal.Up.Client;
          const deco = new TextDecoder();
          var server_options = {
            port: #@port,
            hostname: #@host,
            development: false,
            async fetch(req, server) {
              const upgrade = req.headers.get('Upgrade');
              const env = new Map();
              env.set('rack.errors',#{STDERR});
              if (req.method === 'POST') {
                let body = await req.text();
                console.log('received: ', body);
                env.set('rack.input', #{StringIO.new(`body`)});
              } else {
                env.set('rack.input', #@default_input);
              }
              env.set('rack.logger', #@logger);
              if (upgrade) {
                env.set('rack.upgrade?', #{:websocket});
              }
              env.set('rack.url_scheme', #@scheme);
              env.set('SCRIPT_NAME', "");
              env.set('SERVER_PROTOCOL', req.httpVersion);
              env.set('HTTP_VERSION', req.httpVersion);
              env.set('SERVER_NAME', #@host);
              env.set('SERVER_PORT', #@port);
              env.set('QUERY_STRING', "");
              env.set('REQUEST_METHOD', req.method);
              env.set('PATH_INFO', req.url);
              req.headers.forEach((k, v) => { 
                let h = k.toUpperCase().replaceAll('-', '_');
                if (h[0] === 'C' && (h === 'CONTENT_TYPE || h === 'CONTENT_LENGTH')) {
                  env.set(h, v) ;
                } else {
                  env.set('HTTP_' + h, v) ;
                }
              });
              const rack_res = #@app.$call(env);
              if (upgrade) {
                const handler = env.get('rack.upgrade');
                if (rack_res[0] < 300 && handler && handler !== nil) {
                  const client = ouwc.$new();
                  client.env = env;
                  client.open = false;
                  client.handler = handler
                  client.protocol = #{:websocket};
                  client.server = server;
                  client.timeout = 120;
                  server.upgrade(req, { data: { client: client }});
                  return;
                }
              }
              const hdrs = new Headers();
              oubs.handle_headers(rack_res[1], hdrs);
              var body = '';
              body = oubs.handle_response(rack_res[2], body);
              return new Response(body, {status: rack_res[0], statusText: 'OK', headers: hdrs});
            },
            websocket: {
              close: (ws) => {
                const client = ws.data.client;
                if (typeof(client.handler.$on_close) === 'function') {
                  client.ws = ws;
                  client.open = false;
                  client.handler.$on_close(client);
                  client.ws = null;
                }
              },
              drain: (ws) => {
                const client = ws.data.client;
                if (typeof(client.handler.$on_drained) === 'function') {
                  client.ws = ws;
                  client.handler.$on_drained(client);
                  client.ws = null;
                }
              },
              message: (ws, message) => {
                const client = ws.data.client;
                if (typeof(client.handler.$on_message) === 'function') {
                  if (typeof(message) !== 'string') {
                    message = deco.decode(message);
                  }
                  client.ws = ws;
                  client.handler.$on_message(client, message);
                  client.ws = null;
                }
              },
              open: (ws) => {
                const client = ws.data.client;
                if (typeof(client.handler.$on_open) === 'function') {
                  client.ws = ws;
                  client.open = true;
                  client.handler.$on_open(client);
                  client.ws = null;
                }
              } 
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

      def publish(channel, message)
        %x{
          if (!message.$$is_string) {
            message = JSON.stringify(message);
          }
          #@server.publish(channel, message);
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
