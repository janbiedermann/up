<img src="https://raw.githubusercontent.com/janbiedermann/up/master/up_logo.svg" alt="UP Logo">
<small>(Original Image by <a href="https://www.freepik.com/free-vector/colorful-arrows_715199.htm#query=up&position=3&from_view=search&track=sph&uuid=63f9eddf-02a6-4e5c-8178-8cfa507ee33d">Freepik</a>, modified though)</small>

# UP!

A high performance Rack server for [Opal Ruby](https://opalrb.com/) and [Matz Ruby](https://www.ruby-lang.org/), Tech Demo

## Let Numbers speak first

```
| Response type | env.to_s     | env.to_s   | "hello_world" | "hello_world" |
|---------------|--------------|------------|---------------|---------------|
|               | requests/sec | latency ms | requests/sec  | latency ms    |
| Falcon        |     42350.34 |       2.95 |      68092.27 |          1.83 |
| Iodine        |     69212.39 |       1.80 |     219665.14 |          0.57 |
| Itsi          | +2+ 75158.16 |       1.66 |     109310.00 |          1.14 |
| Puma          |     12397.22 |      10.08 |      55328.63 |          2.26 |
| Up! ruby      | +1+ 77760.68 |       1.60 | +1+ 268618.38 |          0.46 |
| Up! node      |     23153.89 |       5.39 |      80492.32 |          1.55 |
| Up! uWS       |     30891.58 |       4.04 | +2+ 247979.55 |          0.50 |

+1+ denotes the fastest for the response type
+2+ denotes the second fastest for the response type

running on/with:
Linux, Kernel 6.16.3
ruby 3.5.0-preview1, YJit enabled
Falcon 0.52.3, falcon --hybrid --forks 4 --threads 4 -b http://localhost:3000
Iodine 0.7.58, iodine -w 4 -t 1 -p 3000
Itsy 0.2.20, itsi -w 4
Puma 7.0.3, puma -w 4 -t 4 -p 3000
Up! node/ruby/uWS master, 4 workers, up -w 4
  Opal 2.0dev PR#2746 'raise_platform_foundation'
  Node v24.8.0

running the example_rack_app from this repo, benchmarked with:
bombardier http://localhost:3000/
and taking the Avg

on a AMD(R) Ryzen(TM) 5 4500U CPU @ 2.3~4.0 GHz
```

## Introduction

This is currently mainly a technical demonstration, demonstrating the speed of the [Opal Ruby](https://github.com/opal/opal) implementation employing [Node](https://nodejs.org/en) and [uWebSocketJs](https://github.com/uNetworking/uWebSockets.js) as runtime.

Its not yet a generic, all purpose Rack server, but good for further experimentation, research and open for improvement. The included ruby version allows for verification of code correctness and performance. If it works with `bundle exec up_ruby` it should work equally well with the various Opal versions, at least thats the future goal.

Its a intention of this project, to serve as a tool for enhancing Opal Ruby and porting Rack apps from Matz to Opal Ruby.

## Getting started

To start experimenting:
- clone this repo
- cd into it, bundle install
- cd example_rack_app
- bundle install
- bundle exec up

You may want to change the `gem 'opal-up'` line in the Gemfile to use up from rubygems, if you want to run your app outside of the cloned repo.

For a Gemfile UP! is available from rubygems:
`gem 'opal-up'`

## Available Commands

Available with `bundle exec` within the example apps or if this gem is included in your Gemfile:

- `up` - starts a cluster of workers using Opal running in Node with uWebSockets
- `up_node` - starts a cluster of workers using Opal running in Node with ws websocket support
- `up_ruby` - starts a cluster of workers using Ruby with uWebSockets in a native extension, does not support the --secure options/TLS

```
Usage: up [options]

    -h, --help                       Show this message
    -p, --port PORT                  Port number the server will listen to. Default: 3000
    -b, --bind ADDRESS               Address the server will listen to. Default: localhost
    -s, --secure                     Use secure sockets.
When using secure sockets, the -a, -c and -k options must be provided
    -a, --ca-file FILE               File with CA certs
    -c, --cert-file FILE             File with the servers certificate
    -k, --key-file FILE              File with the servers certificate
    -l, --log-file FILE              Log file
    -P, --pid-file FILE              PID file
    -v, --version                    Show version
    -w, --workers NUMBER             For clusters, the number of workers to run. Default: number of processors
```
## Supported Features

Up! implements the [Rack Spec as of Rack 3.0](https://github.com/rack/rack/blob/main/SPEC.rdoc) with the following differences:
- `rack.hijack` is not implemented, but `rack.upgrade` instead is, see "Websockets" below
- Tempfile support is currently incomplete, affecting a few keys in the Rack Env ('tempfile' missing in Opal).
- Some Rack modules/classes still have issues when run in Opal and may not work as expected

Websockets are supported following the [Iodine SPEC-WebSocket-Draft](https://github.com/boazsegev/iodine/blob/master/SPEC-WebSocket-Draft.md).
PubSub is supported following the [Iodine SPEC-PubSub-Draft](https://github.com/boazsegev/iodine/blob/master/SPEC-PubSub-Draft.md), except for engines.

A example RackApp using WebSockets and PubSub is provided in the 'example_rack_ws_app' directory

## Roda

A example app for Roda is provided and _appears_ working with the following patches applied:

- [Changes required to make Roda _appear_ to work](https://github.com/jeremyevans/roda/compare/master...janbiedermann:roda:master)
- [Changes required to make Rack with Roda _appear_ to work](https://github.com/janbiedermann/rack/commit/1dadea0f9813c2df94715052d2277af13f7d0c0c)

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

- [Falcon](https://github.com/socketry/falcon)
- [Iodine](https://github.com/boazsegev/iodine)
- [Itsy](https://github.com/wouterken/itsi)
- [Puma](https://github.com/puma/puma)
