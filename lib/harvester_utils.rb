module HarvesterTools
  class Error < StandardError
  end

  class Utils

    def self.resolve_guid(guid:, metadata: HarvesterTools::MetadataObject.new)
      @meta = metadata
      @meta.all_uris = [guid]
      type, url = convertToURL(guid: guid)
      links = Array.new
      if type
        links = resolve_url(url: url, metadata: @meta)
        @meta.links = @meta.links.append(*links)
      else
        @meta.add_warning(['006', guid, ''])
        @meta.comments << "FATAL: GUID type not recognized.\n"
      end
      [links, @meta]
    end

    def self.convertToURL(guid:)
      FspHarvester::GUID_TYPES.each do |k, regex|
        if k == 'inchi' and regex.match(guid)
          return 'inchi', "https://pubchem.ncbi.nlm.nih.gov/rest/rdf/inchikey/#{guid}"
        elsif k == 'handle1' and regex.match(guid)
          return 'handle', "http://hdl.handle.net/#{guid}"
        elsif k == 'handle2' and regex.match(guid)
          return 'handle', "http://hdl.handle.net/#{guid}"
        elsif k == 'uri' and regex.match(guid)
          return 'uri', guid
        elsif k == 'doi' and regex.match(guid)
          return 'doi', "https://doi.org/#{guid}"
        elsif k == 'ark' and regex.match(guid)
          return 'ark', "https://n2t.net/#{guid}"
        end
      end
      [nil, nil]
    end

    def self.typeit(guid:)
      FspHarvester::GUID_TYPES.each do |type, regex|
        return type if regex.match(guid)
      end
      false
    end

    def self.resolve_url(url:, method: :get, nolinkheaders: false, metadata:, header: FspHarvester::ACCEPT_STAR_HEADER)
      @meta = metadata
      @meta.guidtype = 'uri' if @meta.guidtype.nil?
      warn "\n\n FETCHING #{url} #{header}\n\n"
      response = HarvesterTools::WebUtils.fspfetch(url: url, headers: header, method: method, meta: @meta)
      warn "\n\n head #{response.headers.inspect}\n\n" if response

      unless response
        @meta.add_warning(['001', url, header])
        @meta.comments << "WARN: Unable to resolve #{url} using HTTP Accept header #{header}.\n"
        return []
      end

      @meta.comments << "INFO: following redirection using this header led to the following URL: #{@meta.all_uris.last}.  Using the output from this URL for the next few tests..."
      @meta.full_response << response.body

      links = process_link_headers(response: response, metadata: @meta) unless nolinkheaders
      links
    end

    def self.process_link_headers(response:, metadata:)
      warn "\n\n parsing #{response.headers}\n\n"
      
      parser = LinkHeaders::Processor.new(default_anchor: metadata.all_uris.last)
      parser.extract_and_parse(response: response)
      factory = parser.factory # LinkHeaders::LinkFactory
      FspHarvester::Utils.signpostingcheck(factory: factory, metadata: metadata)
      factory.all_links
    end
  end
end
