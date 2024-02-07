<img src="https://raw.githubusercontent.com/janbiedermann/up/master/up_logo.svg" alt="UP Logo">
<small>(Original Image by <a href="https://www.freepik.com/free-vector/colorful-arrows_715199.htm#query=up&position=3&from_view=search&track=sph&uuid=63f9eddf-02a6-4e5c-8178-8cfa507ee33d">Freepik</a>, modified though)</small>

# UP!

A high performance Rack server for [Opal Ruby](https://opalrb.com/) and [Matz Ruby](https://www.ruby-lang.org/), Tech Demo

## Let Numbers speak first

```
Response type:               env.to_s                    "hello_world"
                 Requests/Second   Latency       Requests/Second   Latency
Puma:              9478.41 req/s  14.05 ms        50822.38 req/s   2.62 ms
Unicorn:          12267.86 req/s  10.26 ms        16329.68 req/s   7.68 ms
Falcon:           13569.35 req/s   9.32 ms        24041.63 req/s   5.26 ms
Racer:            14640.34 req/s   8.90 ms        15354.14 req/s   8.44 ms
Agoo:             51455.38 req/s   2.43 ms        89022.91 req/s   1.51 ms
Iodine:           57257.21 req/s   2.18 ms <<<   132723.02 req/s   0.94 ms
Up! node:          2096.64 req/s* 59.97 ms*       25041.14 req/s   4.99 ms
Up! ruby:         10616.74 req/s  49.83 ms*       69388.90 req/s   1.49 ms
Up! uWS:           2511.65 req/s* 11.76 ms        83853.44 req/s   1.80 ms
Up! node cluster:  6627.05 req/s* 18.83 ms*       61320.38 req/s   2.04 ms
Up! ruby cluster: 29807.97 req/s   4.19 ms       137782.65 req/s   0.91 ms
Up! uWS cluster:   8328.87 req/s* 14.99 ms*      152865.96 req/s   0.82 ms <<<

<<< denotes the fastest for the response type          

running on/with:
Linux, Kernel 6.5.0-x
ruby 3.3.0, YJit enabled
Opal 2.0-dev with node v20.11.0
Puma 6.4.2, 4 workers, 4 threads
Falcon 0.43.0, 4 workers, 4 threads
Racer 0.1.3, defaults
Unicorn 6.1.0, 4 workers
Agoo 2.15.8, 4 workers, 4 threads
Iodine 0.7.57, 4 workers, 1 thread
Up! uWS 0.0.2, 1 worker
Up! Node 0.0.2, 1 worker
Up! Ruby 0.0.3, 1 worker
Up! uWS cluster 0.0.2, 4 workers
Up! Node cluster 0.0.2, 4 workers
Up! Ruby cluster 0.0.3, 4 workers

running the example_rack_app from this repo, benchmarked with:
bombardier http://localhost:3000/

on my old Intel(R) Core(TM) i5-6500 CPU @ 3.20GHz

* please see section "About the benchmarks ..." below
```

## Introduction

This is currently mainly a technical demonstration, demonstrating the speed of the [Opal Ruby](https://github.com/opal/opal) implementation employing [Node](https://nodejs.org/en) and [uWebSocketJs](https://github.com/uNetworking/uWebSockets.js) as runtime. Its not yet a generic, all purpose Rack server, but good for further experimentation, research and open for improvement. The included ruby version allows for verification of code correctness and performance. If it works with `bundle exec up_ruby` it should work equally well with the various Opal versions.

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

Available with `bundle exec` within the example apps or if this gem is included in your Gemfile:

- `up` - starts a single worker server using Opal with uWebSockets
- `up_cluster` - starts a cluster of workers using Opal with uWebSockets, fastest server
- `up_node` - starts a single worker server using Opal with the standard Node HTTP(S) classes
- `up_node_cluster` - starts a cluster of workers using Opal with the standard Node HTTP(S) classes, probably faster than `up_node`
- `up_bun` - starts single worker server using Bun, requires Opal bun support from [PR#2622](https://github.com/opal/opal/pull/2622)
- `up_ruby` - starts a single worker using Ruby with uWebSockets in a native extension, does not support the --secure option/TLS
- `up_ruby_cluster` - starts a cluster of workers using Ruby with uWebSockets in a native extension, does not support the --secure options/TLS

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

The "hello world" benchmark results above demonstrates the great potential of using Opal/Node with uWebSocketsJs on the server for executing ruby, however, the `envt.to_s` benchmark column next to it (results marked with *) also shows, that its still possible to trigger sweet spots in Opal, that can make things a bit slow. Work continues to improve things.

Link to bombardier, the tool used for benchmarking: [https://github.com/codesenberg/bombardier](https://github.com/codesenberg/bombardier)
