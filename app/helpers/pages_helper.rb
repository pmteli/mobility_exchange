module PagesHelper
  # Support paragraphs, bullet lists, and bold labels without accepting raw HTML.
  def page_content(text)
    blocks = text.to_s.strip.split(/\n\s*\n/).map do |block|
      lines = block.lines.map(&:strip)
      if lines.all? { |line| line.match?(/\A[-*] /) }
        tag.ul(safe_join(lines.map { |line| tag.li(page_inline(line.sub(/\A[-*] /, ""))) }))
      else
        tag.p(page_inline(lines.join(" ")))
      end
    end
    safe_join(blocks)
  end

  def page_inline(text)
    safe_join(text.split(/(\*\*[^*]+\*\*)/).map do |part|
      part.start_with?("**") && part.end_with?("**") ? tag.strong(part[2...-2]) : ERB::Util.html_escape(part)
    end)
  end
end
