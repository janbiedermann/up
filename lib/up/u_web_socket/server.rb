# backtick_javascript: true
require 'logger'
require 'stringio'
require 'up/cli'
require 'up/client'

%x{
  const process = require('node:process');
  module.paths.push(process.cwd() + '/node_modules');
  const uws = require('uWebSockets.js');
}

module Up
  class << self
    def publish(channel, message)
      raise 'no instance running' unless @instance
      @instance&.publish(channel, message)
    end
  end

  module UWebSocket
    class Server
      def initialize(app:, host: 'localhost', port: 3000, scheme: 'http', ca_file: nil, cert_file: nil, key_file: nil, logger: Logger.new(STDERR))
        @app = app
        @scheme    = scheme || 'http'
        raise "unsupported scheme #{@scheme}" unless %w[http https].include?(@scheme)
        @host      = host || 'localhost'
        @port      = port&.to_i || 3000
        @config    = { handler: self.class.name, engine: "node/#{`process.version`}" }.freeze
        @ca_file   = ca_file
        @cert_file = cert_file
        @key_file  = key_file
        @default_input = StringIO.new('', 'r')
        @server    = nil
        @logger    = logger
        @t_factory = proc { |filename, _content_type| File.new(filename, 'a+') }
      end

      %x{
        self.handle_headers = function(rack_headers, uws_res) {
          if (rack_headers.$$is_hash) {
            var header, v;
            for(header of rack_headers) {
              v = header[1];
              if (v.$$is_array) {
                v = v.join("\n");
              }
              uws_res.writeHeader(header[0].toLowerCase(), v);
            }
          }
        }

        self.handle_response = function(parts, uws_res) {
          if (parts["$respond_to?"]('each')) {
            #{`parts`.each { |part| `uws_res.write(part)` }}
          } else if (parts["$respond_to?"]('call')) {
            uws_res.write(parts.$call());
          }
          #{`parts`.close if `parts`.respond_to?(:close)}
        }

        self.prepare_env = function(req, ins) {
          const env = new Map();
          env.set('rack.errors',#{STDERR});
          env.set('rack.input', ins.default_input);
          env.set('rack.logger', ins.logger);
          env.set('rack.multipart.buffer_size', 4096);
          env.set('rack.multipart.tempfile_factory', ins.t_factory);
          env.set('rack.url_scheme', ins.scheme);
          env.set('SCRIPT_NAME', "");
          env.set('SERVER_PROTOCOL', 'HTTP/1.1');
          env.set('HTTP_VERSION', 'HTTP/1.1');
          env.set('SERVER_NAME', ins.host);
          env.set('SERVER_PORT', ins.port);
          env.set('QUERY_STRING', req.getQuery() || '');
          env.set('REQUEST_METHOD', req.getMethod().toUpperCase());
          env.set('PATH_INFO', req.getUrl());
          req.forEach((k, v) => { env.set('HTTP_' + k.toUpperCase().replaceAll('-', '_'), v) });
          return env;
        }
      }

      def listen
        raise "already running" if @server
        ::Up.instance_variable_set(:@instance, self)
        %x{
          const ouws = Opal.Up.UWebSocket.Server;
          const ouwc = Opal.Up.Client;
          const deco = new TextDecoder();
          if (#@scheme == 'https') {
            #@server = uws.SSLApp({ ca_file_name: #@ca_file, cert_file_name: #@cert_file, key_file_name: #@key_file });
          } else {
            #@server = uws.App();
          }
          #@server.post('/*', (res, req) => {
            const env = ouws.prepare_env(req, self);
            let buffer = Buffer.from('');
            res.onData((chunk, is_last) => {
              buffer = Buffer.concat([buffer, Buffer.from(chunk)]);
              if (is_last === true) {
                env.set('rack.input', #{StringIO.new(`buffer.toString()`)});
                const rack_res = #@app.$call(env);
                res.writeStatus(rack_res[0].toString() + ' OK');
                ouws.handle_headers(rack_res[1], res);
                ouws.handle_response(rack_res[2], res);
                res.end();
              }
            });
            res.onAborted(() => {});
          });
          #@server.any('/*', (res, req) => {
            const rack_res = #@app.$call(ouws.prepare_env(req, self));
            res.writeStatus(rack_res[0].toString() + ' OK');
            ouws.handle_headers(rack_res[1], res);
            ouws.handle_response(rack_res[2], res);
            res.end();
          });
          #@server.ws('/*', {
            close: (ws, code, message) => {
              const user_data = ws.getUserData();
              if (typeof(user_data.client.handler.$on_close) === 'function') {
                user_data.client.ws = ws;
                user_data.client.open = false;
                user_data.client.handler.$on_close(user_data.client);
                user_data.client.ws = null;
              }
            },
            drain: (ws) => {
              const user_data = ws.getUserData();
              if (typeof(user_data.client.handler.$on_drained) === 'function') {
                user_data.client.ws = ws;
                user_data.client.handler.$on_drained(user_data.client);
                user_data.client.ws = null;
              }
            },
            message: (ws, message, isBinary) => {
              const user_data = ws.getUserData();
              if (typeof(user_data.client.handler.$on_message) === 'function') {
                const msg = deco.decode(message);
                user_data.client.ws = ws;
                user_data.client.handler.$on_message(user_data.client, msg);
                user_data.client.ws = null;
              }
            },
            open: (ws) => {
              const user_data = ws.getUserData();
              if (typeof(user_data.client.handler.$on_open) === 'function') {
                user_data.client.ws = ws;
                user_data.client.open = true;
                user_data.client.handler.$on_open(user_data.client);
                user_data.client.ws = null;
              }
            },
            sendPingsAutomatically: true,
            upgrade: (res, req, context) => {
              const env = ouws.prepare_env(req, self);
              env.set('rack.upgrade?', #{:websocket});
              const rack_res = #@app.$call(env);
              const handler = env.get('rack.upgrade');
              if (rack_res[0] < 300 && handler && handler !== nil) {
                const client = ouwc.$new();
                client.env = env;
                client.open = false;
                client.handler = handler
                client.protocol = #{:websocket};
                client.server = #@server;
                client.timeout = 120;
                if (#@worker) {
                  client.worker = true;
                }
                res.upgrade({ client: client },
                  req.getHeader('sec-websocket-key'),
                  req.getHeader('sec-websocket-protocol'),
                  req.getHeader('sec-websocket-extensions'),
                  context);
              } else {
                if (rack_res[0] >= 300) {
                  env.delete('rack.upgrade');
                }
                res.writeStatus(rack_res[0].toString() + ' OK');
                ouws.handle_headers(rack_res[1], res);
                ouws.handle_response(rack_res[2], res);
                res.end();
              }
            },

          });
          #@server.listen(#@port, #@host, () => { console.log(`Server is running on ${#@scheme}://${#@host}:${#@port}`)});
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
          `#@server.close()`
          @server = nil
        end
      end
    end
  end
end
