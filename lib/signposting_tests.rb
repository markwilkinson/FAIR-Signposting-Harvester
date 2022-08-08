def check_for_citeas_conflicts(citeas: )
  @meta.comments << 'INFO: checking for conflicting cite-as links'
  citeas_hrefs = Hash.new
  citeas.each do |link|
    warn "INFO: Adding citeas #{link.href} to the testing queue."
    @meta.comments << "INFO: Adding citeas #{link.href} to the testing queue."
    citeas_hrefs[link.href] = link
  end

  if citeas_hrefs.length > 1
    @meta.comments << 'INFO: Found multiple non-identical cite-as links.'
    @meta.add_warning(['007', '', ''])
    @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard: Found conflicting cite-as link headers.\n"
  end
  citeas_hrefs.values  # return list of unique links
end


def check_describedby_rules(describedby:)
  describedby.each do |l|
    unless l.respond_to? 'type'
      @meta.add_warning(['005', l.href, ''])
      @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard, which requires any describedby links to also have a 'type' attribute.\n"
    end
    type = l.type if l.respond_to? 'type'
    type ||= '*/*'
    header = { accept: type }
    response = FspHarvester::WebUtils.fspfetch(url: l.href, headers: header, method: :head)
    if response
      responsetype = response.headers[:content_type]
      @meta.comments << "INFO: describedby link responds with content type #{responsetype}\n"
      if responsetype =~ %r{^(.*/[^;]+)}
        responsetype = Regexp.last_match(1).to_s # remove the e.g. charset information
      end
      @meta.comments << "INFO: testing content type |#{responsetype}| against |#{type}|\n"
      if type != '*/*'
        if responsetype == type
          @meta.comments << "INFO: describedby link responds according to Signposting specifications\n"
        else
          @meta.add_warning(['009', l.href, header])
          @meta.comments << "WARN: Content type of returned describedby link #{responsetype}does not match the 'type' attribute #{type}\n"
        end
      else
        @meta.add_warning(['010', l.href, header])
        @meta.comments << "WARN: Content type of returned describedby link is not specified in response headers or cannot be matched against accept headers\n"
      end
    else
      @meta.add_warning(['008', l.href, header])
      @meta.comments << "WARN: describedby link doesn't resolve\n"
    end
  end
end

def check_item_rules(item:)
  item.each do |l| # l = LinkHeaders::Link
    unless l.respond_to? 'type'
      @meta.add_warning(['011', l.href, ''])
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
          @meta.add_warning(['012', l.href, header])
          @meta.comments << "WARN: Content type of returned item link does not match the 'type' attribute\n"
        end
      else
        @meta.add_warning(['013', l.href, header])
        @meta.comments << "WARN: Content type of returned item link is not specified in response headers or cannot be matched against accept headers\n"
      end
    else
      @meta.add_warning(['014', l.href, header])
      @meta.comments << "WARN: item link doesn't resolve\n"
    end
  end
end
