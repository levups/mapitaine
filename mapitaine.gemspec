# frozen_string_literal: true

require_relative "lib/mapitaine/version"

Gem::Specification.new do |spec|
  spec.name = "mapitaine"
  spec.version = Mapitaine::VERSION
  spec.authors = ["Level UP Solutions"]
  spec.summary = "XML sitemaps for Rails sites in many languages, rebuilt only where the content changed"
  spec.description = "Each kind of page is a small class that names its records, its URLs and its languages. " \
                     "Mapitaine writes the hreflang links itself, cuts the sitemap into files that keep the same " \
                     "records from one build to the next, and rewrites only the files whose records changed."
  spec.homepage = "https://github.com/levups/mapitaine"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://levups.github.io/mapitaine/"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.files = Dir["lib/**/*.{rb,rake}", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 8.0"
end
