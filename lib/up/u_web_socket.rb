# backtick_javascript: true

%x{
  module.paths.push(process.cwd() + '/node_modules');
  const uws = require('uWebSockets.js');
  const cluster = require('node:cluster');
}

require 'up/uws_rack_env'

module Up
  module UWebSocket
    def self.listen(app:, host: 'localhost', port: 3000, scheme: 'http', ca_file: nil, cert_file: nil, key_file: nil)
      port = port&.to_i
      scheme ||= 'http'
      host   ||= 'localhost'
      port   ||=  3000
      config = { handler: self.name, engine: "node/#{`process.version`}", port: port, scheme: scheme, host: host }
      %x{
        let server;
        if (scheme == 'http') {
          server = uws.App();
        } else if (scheme == 'https') {
          server = uws.SSLApp({ ca_file_name: ca_file, cert_file_name: cert_file, key_file_name: key_file });
        } else {
          #{raise "unsupported scheme #{scheme}"}
        }
        server.get('/*', (res, req) => {
          const rack_res = app.$call(Opal.Up.UwsRackEnv.$new(req, config));
          res.writeStatus(`${rack_res[0].toString()} OK`);
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
                res.writeHeader(k, v);
              }
            }
          }
          #{
            parts = `rack_res[2]`
            if parts.respond_to?(:each)
              parts.each do |part|
                `res.write(part)`
              end
            elsif parts.respond_to?(:call)
              `res.write(parts.$call())`
            end
            parts.close if parts.respond_to?(:close)
          }
          res.end();
        });
        server.listen(port, host, () => { console.log(`Server is running on http://${host}:${port}`)});
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
