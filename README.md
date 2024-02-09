<img src="https://raw.githubusercontent.com/janbiedermann/up/master/up_logo.svg" alt="UP Logo">
<small>(Original Image by <a href="https://www.freepik.com/free-vector/colorful-arrows_715199.htm#query=up&position=3&from_view=search&track=sph&uuid=63f9eddf-02a6-4e5c-8178-8cfa507ee33d">Freepik</a>, modified though)</small>

# UP!

A high performance Rack server for [Opal Ruby](https://opalrb.com/) and [Matz Ruby](https://www.ruby-lang.org/), Tech Demo

## Let Numbers speak first

```
Response type:               env.to_s                    "hello_world"
                 Requests/Second   Latency       Requests/Second   Latency
Puma:              8884.53 req/s  15.18 ms        50822.38 req/s   2.62 ms
Unicorn:          12302.35 req/s  10.22 ms        16329.68 req/s   7.68 ms
Falcon:           13168.82 req/s   9.49 ms        24041.63 req/s   5.26 ms
Racer:            14536.88 req/s   8.94 ms        15354.14 req/s   8.44 ms
Agoo:             49078.57 req/s   2.54 ms        89022.91 req/s   1.51 ms
Iodine:           59116.53 req/s   2.11 ms <<<   134267.79 req/s   0.93 ms
Up! node:          5089.40 req/s  24.53 ms        24398.51 req/s   5.12 ms
Up! ruby:         22144.33 req/s   5.64 ms        58704.09 req/s   2.14 ms
Up! uWS:           6540.62 req/s  19.09 ms        78384.93 req/s   1.59 ms
Up! node cluster: 16218.80 req/s   7.70 ms        61381.99 req/s   2.03 ms
Up! ruby cluster: 53641.29 req/s   2.35 ms       130492.13 req/s   0.96 ms
Up! uWS cluster:  20143.62 req/s   6.20 ms       148534.58 req/s   0.84 ms <<<

<<< denotes the fastest for the response type

running on/with:
Linux, Kernel 6.5.0-x
ruby 3.3.0, YJit enabled
Opal 2.0-dev as of 9. Feb 2024, with node v20.11.0
Puma 6.4.2, 4 workers, 4 threads
Falcon 0.43.0, 4 workers, 4 threads
Racer 0.1.3, defaults
Unicorn 6.1.0, 4 workers
Agoo 2.15.8, 4 workers, 4 threads
Iodine 0.7.57, 4 workers, 1 thread
Up! uWS 0.0.4, 1 worker
Up! Node 0.0.4, 1 worker
Up! Ruby 0.0.4, 1 worker
Up! uWS cluster 0.0.4, 4 workers
Up! Node cluster 0.0.4, 4 workers
Up! Ruby cluster 0.0.4, 4 workers

running the example_rack_app from this repo, benchmarked with:
bombardier http://localhost:3000/
and taking the Avg

on a Intel(R) Core(TM) i5-6500 CPU @ 3.20GHz
```

## Introduction

This is currently mainly a technical demonstration, demonstrating the speed of the [Opal Ruby](https://github.com/opal/opal) implementation employing [Node](https://nodejs.org/en) and [uWebSocketJs](https://github.com/uNetworking/uWebSockets.js) as runtime. Its not yet a generic, all purpose Rack server, but good for further experimentation, research and open for improvement. The included ruby version allows for verification of code correctness and performance. If it works with `bundle exec up_ruby` it should work equally well with the various Opal versions, at least thats the future goal.

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
## Supported Features

Up! implements the [Rack Spec as of Rack 3.0](https://github.com/rack/rack/blob/main/SPEC.rdoc) with the following differences:
- `rack.hijack` is not implemented, but `rack.upgrade` instead is, see below
- `rack.input` is currently still missing
- Tempfile support is currently incomplete, affecting a few keys in the Rack Env ('tempfile' missing in Opal).
- Some Rack modules/classes still have issues when run in Opal and may not work as expected

For Up! uWS running in Opal:
Websockets are supported following [the Iodine 'rack.upgrade' Draft](https://github.com/boazsegev/iodine/blob/master/SPEC-WebSocket-Draft.md)
A example RackApp using WebSockets is provided in the 'example_rack_ws_app' directory

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

## About the Benchmarks

The benchmarks mainly test the overhead introduced by the rack server. 

In the 'env.to_s' benchmark, the Rack environment access and response header handling overhead are measured. Simply calling env.to_s accesses all keys and serializes them briefly. If the Rack app accesses the keys of the Rack environment and sets response headers, the overhead/latency as measured can be expected, or that amount of requests per second can be expected at most.

The "hello_world" benchmark measures the overhead for the simplest possible version of a meaningful Rack response and should provide maximum performance. If the Rack app just replies with a string, that overhead/latency can be expected, or that amount of requests per second can be expected at most.

## Links

- bombardier, the tool used for benchmarking: [https://github.com/codesenberg/bombardier](https://github.com/codesenberg/bombardier)

### Rack Servers

- [Agoo](https://github.com/ohler55/agoo)
- [Falcon](https://github.com/socketry/falcon)
- [Iodine](https://github.com/boazsegev/iodine)
- [Puma](https://github.com/puma/puma)
- [Racer](https://rubygems.org/gems/racer) (a bit old, but included here, because it uses libuv, just like Node)
- [Unicorn](https://yhbt.net/unicorn/)
