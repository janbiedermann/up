# backtick_javascript: true

require 'up/bun_rack_env'

module Up
  module Bun
    def self.listen(app:, host: 'localhost', port: 3000, scheme: 'http', ca_file: nil, cert_file: nil, key_file: nil)
      port = port&.to_i
      scheme ||= 'http'
      host   ||= 'localhost'
      port   ||=  3000
      config = { handler: self.name, engine: "bun/#{`process.version`}", port: port, scheme: scheme, host: host }
      %x{
        if (scheme !== 'http' && scheme !== 'https') {
          #{raise "unsupported scheme #{scheme}"}
        }

        var server_options = {
          port: port,
          hostname: host,
          development: false,
          fetch(req) {
            const rack_res = app.$call(Opal.Up.BunRackEnv.$new(req, config));
            const hdr = new Headers();
            const headers = rack_res[1];
            if (headers.$$is_hash) {
              var header, k, v;
              for(header of headers) {
                k = header[0];
                v = header[1];
                if (!k.startsWith('rack.')) {
                  if (v.$$is_array) {
                    v = v.join("\n");
                  }
                  hdr.set(k, v);
                }
              }
            }
            var body = '';

            #{
              parts = `rack_res[2]`
              if parts.respond_to?(:each)
                parts.each do |part|
                  # this is not technically correct, just to make htings work
                  `body = body + part`
                end
              elsif parts.respond_to?(:call)
                `body = parts.$call()`
              end
              parts.close if parts.respond_to?(:close)
            }

            return new Response(body, {status: rack_res[0], statusText: 'OK', headers: hdr});
          }
        };
        if (scheme === 'https') {
          server_options.tls = {
            key: Bun.file(key_file),
            cert: Bun.file(cert_file),
            ca: Bun.file(ca_file)
          };
        }
    
        Bun.serve(server_options);
        console.log(`Server is running on http://${host}:${port}`);
      }
    end

    def self.stop
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
        puts "\nRED ALERT: boost pressure to high, cannot open release valve!1!!!"
        sleep 0.1
        print '.'
        sleep 0.1
      end
      puts 'stopping engines failed, for further help see:'
      puts 'https://www.youtube.com/watch?v=ecBco63zvas'
    end
  end
end
