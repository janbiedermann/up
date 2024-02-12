module WSConnection
  class << self
    def on_open(client)
      puts "WebSocket connection established (#{client.object_id})."
      client.subscribe(:a_channel)
    end
    def on_message(client, data)
      client.write data # echo the data back
      client.publish(:a_channel, "sent to a_channel: #{data} from #{Process.pid}") # and send it to a_channel
      puts "on_drained MUST be implemented if #{ client.pending } != 0."
    end
    def on_drained(client)
      puts "If this line prints out, on_drained is supported by the server."
    end
    def on_shutdown(client)
      client.write "The server is going away. Goodbye."
    end
    def on_close(client)
      puts "WebSocket connection closed (#{client.object_id})."
    end
  end
end

class RackApp
  def self.call(env)
    if (env['rack.upgrade?'] == :websocket)
      env['rack.upgrade'] = WSConnection
      return [0, {}, []]
    end
    body = %Q(
      <head>
      <title>Websockets</title>
      <script>
        let ws= new WebSocket("ws://" + window.location.host);
        ws.addEventListener("message", (event) => {
          document.querySelector("#receiver").innerHTML = event.data;
        })
        let i = 0;
        function send_message() {
          i++;
          ws.send("Hello World, message number " + i);
        }
      </script>
      </head>
      <body>
      <div id="receiver">Please click the "Send" button</div>
      <button onclick="send_message()">Send</button>
      </body>
    )
    [200, {"Content-Type" => "text/html"}, [body]]
  end
end
