# frozen_string_literal: true

# Highlights every <pre><code class="language-…"> block of docs/*.html with Rouge, in place.
# Idempotent: it rebuilds each block from its text. --check writes nothing and exits 1 if a page would change.

require "cgi"
require "rouge"

CODE_BLOCK = %r{(<pre><code class="language-([\w-]+)">)(.*?)(</code></pre>)}m
TOKEN_TAG = %r{</?span[^>]*>}
FORMATTER = Rouge::Formatters::HTML.new

def highlight(page, path)
  page.gsub(CODE_BLOCK) do
    opening, language, code, closing = Regexp.last_match.captures
    lexer = Rouge::Lexer.find(language) || abort("#{path}: Rouge has no lexer for language-#{language}")
    "#{opening}#{FORMATTER.format(lexer.lex(CGI.unescapeHTML(code.gsub(TOKEN_TAG, ""))))}#{closing}"
  end
end

check = ARGV.include?("--check")
stale_paths = Dir[File.expand_path("../docs/*.html", __dir__)].sort.select do |path|
  page = File.read(path)
  highlighted = highlight(page, path)
  next false if highlighted == page

  File.write(path, highlighted) unless check
  true
end

relative_paths = stale_paths.map { |path| File.join("docs", File.basename(path)) }
abort "Not highlighted: #{relative_paths.join(", ")}. Run bundle exec rake docs:highlight" if check && stale_paths.any?
puts "Highlighted #{relative_paths.join(", ")}" if stale_paths.any?
