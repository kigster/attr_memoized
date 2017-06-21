# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'attr_memoized/version'

Gem::Specification.new do |spec|
  spec.name          = 'attr_memoized'
  spec.version       = AttrMemoized::VERSION
  spec.authors       = ['Konstantin Gredeskoul']
  spec.email         = ['kig@reinvent.one']

  spec.summary       = %q{This gem adds #attr_memoized class method that ensures the block that executes once to get the initial value is executed truly only once, and is thread safe.}
  spec.description   = %q{This gem adds #attr_memoized class method that ensures the block that executes once to get the initial value is executed truly only once, and is thread safe.}
  spec.homepage      = 'https://github.com/kigster/attr_memoized'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1'
  spec.add_development_dependency 'rake', '~> 12'
  spec.add_development_dependency 'rspec', '~> 3'
  spec.add_development_dependency 'rspec-its'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'codeclimate-test-reporter'
end
