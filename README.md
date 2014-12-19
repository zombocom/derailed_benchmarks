## Derailed Benchmarks

A series of things you can use to benchmark a Rails app

![](http://media.giphy.com/media/lfbxexWy71b6U/giphy.gif)

## Compatibility/Requirements

This gem has been tested and is known to work with Rails 3.2 using Ruby
2.1. It is not expected to work with older or newer versions of Ruby. You'll need to
install `curl` as well in the off chance you haven't already.

## Install

Put this in your gemfile:

```
gem 'derailed_benchmarks', group: :development
```

Then run `$ bundle install`.

This part is **important** run this command to create a `perf.rake`

```
$ cat <<  EOF > perf.rake
  require 'bundler'
  Bundler.setup

  require 'derailed_benchmarks'
  require 'derailed_benchmarks/tasks'
EOF
```

The file should look like this:

```
$ cat perf.rake
  require 'bundler'
  Bundler.setup

  require 'derailed_benchmarks'
  require 'derailed_benchmarks/tasks'
```

This is done so the benchmarks will be loaded before your application, this is important for some benchmarks and less for others. This also prevents you from accidentally loading these benchmarks when you don't need them.

## Run

To find out the tasks available you can use `$ rake -f perf.rake -T` which essentially says use the file `perf.rake` and list all the tasks.

```
$ rake -f perf.rake -T
rake perf:allocated_objects  # outputs allocated object diff after app is called TEST_COUNT times
rake perf:ips                # ips
rake perf:mem                # profiles ruby allocation
rake perf:ram_over_time      # outputs ram usage over time
rake perf:require_bench      # show memory usage caused by invoking require per gem
rake perf:stackprof          # sampling stack time
rake perf:test               # hits the url TEST_COUNT times
```

All the rake tasks accept configuration in the form of environment variables. For example, this command will measure the time it takes to hit your site `100,000` times:

```
$ rake -f perf.rake perf:test TEST_COUNT=100_000
```

Tests run against the production environment by default, but it's easy to
change this if your app doesn't run locally with `RAILS_ENV` set to
`production`. For example:

```
$ rake -f perf.rake perf:mem RAILS_ENV=development
```

## Rack Setup

Using Rails? You don't need to do anything special. If you're using Rack, you need to tell us how to boot your app. In your `perf.rake` file add a task:

```
namespace :perf do
  task :rack_load do
    DERAILED_APP = # your code here
  end
end
```

Set the constant `DERAILED_APP` to your Rack app. See [schneems/derailed_benchmarks#1](https://github.com/schneems/derailed_benchmarks/pull/1) for more info.


## Config

Here are the common environment variables.

### PATH_TO_HIT

By default tasks will hit your homepage `/`. If you want to hit a different url use `PATH_TO_HIT` for example if you wanted to go to `users/new` you can execute:

```
PATH_TO_HIT=/users/new
```

### USE_SERVER

All tests are run without a webserver by default, if you want to use a webserver set `USE_SERVER` to a Rack::Server compliant server, such as `webrick`.

```
USE_SERVER=webrick
```

### TEST_COUNT

If the test contains an interation (most of them do), control how many times the test will loop before exiting with `TEST_COUNT`. To run `1` time you can execute

```
TEST_COUNT=1
```

Note some tasks have different defaults.

### USE_AUTH

See the section on [Authentication](#authentication) below.


## Task Specific notes


### perf:mem

This task uses `memory_profiler` to see where memory is allocated while it is running. By default it will iterate once


### perf:ips

Determines the number of times your app can serve a web request each second (iterations per second). Higher number is better. Note this will be much larger if you do not use a server.


### perf:ram_over_time

Your app will use memory differently over time, this task records RSS memory usage every 5 seconds and outputs the value to STDOUT and to a file in `tmp/`. You can use this to build graphs (https://drive.google.com).


### perf:require_bench

Shows the amount of memory (RAM) each library takes up when it is required.


```
action_controller/railtie: 1.06 mb
  action_controller: 0.72 mb
    action_controller/metal/live: 0.38 mb
      action_dispatch/http/response: 0.17 mb
        rack/request: 0.05 mb
```

## Authentication

If you're trying to test an endpoint that has authentication you'll need to tell your task how to bypass that authentication. Authentication is controlled by the `DerailedBenchmarks.auth` object. There is a built in support for Devise. If you're using some other authentication method, you can write your own authentication strategy.

To enable authentication in a test run with:

```
USE_AUTH=true
```

See below how to customize authentication.

### Authentication with Devise

If you're using devise, there is a built in auth helper that will detect the presence of the devise gem and load automatically. If you want you can customize the user that is logged in by setting that value in your `perf.rake` file.

```
DerailedBenchmarks.auth.user = User.find_or_create!(twitter: "schneems")
```

You will need to provide a valid user, so depending on the validations you have in your `user.rb`, you may need to provide different parameters.

If you're trying to authenticate a non-user model, you'll need to write your own custom auth strategy.

### Custom Authentication Strategy

To implement your own authentication strategy You will need to create a class that [inherits from auth_helper.rb](lib/derailed_benchmarks/auth_helper.rb). You will need to implement a `setup` and a `call` method. You can see an example of [how the devise auth helper was written](lib/derailed_benchmarks/auth_helpers/devise.rb). You can put this code in your `perf.rake` file.

```ruby
class MyCustomAuth < DerailedBenchmarks::AuthHelper
  def setup
    # initialize code here
  end

  def call(env)
    # log something in on each request
    app.call(env)
  end
end
```

The devise strategy works by enabling test mode inside of the Rack request and inserting a stub user. You'll need to duplicate that logic for your own authentication scheme if you're not using devise.

Once you have your class, you'll need to set `DerailedBenchmarks.auth` to a new instance of your class. In your `perf.rake` file add:

```ruby
DerailedBenchmarks.auth = MyCustomAuth.new
```

Now on every request that is made with the `USE_AUTH` environment variable set, the `MyCustomAuth#call` method will be invoked.

## License

MIT


## Acknowledgements

Most of the commands are wrappers around other libraries, go check them out. Also thanks to [@tenderlove](https://twitter.com/tenderlove) as I cribbed some of the Rails init code in `$ rake perf:setup` from one of his projects.

kthksbye [@schneems](https://twitter.com/schneems)
