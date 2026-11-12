# frozen_string_literal: true

module Maptain
  class Railtie < Rails::Railtie
    SOURCES_DIRECTORY = "app/sitemaps"

    rake_tasks { load File.expand_path("tasks.rake", __dir__) }

    config.after_initialize do |app|
      Maptain::Source.include(app.routes.url_helpers)
      Maptain.configuration.load_sources = lambda do
        directory = app.root.join(SOURCES_DIRECTORY)
        Rails.autoloaders.main.eager_load_dir(directory) if directory.directory?
      end
    end
  end
end
