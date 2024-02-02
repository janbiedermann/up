<img src="https://raw.githubusercontent.com/janbiedermann/up/master/up_logo.svg" alt="UP Logo">
<small>Original Image by <a href="https://www.freepik.com/free-vector/colorful-arrows_715199.htm#query=up&position=3&from_view=search&track=sph&uuid=63f9eddf-02a6-4e5c-8178-8cfa507ee33d">Freepik</a>, modified though</small>

# UP

A high performance Rack server for Opal Ruby, Tech Demo

## Let Numbers speak first

```
Requests per second:
Puma:    6391.01 req/s
Iodine: 18645.58 req/s
Up!:    20258.46 req/s <<< fastest

Time per Request, mean, across all concurrent requests:
Puma:    0.156ms
Iodine:  0.054ms
Up!:     0.049ms  <<< fastest
```
running on linux with:
ruby 3.3.0, YJit enabled
Opal 1.8.2 with node v2011.0
Puma 6.4.2, 4 workers, 4 threads
Iodine 0.7.57, 4 workers, 4 threads
Up! 0.0.1, 1 worker, no threads

running the example_rack_app from this repo, benchmarked with:
`ab -n 100000 -c 10 http://localhost:3000/`

## Introduction

This is currently mainly a technical demonstration, demonstrating the speed of the Opal Ruby implementation employing Node and UWebSocketJs as runtime. Its not yet a generic, all purpose Reck server, but good for further experimentation, research and open for improvement.

## Getting started

To start experimenting:
- clone this repo
- cd into it, bundle install
- cd example_rack_app
- bundle install
- bundle exec up

You may want to change the `gem 'up'` line in the Gemfile to use up from rubygems, if you want to run your app outside of the cloned repo.

## Roda, Sinatra, others ...

... currently do not work! Just basic Rack apps with a few dependencies.

Example apps for Roda and Sinatra are provided, for convenience of developing and expanding the capabilities of Opal.

