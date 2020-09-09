# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

def shell(*args)
  puts "running: #{args.join(' ')}"
  system(args.join(' '))
end

task :permissions do
  shell('rm -rf pkg/ tmp/')
  shell("chmod -v o+r,g+r * */* */*/* */*/*/* */*/*/*/* */*/*/*/*/*")
  shell("find . -type d -exec chmod o+x,g+x {} \\;")
end

task build: :permissions

RSpec::Core::RakeTask.new(:spec)

task default: :spec

task gem: :install do
  gem = `ls -1 *.gemspec | sed 's/\.gemspec//g'`.chomp
  puts "gem is #{gem}"
  puts `gem uninstall -ax #{gem}`.chomp
  file = `ls -1 pkg`.chomp
  puts `gem install pkg/#{file}`
end
