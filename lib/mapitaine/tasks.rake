# frozen_string_literal: true

namespace :mapitaine do
  report = lambda do |result|
    puts "#{result.url_count} URLs#{" (full build)" if result.full}: #{result.written.size} files written, #{result.kept.size} kept, " \
         "#{result.deleted.size} deleted, #{result.submitted} URLs sent to IndexNow"
    result.warnings.each { |warning| warn "  #{warning}" }
  end

  desc "Rewrite the sitemap files whose records changed since the last build"
  task build: :environment do
    report.call(Mapitaine.build)
  end

  desc "Rewrite every sitemap file"
  task rebuild: :environment do
    report.call(Mapitaine.build(full: true))
  end

  desc "Render every sitemap without publishing it, and fail on what looks wrong in it"
  task check: :environment do
    warnings = Mapitaine.check
    abort warnings.join("\n") if warnings.any?
    puts "Nothing to report"
  end
end
