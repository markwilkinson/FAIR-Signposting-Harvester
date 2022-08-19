# frozen_string_literal: true

module HarvesterTools
  class Error < StandardError
  end

  class MetadataHarvester
    def self.extract_metadata_from_links(links: [], metadata: HarvesterTools::MetadataObject.new)
      @meta = metadata
      @meta.comments << 'INFO:  now collecting both linked data and hash-style data using the harvested links'

      describedby = links.select { |l| l if l.relation == 'describedby' }

      hvst = HarvesterTools::MetadataParser.new(metadata_object: @meta) # put here because the class variable for detecting duplicates should apply to all URIs
      describedby.each do |link|
        accepttype = FspHarvester::ACCEPT_STAR_HEADER
        accept = link.respond_to?('type') ? link.type : nil
        accepttype = { 'Accept' => accept } if accept

        response = attempt_to_resolve(link: link, headers: accepttype)

        abbreviation, content_type = attempt_to_detect_type(body: response.body, headers: response.headers)
        unless abbreviation
          @meta.add_warning(['017', url, header])
          @meta.comments << "WARN: metadata format returned from #{url} using Accept header #{header} is not recognized.  Processing will end now.\n"
          next
        end

        process_according_to_type(body: response.body, uri: link, metadata: @meta, abbreviation: abbreviation,
                                  content_type: content_type, harvester: hvst)
      end
    end

    def self.extract_metadata_from_body(response:, metadata: HarvesterTools::MetadataObject.new)
      @meta = metadata
      @meta.comments << 'INFO:  now collecting both linked data and hash-style data using the harvested links'

      abbreviation, content_type = attempt_to_detect_type(body: response.body, headers: response.headers)
      unless abbreviation
        @meta.add_warning(['017', response.request.url, ''])
        @meta.comments << "WARN: format returned from #{response.request.url} is not recognized. Moving on.\n"
        return
      end
      request_content_types = response.request.headers["Accept"].split(/,\s*/)
      unless (request_content_types.include? content_type) and !(request_content_types.include? "*/*") and (response.code != 406)
        @meta.add_warning(['023', response.request.url, ''])
        @meta.comments << "WARN: format returned from #{response.request.url} does not match request type.  This should result in a 406 error, but instead was accepted as a 200.\n"
      end
      process_according_to_type(body: response.body, uri: response.request.url, metadata: @meta,
                                abbreviation: abbreviation, content_type: content_type)
    end

    def self.process_according_to_type(body:, uri:, abbreviation:, content_type:, metadata:,
                                   harvester: HarvesterTools::MetadataParser.new(metadata_object: @meta))
      case abbreviation
      when 'html'
        @meta.comments << 'INFO: Processing html'
        harvester.process_html(body: body, uri: uri, metadata: @meta)
      when 'xml'
        @meta.comments << 'INFO: Processing xml'
        harvester.process_xml(body: body, metadata: @meta)
      when 'json'
        @meta.comments << 'INFO: Processing json'
        harvester.process_json(body: body, metadata: @meta)
      when 'jsonld', 'rdfxml', 'turtle', 'ntriples', 'nquads'
        @meta.comments << 'INFO: Processing linked data'
        harvester.process_ld(body: body, content_type: content_type, metadata: @meta)
      when 'specialist'
        warn 'no specialized parsers so far'
      end
    end

    def self.attempt_to_resolve(link:, headers: FspHarvester::ACCEPT_STAR_HEADER)
      @meta.comments << "INFO:  link #{link.href} being processed"
      if link.respond_to? 'type'
        header = { 'Accept' => link.type }
      else
        @meta.comments << "INFO:  link #{link.href} has no MIME type, defaulting to */*"
      end
      url = link.href
      response = HarvesterTools::WebUtils.fspfetch(url: url, method: :get, headers: header)
      unless response
        @meta.add_warning(['016', url, header])
        @meta.comments << "WARN: Unable to resolve describedby link #{url} using HTTP Accept header #{header}.\n"
      end
      response
    end

    def self.attempt_to_detect_type(body:, headers:)
      #  described by should be an html, xml, json, or linked data document
      abbreviation = nil
      content_type = nil
      @meta.comments << 'INFO: Testing metadata format for html, xml, and linked data formats\n'
      claimed_type = headers[:content_type]
      claimed_type.gsub!(/\s*;.*/, '')
      if body =~ /^\s*<\?xml/
        if body[0..1000] =~ /<HTML/i  # take a sample, it should appear quite early (it will appear in other places in e.g. tutorial documents)
          abbreviation = 'html'
          content_type = validate_claimed_type(abbreviation: abbreviation, claimed_type: claimed_type)
          @meta.add_warning(['022', @meta.all_uris.last, "" ]) unless content_type
          content_type |= 'text/html'
          @meta.comments << 'INFO: appears to be HTML\n'
        elsif body =~ /<rdf:RDF/i
          abbreviation = 'rdfxml'
          content_type = validate_claimed_type(abbreviation: abbreviation, claimed_type: claimed_type)
          @meta.add_warning(['022', @meta.all_uris.last, "" ]) unless content_type
          content_type |= 'application/rdf+xml'
          @meta.comments << 'INFO: appears to be RDF-XML\n'
        else
          abbreviation = 'xml'
          content_type = validate_claimed_type(abbreviation: abbreviation, claimed_type: claimed_type)
          @meta.add_warning(['022', @meta.all_uris.last, "" ]) unless content_type
          content_type |= 'application/xml'
          @meta.comments << 'INFO: appears to be XML\n'
        end
      elsif body[0..1000] =~ /<HTML/i # take a sample, it should appear quite early (it will appear in other places in e.g. tutorial documents)
        abbreviation = 'html'
        content_type = validate_claimed_type(abbreviation: abbreviation, claimed_type: claimed_type)
        @meta.add_warning(['022', @meta.all_uris.last, "" ]) unless content_type
        content_type ||= 'text/html'
        @meta.comments << 'INFO: appears to be HTML\n'
      else
        abbreviation, content_type = check_ld(body: body, claimed_type: claimed_type)
        abbreviation, content_type = check_json(body: body) unless abbreviation  # don't test if LD already found!
      end

      unless content_type
        @meta.add_warning(['017', url, header])
        @meta.comments << "WARN: metadata format returned from #{url} using Accept header #{header} is not recognized.  Processing will end now.\n"
      end
      [abbreviation, content_type]
    end

    def self.validate_claimed_type(abbreviation:, claimed_type:)
        warn "\n\nclaimed type #{claimed_type}\nabbreviation #{abbreviation}\n\n"
        claimed_type.gsub!(/\s*;.*/, '')

        case abbreviation
        when 'html'
          return claimed_type if FspHarvester::HTML_FORMATS['html'].include? claimed_type
        when 'xml'
          return claimed_type if FspHarvester::XML_FORMATS['xml'].include? claimed_type
        when 'json'
          return claimed_type if FspHarvester::JSON_FORMATS['json'].include? claimed_type
        when 'jsonld', 'rdfxml', 'turtle', 'ntriples', 'nquads'
          return claimed_type if FspHarvester::RDF_FORMATS.values.flatten.include? claimed_type
        when 'specialist'
          warn 'no specialized parsers so far'
        end
        return false
    end

    def self.check_ld(body:, claimed_type:)
      detected_type = ntriples_hack(body: body) # ntriples hack for one-line metadata records
      unless detected_type  # see if distiller can detect a type
        detected_type = RDF::Format.for({ sample: body[0..5000].force_encoding('UTF-8')})
        @meta.comments << "INFO: Auto-detected type #{detected_type}\n"
      end
      # at this point, detected_type is something like RDF::Turtle::Format (or nil).  This will return a content-type
      contenttype = ''
      abbreviation = ''
      if detected_type
        detectedcontenttypes = detected_type.content_type # comes back as array of [application/x, application/y]
        unless detectedcontenttypes.include? claimed_type
          @meta.add_warning(['022', @meta.all_uris.last, "" ]) 
          contenttype = detected_type.content_type.first  # just pick one arbitrarily, since it doesn't match thedeclared type anyway
          abbreviation = abbreviate_type(contenttype: contenttype)
          @meta.comments << "INFO: using content-type #{contenttype} even though there was a mismatch.\n"
        else
          contenttype = claimed_type  # just pick one arbitrarily, since it doesn't match thedeclared type anyway
          abbreviation = abbreviate_type(contenttype: contenttype)
          @meta.comments << "INFO: using content-type #{contenttype}.\n"
        end
      else
        @meta.comments << "INFO: metadata does not appear to be in a linked data format.  Trying other options.\n"
      end
      [abbreviation, contenttype]
    end

    def self.ntriples_hack(body:) # distriller cannot recognize single-line ntriples unless they end with a period, which is not required by the spec... so hack it!
      detected_type = nil
      body.split.each do |line|
        line.strip!
        next if line.empty?

        next unless line =~ /\s*<[^>]+>\s*<[^>]+>\s\S+/

        @meta.comments << "INFO: running ntriples hack on  #{line + ' .'}\n"
        detected_type = RDF::Format.for({ sample: "#{line} ." }) # adding a period allows detection of ntriples by distiller
        break
      end
      @meta.comments << "INFO: ntriples hack found: #{detected_type}\n"
      return nil if detected_type != RDF::NTriples::Format # only return the hacky case

      detected_type
    end

    def self.check_json(body:)
      abbreviation = nil
      parsed = nil
      begin
        parsed = JSON.parse(body.force_encoding('UTF-8'))
      rescue StandardError
        abbreviation = nil
      end

      if parsed
        abbreviation = 'json'
      else
        @meta.comments << "INFO: metadata does not appear to be in JSON format.  No options left.\n"
        return [nil, nil]
      end
      [abbreviation, 'application/json']
    end

    def self.abbreviate_type(contenttype:)
      foundtype = nil
      FspHarvester::RDF_FORMATS.merge(FspHarvester::XML_FORMATS).merge(FspHarvester::HTML_FORMATS).merge(FspHarvester::JSON_FORMATS).each do |type, vals|
        warn "\n\ntype #{type}\nvals #{vals}\n\n"
        @meta.comments << "INFO: testing #{type} MIME types for #{contenttype}"
        next unless vals.include? contenttype

        foundtype = type
        @meta.comments << "INFO: detected a #{type} MIME type"
        break
      end
      foundtype
    end
  end
end
