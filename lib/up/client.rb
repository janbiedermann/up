# backtick_javascript: true

module Up
  class Client
    # instance vars are set by the server

    attr_reader :handler, :protocol, :timeout

    def env
      @env
    end

    def handler=(h)
      @handler.on_close(self)
      @handler = h
      @handler.on_open(self)
    end

    def open?
      @open
    end

    def pubsub?
      false
    end

    if RUBY_ENGINE == 'opal'
      def close
        @open = false
        `#@ws?.close()`
      end

      def pending
        `#@ws?.getBufferedAmount()`
      end

      def write(data)
        `#@ws?.send(data, false)`
      end
    end
  end
end
