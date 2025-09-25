class RackApp
  class << self
    def call(env)
      case env['PATH_INFO']
      when '/' then  [200, {}, [root(env)]]
      when '/huhu' then [200, {}, [huhu]]
      else
        [404, {}, [not_found]]
      end

      # These are for benchmarking:

      # [200, {}, ["hello world"]]

      # [200, { 'content-type' => 'text/plain' }, [env.to_s]]

    end

    def root(env)
      <<-HTML
      <head>
      <title>hello root</title>
      </head>
      <body>
      <h1>Hello</h1>
      <p>Welcome! Visit this <a href="/huhu">page</a>.</p>
      <p>Or visit the <a href="/nonexisting">void</a>.</p>
      <p>This request is using the #{env['REQUEST_METHOD']} method.</p>
      </body>
      </html>
      HTML
    end

    def huhu
      <<-HTML
      <head>
      <title>huhu</title>
      </head>
      <body>
      <h1>Huhu</h1>
      <p>Welcome, go back to the <a href="/">root</a></p>
      </body>
      </html>
      HTML
    end

    def not_found
      <<-HTML
      <head>
      <title>The void</title>
      </head>
      <body>
      <h1>Not found</h1>
      <p>whatever you are looking for, its not here. Here is nothing. Its the void.</p>
      <p>Go to the <a href="/">root</a> instead.</p>
      </body>
      </html>
      HTML
    end
  end
end
