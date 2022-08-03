# frozen_string_literal: true

module FspHarvester
  class Error < StandardError
  end

  class MetadataHarvester

    def self.extract_metadata(links: [], metadata: FspHarvester::MetadataObject.new)
      @meta = metadata
      @meta.comments << "INFO:  now collecting both linked data and hash-style data using the harvested links"

      describedby = links.select {|l| l if l.relation == "describedby"}

      hvst = FspHarvester::MetadataParser.new(metadata_object: @meta)  # put here because the class variable for detecting duplicates should apply to all URIs
      describedby.each do |link|
        accepttype = ACCEPT_STAR_HEADER
        accept = link.respond_to?('type') ? link.type : nil
        accepttype = {"Accept" => accept}  if accept

        response = self.attempt_to_resolve(link: link, headers: accepttype)

        known_type = attempt_to_detect_type(body: response.body)
        unless known_type
          @meta.warnings << ['017', url, header]
          @meta.comments << "WARN: metadata format returned from #{url} using Accept header #{header} is not recognized.  Processing will end now.\n"
          next
        end

        # process according to detected type
        case known_type
        when 'html'
          @meta.comments << "INFO: Processing html"
          hvst.process_html(body: response.body, uri: db)
        when 'xml'
          @meta.comments << "INFO: Processing xml"
          hvst.process_xml(body: response.body)
        when 'json'
          @meta.comments << "INFO: Processing json"
          hvst.process_json(body: response.body)
        when 'jsonld', 'rdfxml', 'turtle', 'ntriples', 'nquads'
          @meta.comments << "INFO: Processing linked data"
          hvst.process_ld(body: response.body, known_type: known_type)
        when 'specialist'
          warn "no specialized parsers so far"
        end
  

      end
    end

    def self.attempt_to_resolve(link:, headers: ACCEPT_STAR_HEADER )
      @meta.comments << "INFO:  link #{link.href} being processed"
      unless link.respond_to? 'type'
        @meta.comments << "INFO:  link #{link.href} has no MIME type, defaulting to */*" 
      else
        header = {'Accept' => link.type}
      end
      url = link.href
      response = FspHarvester::WebUtils.fspfetch(url: url, method: :get, headers: header)
      unless response
        @meta.warnings << ['016', url, header]
        @meta.comments << "WARN: Unable to resolve describedby link #{url} using HTTP Accept header #{header}.\n"
      end
      response
    end

    def self.attempt_to_detect_type(body:)
      #  described by should be an html, xml, json, or linked data document
      detected_type = nil
      @meta.comments << "INFO: Testing metadata format for html, xml, and linked data formats"
      if body  =~ /^\s*<\?xml/
        if body =~ /<HTML/i
          detected_type = "html"
          @meta.comments << "INFO: appears to be HTML"
        else
          detected_type = "xml"
          @meta.comments << "INFO: appears to be XML"
        end
      else
        detected_type = check_ld(body: body)
        unless detected_type 
          detected_type = check_json(body: body)
        end
      end
      
      unless detected_type
        @meta.warnings << ['017', url, header]
        @meta.comments << "WARN: metadata format returned from #{url} using Accept header #{header} is not recognized.  Processing will end now.\n"
      end
      detected_type
    end


    def self.check_ld(body:)
      detected_type = RDF::Format.for({:sample => body[0..5000]})
      unless detected_type
          @meta.comments << "INFO: metadata does not appear to be in a linked data format.  Trying other options."
      else
        contenttype = detected_type.content_type.first # comes back as array
        detected_type = abbreviate_type(contenttype: contenttype)
      end
      detected_type
    end

    def self.check_json(body:)
      detected_type = nil
      parsed = nil
      begin
        parsed = JSON.parse(body)
      rescue
        detected_type = nil
      end

      unless parsed
          @meta.comments << "INFO: metadata does not appear to be in JSON format.  No options left."
      else
        detected_type = "json"
      end
    end

    def self.abbreviate_type(contenttype:)
      foundtype = nil
      RDF_FORMATS.merge(XML_FORMATS).merge(HTML_FORMATS).merge(JSON_FORMATS).each do |type, vals|
        @meta.comments << "INFO: testing #{type} MIME types"
        next unless vals.include? contenttype
        foundtype = type
        @meta.comments << "INFO: detected a #{type} MIME type"
        break
      end
      foundtype
    end
  end
end