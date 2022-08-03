def check_for_citeas_conflicts(citeas: )
    @meta.comments << 'INFO: checking for conflicting cite-as links'
    citeas_hrefs = Array.new
    citeas.each do |link|
      warn "INFO: Adding citeas #{link.href} to the testing queue."
      @meta.comments << "INFO: Adding citeas #{link.href} to the testing queue."
      citeas_hrefs << link.href
    end

    if citeas_hrefs.length > 1
        @meta.comments << 'INFO: Found multiple cite-as links, now testing for conflicts.'
    end
  
    if citeas_hrefs.uniq.length == 1
      @meta.comments << 'INFO: No conflicting cite-as links found.'
    else  # only one allowed!
      @meta.warnings << ['007', '', '']
      @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard: Found conflicting cite-as link headers.\n"
    end
end


def check_describedby_rules(describedby:)
  describedby.each do |l|
    unless l.respond_to? 'type'
      @meta.warnings << ['005', l.href, '']
      @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard, which requires any describedby links to also have a 'type' attribute.\n"
    end
    type = l.type if l.respond_to? 'type'
    type ||= '*/*'
    header = { accept: type }
    response = FspHarvester::WebUtils.fspfetch(url: l.href, headers: header, method: :head)
    if response
      if response.headers[:content_type] and type != '*/*'
        rtype = type.gsub(%r{/}, "\/")
        rtype = rtype.gsub(/\+/, '.')
        typeregex = Regexp.new(rtype)
        if response.headers[:content_type].match(typeregex)
          warn response.headers[:content_type]
          warn typeregex.inspect
          @meta.comments << "INFO: describedby link responds according to Signposting specifications\n"
        else
          @meta.warnings << ['009', l.href, header]
          @meta.comments << "WARN: Content type of returned describedby link does not match the 'type' attribute\n"
        end
      else
        @meta.warnings << ['010', l.href, header]
        @meta.comments << "WARN: Content type of returned describedby link is not specified in response headers or cannot be matched against accept headers\n"
      end
    else
      @meta.warnings << ['008', l.href, header]
      @meta.comments << "WARN: describedby link doesn't resolve\n"
    end
  end
end

def check_item_rules(item:)
  item.each do |l| # l = LinkHeaders::Link
    unless l.respond_to? 'type'
      @meta.warnings << ['011', l.href, '']
      @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard, which encourages any item links to also have a 'type' attribute.\n"
    end
    type = l.type if l.respond_to? 'type'
    type ||= '*/*' # this becomes a frozen string
    header = { accept: type }
    response = FspHarvester::WebUtils.fspfetch(url: l.href, headers: header, method: :head)

    if response
      if response.headers[:content_type] and type != '*/*'
        rtype = type.gsub(%r{/}, "\/")   # because type is a frozen string
        rtype = rtype.gsub(/\+/, '.')
        typeregex = Regexp.new(type)
        if response.headers[:content_type].match(typeregex)
          warn response.headers[:content_type]
          warn typeregex.inspect
          @meta.comments << "INFO: item link responds according to Signposting specifications\n"
        else
          @meta.warnings << ['012', l.href, header]
          @meta.comments << "WARN: Content type of returned item link does not match the 'type' attribute\n"
        end
      else
        @meta.warnings << ['013', l.href, header]
        @meta.comments << "WARN: Content type of returned item link is not specified in response headers or cannot be matched against accept headers\n"
      end
    else
      @meta.warnings << ['014', l.href, header]
      @meta.comments << "WARN: item link doesn't resolve\n"
    end
  end
end
