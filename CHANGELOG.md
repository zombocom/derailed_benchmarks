# A Log of Changes!

## [1.1.0] - unreleased
- Set custom auth user using a lambda in perf.rake

## [1.0.1] - 2015-20-06

- `bundle:mem` and similar tasks now keep track of duplicate requires and display them along side of memory requirements. This makes it easier to identify where components are used by multiple libraries
- Add rake to gemspec which gets rid of `Unresolved specs during Gem::Specification.reset:` warning
- Outputs of memory are now done in [mebibytes](https://en.wikipedia.org/wiki/Mebibyte), a more accurate unit for the value we're measuring (hint: it's what you think MB is).

## [1.0.0] - 2015-15-05

- Added `derailed` command line utility. Can be used with just a Gemfile using command `$ derailed bundle:mem` and `$ derailed bundle:objects`. All existing Rake tasks can now be called with `$ derailed exec` such as `$ derailed exec perf:mem`.
- Changed memory_profiler task to be `perf:objects` instead of `perf:mem`.
- Changed boot time memory measurement to `perf:mem` instead of `perf:require_bench`
- Released seperate [derailed](https://github.com/schneems/derailed) gem that is a wrapper for this gem. I.e. installing that gem installs this one. Easier to remember, less words to type. Also means there's no colision using the `derailed` namespace for executables inside of the `derailed_benchmarks`.

## [0.0.0] - 2014-15-08

- Initial release