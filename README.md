<img src="https://raw.githubusercontent.com/janbiedermann/up/master/up_logo.svg" alt="UP Logo">
<small>(Original Image by <a href="https://www.freepik.com/free-vector/colorful-arrows_715199.htm#query=up&position=3&from_view=search&track=sph&uuid=63f9eddf-02a6-4e5c-8178-8cfa507ee33d">Freepik</a>, modified though)</small>

# UP!

A high performance Rack server for [Opal Ruby](https://github.com/opal/opal), Tech Demo

## Let Numbers speak first

```
Response type*:         env.to_s       "hello_world"
Requests/Second:
Puma:              9478.41 req/s      50822.38 req/s
Unicorn:          12267.86 req/s      16329.68 req/s
Falcon:           13569.35 req/s      24041.63 req/s
Racer:            14640.34 req/s      15354.14 req/s
Agoo:             51455.38 req/s      89022.91 req/s
Iodine:           57257.21 req/s <<< 132723.02 req/s
Up! node:          2096.64 req/s      25041.14 req/s
Up! uWS:           2511.65 req/s      83853.44 req/s
Up! node cluster:  6627.05 req/s      61320.38 req/s
Up! uWS cluster:   8328.87 req/s     152865.96 req/s <<< fastest

Latency:
Puma:                14.05 ms             2.62 ms
Unicorn:             10.26 ms             7.68 ms
Falcon:               9.32 ms             5.26 ms
Racer:                8.90 ms             8.44 ms
Agoo:                 2.43 ms             1.51 ms
Iodine:               2.18 ms <<<         0.94 ms
Up! node:            59.97 ms             4.99 ms
Up! uWS:             49.83 ms             1.49 ms
Up! node cluster:    18.83 ms             2.04 ms
Up! uWS cluster:     14.99 ms             0.82 ms <<< fastest

running on Linux with:
ruby 3.3.0, YJit enabled
Opal 2.0-dev with node v20.11.0
Puma 6.4.2, 4 workers, 4 threads
Falcon 0.43.0, 4 workers, 4 threads
Racer 0.1.3, defaults
Unicorn 6.1.0, 4 workers
Agoo 2.15.8, 4 workers, 4 threads
Iodine 0.7.57, 4 workers, 1 thread
Up! uWS 0.0.2, 1 worker
Up! Node 0.0.2, 4 workers
Up! uWS cluster 0.0.2, 4 workers
Up! Node cluster 0.0.2, 4 workers

running the example_rack_app from this repo, benchmarked with:
bombardier http://localhost:3000/

on my old Intel(R) Core(TM) i5-6500 CPU @ 3.20GHz

* env.to_s is the original benchmark, unfortunately triggering a sweet spot in Opal.
  Thats why i benchmarked in addition with a static string "hello world",
  to demonstrate the potential.
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

A example app for Roda is provided and _appears_ working with the following patches applied:

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

## About the benchmarks and Opal/Up! performance

The "hello world" benchmark result demonstrates the great potential of using Opal/Node with uWebSocketsJs on the server for executing ruby, however, the `envt.to_s` benchmark column next to it also shows, that its still possible to trigger sweet spots in Opal, that can make things a bit slow. Work continues to improve things.

Link to bombardier, the tool used for benchmarking: [https://github.com/codesenberg/bombardier](https://github.com/codesenberg/bombardier)
