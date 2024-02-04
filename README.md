<img src="https://raw.githubusercontent.com/janbiedermann/up/master/up_logo.svg" alt="UP Logo">
<small>Original Image by <a href="https://www.freepik.com/free-vector/colorful-arrows_715199.htm#query=up&position=3&from_view=search&track=sph&uuid=63f9eddf-02a6-4e5c-8178-8cfa507ee33d">Freepik</a>, modified though</small>

# UP!

A high performance Rack server for Opal Ruby, Tech Demo

## Let Numbers speak first

```
Requests per second:
Puma:      6391.01 req/s
Falcon:    8878.10 req/s
Unicorn:  14675.86 req/s
Iodine:   18645.58 req/s
Racer:    19321.63 req/s
Up! node:  3801.21 req/s
Up! uWS:  21070.34 req/s <<< fastest

Time per Request, mean, across all concurrent requests:
Puma:     0.156ms
Falcon:   0.113ms
Unicorn:  0.068ms
Iodine:   0.054ms
Racer:    0.052ms
Up! node: 0.275ms
Up! uWS:  0.047ms  <<< fastest

running on Linux with:
ruby 3.3.0, YJit enabled
Opal 1.8.2 with node v20.11.0
Puma 6.4.2, 4 workers, 4 threads
Falcon 0.43.0, 4 workers, 4 threads
Racer 0.1.3, defaults
Unicorn 6.1.0, 4 workers
Iodine 0.7.57, 4 workers, 4 threads
Up! uWS 0.0.2, 1 worker, no threads
Up! Node 0.0.2, 4 workers, no threads

running the example_rack_app from this repo, benchmarked with:
ab -n 100000 -c 10 http://localhost:3000/
```

## Introduction

This is currently mainly a technical demonstration, demonstrating the speed of the Opal Ruby implementation employing Node and UWebSocketJs as runtime. Its not yet a generic, all purpose Rack server, but good for further experimentation, research and open for improvement.

## Getting started

To start experimenting:
- clone this repo
- cd into it, bundle install
- cd example_rack_app
- bundle install
- bundle exec up

You may want to change the `gem 'opal-up'` line in the Gemfile to use up from rubygems, if you want to run your app outside of the cloned repo.

For a Gemfile available from rubygems:
`gem 'opal-up'`

## Available Commands

Available with `bundle exec` within the example apps or if this gem  is included in your Gemfile:

- `up` - starts a single worker server using uWebSockets, fastest server
- `up_cluster` - starts a cluster of workers using uWebSockets, still fast, depending on workload may be even faster than the single worker or not
- `up_node` - starts a single worker server using the standard Node HTTP(S) classes
- `up_node_cluster` - starts a cluster of workers using the standard Node HTTP(S) classes, probably faster than `up_node`
- `up_bun` - starts single worker server using Bun, requires Opal bun support from [PR#2622](https://github.com/opal/opal/pull/2622)

```
Usage: up [options]

    -h, --help                       Show this message
    -p, --port PORT                  Port number the server will listen to
    -b, --bind ADDRESS               Address the server will listen to
    -s, --secure                     Use secure sockets.
When using secure sockets, the -a, -c and -k options must be provided
    -a, --ca-file FILE               File with CA certs
    -c, --cert-file FILE             File with the servers certificate
    -k, --key-file FILE              File with the servers certificate
    -v, --version                    Show version

```

## Roda

A example apps for Roda is provided and _appears_ working with the following patches applied:

- [Changes required to make Roda _appear_ to work](https://github.com/jeremyevans/roda/compare/master...janbiedermann:roda:master)
- [Changes required to make Rack _appear_ to work](https://github.com/janbiedermann/rack/commit/1dadea0f9813c2df94715052d2277af13f7d0c0c)

Please note the phrase "_appear_ to work" in above sentences.
To try:
- clone Rack 3.0.9 and Roda 3.76
- apply the patch sets above
- set paths in the example_roda_app to point to your cloned rack & roda repos
- and up! the server

## Sinatra, others ...

... currently do not work! A example app for Sinatra is provided, for convenience of developing and expanding the capabilities of Opal.

- [Sinatra patches](https://github.com/sinatra/sinatra/compare/main...janbiedermann:sinatra:main)
- [Mustermann patches](https://github.com/sinatra/mustermann/compare/main...janbiedermann:mustermann:main)
- [Rack-Session patches](https://github.com/rack/rack-session/compare/main...janbiedermann:rack-session:main)
