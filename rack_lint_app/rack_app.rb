class RackApp
  def self.call(env)
    #
    [200, {}, ["hello world"]]
    # [200, { 'content-type' => 'text/plain' }, [env.to_s]]
  end
end
