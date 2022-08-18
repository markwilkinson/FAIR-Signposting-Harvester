module HarvesterTools
  class Error < StandardError
  end

  class BruteForce
    def self.begin_brute_force(guid:, metadata: HarvesterTools::MetadataObject.new)
      type, url = HarvesterTools::Utils.convertToURL(guid: guid)
      return false unless type
      # TODO:  follow rel=alternate headers, if they are in LD or Hash format
      do_content_negotiation(url: url, metadata: metadata)
      metadata
    end

    def self.do_content_negotiation(url:, metadata:)
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
    end

    def self.resolve_url_brute(url:, method: :get, nolinkheaders: true, headers:, metadata:)
      @meta = metadata
      @meta.guidtype = 'uri' if @meta.guidtype.nil?
      warn "\n\n BRUTE FETCHING #{url} \nwith headers\n #{headers}\n\n"
      response = HarvesterTools::WebUtils.fspfetch(url: url, headers: headers, method: method, meta: @meta)
      warn "\n\n head #{response.headers.inspect}\n\n" if response

      unless response
        @meta.add_warning(['001', url, headers])
        @meta.comments << "WARN: Unable to resolve #{url} using HTTP Accept header #{headers}.\n"
        @meta.full_response << [url, "No response"]
        false
      end

      @meta.comments << "INFO: following redirection using this header led to the following URL: #{@meta.all_uris.last}.  Using the output from this URL for the next few tests..."
      @meta.full_response << [url, response.body]
      response
    end
  end
end