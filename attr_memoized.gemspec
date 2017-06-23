# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'attr_memoized/version'

Gem::Specification.new do |spec|
  spec.name          = 'attr_memoized'
  spec.version       = AttrMemoized::VERSION
  spec.authors       = ['Konstantin Gredeskoul']
  spec.email         = ['kig@reinvent.one']

  spec.summary       = %q{Memoize attributes in a thread-safe way. This ruby gem adds a `#attr_memoized` class method, that provides a lazy-loading mechanism for initializing "heavy" attributes, but in a thread-safe way. Instances thus created can be shared among threads.}
  spec.description   = %q{Memoize attributes in a thread-safe way. This ruby gem adds a `#attr_memoized` class method, that provides a lazy-loading mechanism for initializing "heavy" attributes, but in a thread-safe way. Instances thus created can be shared among threads.}
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
  spec.add_development_dependency 'irbtools'
  spec.add_development_dependency 'colored2'
  spec.add_development_dependency 'codeclimate-test-reporter'
end
