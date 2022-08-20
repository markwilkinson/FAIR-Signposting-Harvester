module HarvesterTools
  class Error < StandardError
  end

  class BruteForce
    def self.begin_brute_force(guid:, links: [], metadata: HarvesterTools::MetadataObject.new)
      type, url = HarvesterTools::Utils.convertToURL(guid: guid)
      return false unless type

      # TODO:  follow rel=alternate headers, if they are in LD or Hash format
      do_content_negotiation(url: url, metadata: metadata, links: links)
      metadata
    end

    def self.do_content_negotiation(url:, metadata:, links: [])
      warn "\n\nINFO: entering content negotiation of #{url}\n\n"
      metadata.comments << "INFO: entering content negotiation of #{url}.\n"


      response = resolve_url_brute(url: url, metadata: metadata, headers: FspHarvester::ACCEPT_LD_HEADER)
      if response
        HarvesterTools::MetadataHarvester.extract_metadata_from_body(response: response, metadata: metadata)
      end
      response = resolve_url_brute(url: url, metadata: metadata, headers: FspHarvester::ACCEPT_STAR_HEADER)
      if response
        HarvesterTools::MetadataHarvester.extract_metadata_from_body(response: response, metadata: metadata) # extract from landing page
        response = resolve_url_brute(url: response.request.url, metadata: metadata, headers: FspHarvester::ACCEPT_LD_HEADER) # now do content negotiation on the landing page
        if response
          HarvesterTools::MetadataHarvester.extract_metadata_from_body(response: response, metadata: metadata) # extract from landing page
        end
      end

      process_alternates(links: links, metadata: metadata)
    end

    def self.process_alternates(links: [], metadata:)
      warn "\n\nINFO: entering content negotiation on link alternates\n\n"
      metadata.comments << "INFO: entering content negotiation on link alternates.\n"
      # process "alternate" links
      links.each do |link|  
        next unless link.relation == "alternate"
        next unless sanity_check_alternate(link: link, metadata: metadata)  # don't try to process zip files!  LOL!

        url = link.href
        headers = {'Accept' => "#{link.type}"} if link.respond_to?("type")
        headers ||= FspHarvester::ACCEPT_STAR_HEADER
        warn "\n\nINFO: resolving alternate #{url} with headers #{headers.to_s}\n\n"
        metadata.comments << "INFO: entering content negotiation on link alternates.\n"
        response = resolve_url_brute(url: url, metadata: metadata, headers: headers) # now do content negotiation on the link
        if response
          HarvesterTools::MetadataHarvester.extract_metadata_from_body(response: response, metadata: metadata) # extract from alternate link
        end
      end

    end

    def self.sanity_check_alternate(link:, metadata:)
      type = link.type if link.respond_to?('type')
      href = link.href
      unless type # we're gonna have to check extensions...
        m = href.match(/.*\.[\w\-]+/)
        extension = m[1]
        unless %w[json jsonld rdf ttl turtle n3 triples ntriples txt html xhtml nq xml].include? extension
          warn "\n\nINFO: extension #{extension} is not trusted as a link 'alternate' representation for metadata, so it will not be processed\n"
          metadata.comments << "INFO: extension #{extension} is not trusted as a link 'alternate' representation for metadata, so it will not be processed.\n"
          return false
        end
        return true
      end
      type.gsub!(/;.*/, '')  # remove any UTF8 blah blah
      abbrev = HarvesterTools::MetadataHarvester.abbreviate_type(contenttype: type)
      unless abbrev
        warn "\n\nINFO: content-type #{type} is not trusted as a link 'alternate' representation for metadata, so it will not be processed\n"
        metadata.comments << "INFO: content-type #{type} is not trusted as a link 'alternate' representation for metadata, so it will not be processed.\n"
        return false
      end
      true
    end

    def self.resolve_url_brute(url:, method: :get, nolinkheaders: true, headers:, metadata:)

      cache_key = Digest::MD5.hexdigest url + headers.to_s
      if metadata.url_header_hash[cache_key]
        warn "Already processed #{url} - moving on"
        metadata.comments << "INFO: Already processed #{url} - moving on.\n"
        return false
      end

      metadata.guidtype = 'uri' if metadata.guidtype.nil?
      warn "\n\n BRUTE FETCHING #{url} \nwith headers\n #{headers}\n\n"
      response = HarvesterTools::WebUtils.fspfetch(url: url, headers: headers, method: method, meta: metadata)
      warn "\n\n head #{response.headers.inspect}\n\n" if response

      unless response
        metadata.add_warning(['001', url, headers])
        metadata.comments << "WARN: Unable to resolve #{url} using HTTP Accept header #{headers}.\n"
        metadata.full_response << [url, "No response"]
        false
      end

      metadata.comments << "INFO: following redirection using this header led to the following URL: #{metadata.all_uris.last}.  Using the output from this URL for the next few tests..."
      metadata.full_response << [url, response.body]
      metadata.url_header_hash[cache_key] = true
      response
    end
  end
end