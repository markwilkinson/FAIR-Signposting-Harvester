# frozen_string_literal: true

module HarvesterTools
  class Error < StandardError
  end

  class MetadataHarvester
    def self.extract_metadata(links: [], metadata: HarvesterTools::MetadataObject.new)
      @meta = metadata
      @meta.comments << 'INFO:  now collecting both linked data and hash-style data using the harvested links'

      describedby = links.select { |l| l if l.relation == 'describedby' }

      hvst = HarvesterTools::MetadataParser.new(metadata_object: @meta) # put here because the class variable for detecting duplicates should apply to all URIs
      describedby.each do |link|
        accepttype = ACCEPT_STAR_HEADER
        accept = link.respond_to?('type') ? link.type : nil
        accepttype = { 'Accept' => accept } if accept

        response = attempt_to_resolve(link: link, headers: accepttype)

        abbreviation, content_type = attempt_to_detect_type(body: response.body, headers: response.headers)
        unless abbreviation
          @meta.add_warning(['017', url, header])
          @meta.comments << "WARN: metadata format returned from #{url} using Accept header #{header} is not recognized.  Processing will end now.\n"
          next
        end

        # process according to detected type
        case abbreviation
        when 'html'
          @meta.comments << 'INFO: Processing html'
          hvst.process_html(body: response.body, uri: link)
        when 'xml'
          @meta.comments << 'INFO: Processing xml'
          hvst.process_xml(body: response.body)
        when 'json'
          @meta.comments << 'INFO: Processing json'
          hvst.process_json(body: response.body)
        when 'jsonld', 'rdfxml', 'turtle', 'ntriples', 'nquads'
          @meta.comments << 'INFO: Processing linked data'
          hvst.process_ld(body: response.body, content_type: content_type)
        when 'specialist'
          warn 'no specialized parsers so far'
        end
      end
    end

    def self.attempt_to_resolve(link:, headers: ACCEPT_STAR_HEADER)
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
      if body =~ /^\s*<\?xml/
        if body =~ /<HTML/i
          abbreviation = 'html'
          content_type = 'text/html'
          @meta.comments << 'INFO: appears to be HTML\n'
        elsif body =~ /<rdf:RDF/i
          abbreviation = 'rdfxml'
          content_type = 'application/rdf+xml'
          @meta.comments << 'INFO: appears to be RDF-XML\n'
        else
          abbreviation = 'xml'
          content_type = 'application/xml'
          @meta.comments << 'INFO: appears to be XML\n'
        end
      else
        abbreviation, content_type = check_ld(body: body, claimed_type: headers[:content_type])
        abbreviation, content_type = check_json(body: body) unless abbreviation
      end

      unless content_type
        @meta.add_warning(['017', url, header])
        @meta.comments << "WARN: metadata format returned from #{url} using Accept header #{header} is not recognized.  Processing will end now.\n"
      end
      [abbreviation, content_type]
    end

    def self.check_ld(body:, claimed_type:)
      detected_type = ntriples_hack(body: body) # ntriples hack for one-line metadata records
      unless detected_type
        detected_type = RDF::Format.for({ sample: body[0..5000] })
        @meta.comments << "INFO: Auto-detected type #{detected_type}\n"
      end
      contenttype = ''
      abbreviation = ''
      if detected_type
        contenttype = detected_type.content_type.first # comes back as array
        abbreviation = abbreviate_type(contenttype: contenttype)
        @meta.comments << "INFO: using content-type #{contenttype}.\n"
      else
        @meta.comments << "INFO: metadata does not appear to be in a linked data format.  Trying other options.\n"
      end
      [abbreviation, contenttype]
    end

    def self.ntriples_hack(body:)  # distriller cannot recognize single-line ntriples unless they end with a period, which is not required by the spec... so hack it!
      detected_type = nil
      body.split.each do |line|
        line.strip!
        next if line.empty?
        if line =~ %r{\s*<[^>]+>\s*<[^>]+>\s\S+}
          @meta.comments << "INFO: running ntriples hack on  #{line + " ."}\n"
          detected_type = RDF::Format.for({ sample: "#{line} ." })  # adding a period allows detection of ntriples by distiller
          break
        end        
      end
      @meta.comments << "INFO: ntriples hack found: #{detected_type.to_s}\n"
      if detected_type != RDF::NTriples::Format   # only return the hacky case
        return nil
      end
      return detected_type
    end


    def self.check_json(body:)
      abbreviation = nil
      parsed = nil
      begin
        parsed = JSON.parse(body)
      rescue StandardError
        abbreviation = nil
      end

      if parsed
        abbreviation = 'json'
      else
        @meta.comments << "INFO: metadata does not appear to be in JSON format.  No options left.\n"
      end
      [abbreviation, 'application/ld+json']
    end

    def self.abbreviate_type(contenttype:)
      foundtype = nil
      RDF_FORMATS.merge(XML_FORMATS).merge(HTML_FORMATS).merge(JSON_FORMATS).each do |type, vals|
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
