# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new do |task|
  task.libs << "lib" << "test"
  task.test_files = FileList["test/*_test.rb"]
end

task default: :test

namespace :docs do
  desc "Highlight the code blocks of docs/*.html with Rouge"
  task :highlight do
    ruby "script/highlight_docs.rb"
  end

  desc "Fail if a code block of docs/*.html is not highlighted"
  task "highlight:check" do
    ruby "script/highlight_docs.rb", "--check"
  end
end
