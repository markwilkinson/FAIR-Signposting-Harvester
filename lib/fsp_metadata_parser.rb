# frozen_string_literal: true

module FspHarvester
  class Error < StandardError
  end

  class MetadataParser
    # attr_accessor :distillerknown

    @@distillerknown = {}

    def initialize(metadata_object: FspHarvester::MetadataObject.new)
      @meta = metadata_object
    end

    def process_html(body:, uri:)
      process_with_distiller(body: body)
      process_with_extruct(uri: uri)
    end

    def process_with_distiller(body:)
      bhash = Digest::SHA256.hexdigest(body)
      if @@distillerknown[bhash]
        @meta.comments << "INFO: data is already parsed by distiller.\n"
        parse_rdf(body: body)
      else
        @@distillerknown[bhash] = true

        @meta.comments << "INFO: Using 'Kellog's Distiller' to try to extract metadata from return value (message body).\n"
        file = Tempfile.new('foo', encoding: 'UTF-8')
        body = body.force_encoding('UTF-8')
        body.scrub!
        body = body.gsub(%r{"@context"\s*:\s*"https?://schema.org/?"}, '"@context": "https://schema.org/docs/jsonldcontext.json"') # a bug in distiller, apparently
        file.write(body)
        file.rewind

        @meta.comments << "INFO: The message body is being examined by Distiller\n"
        # command = "LANG=en_US.UTF-8 #{Utils::RDFCommand} serialize --input-format rdfa --output-format turtle #{file.path} 2>/dev/null"
        command = "LANG=en_US.UTF-8 #{Utils::RDFCommand} serialize --input-format rdfa --output-format jsonld #{file.path}"
        # command = "LANG=en_US.UTF-8 /usr/local/bin/ruby #{@rdf_command} serialize --input-format rdfa --output-format jsonld #{file.path}"
        # command = "LANG=en_US.UTF-8 /home/osboxes/.rvm/rubies/ruby-2.6.3/bin/ruby /home/osboxes/.rvm/gems/ruby-2.6.3/bin/rdf serialize --output-format jsonld #{file.path}"
        warn "distiller command: #{command}"
        result, _stderr, _status = Open3.capture3(command)
        warn ''
        warn "distiller errors: #{stderr}"
        file.close
        file.unlink

        result = result.force_encoding('UTF-8')
        warn "DIST RESULT: #{result}"
        if result !~ /@context/i # failure returns nil
          @meta.comments << "WARN: The Distiller tool failed to find parseable data in the body, perhaps due to incorrectly formatted HTML..\n"
          @meta.warnings << ['018', '', '']
        else
          @meta.comments << "INFO: The Distiller found parseable data.  Parsing as RDF\n"
          parse_rdf(result: result)
        end
      end
    end

    def processs_with_extruct(uri:)
      @meta.comments << "INFO:  Using 'extruct' to try to extract metadata from return value (message body) of #{uri}.\n"
      warn 'begin open3'
      stdout, stderr, status = Open3.capture3(EXTRUCT_COMMAND + ' ' + uri)
      warn "open3 status: #{status} #{stdout}"
      result = stderr # absurd that the output comes over stderr!  LOL!

      if result.to_s.match(/(Failed\sto\sextract.*?)\n/)
        @meta.comments << "WARN: extruct threw an error #{Regexp.last_match(1)} when attempting to parse return value (message body) of #{uri}.\n"
        @meta.warnings << ['019', '', '']
        if result.to_s.match(/(ValueError:.*?)\n/)
          @meta.comments << "WARN: extruct error was #{Regexp.last_match(1)}\n"
          @meta.warnings << ['019', '', '']
        end
      elsif result.to_s.match(/^\s+?\{/) or result.to_s.match(/^\s+\[/) # this is JSON
        json = JSON.parse result
        @meta.comments << "INFO: the extruct tool found parseable data at #{uri}\n"

        parse_rdf(meta, json['json-ld'].to_json, 'application/ld+json') if json['json-ld'].any? # RDF
        @meta.merge_hash(json['microdata'].first) if json['microdata'].any?
        @meta.merge_hash(json['microformat'].first) if json['microformat'].any?
        @meta.merge_hash(json['opengraph'].first) if json['opengraph'].any?
        parse_rdf(meta, json['rdfa'].to_json, 'application/ld+json') if json['rdfa'].any? # RDF

        meta.merge_hash(json.first) if json.first.is_a? Hash
      else
        meta.comments << "WARN: the extruct tool failed to find parseable data at #{uri}\n"
      end
    end

    def process_xml(body:); end

    def process_json(body:); end

    def process_ld(body:)

    end

    def parse_rdf(body:)
      unless body
        @meta.comments << "CRITICAL: The response message body component appears to have no content.\n"
        @meta.warnings << ['018', '', '']
        return
      end

      unless body.match(/\w/)
        @meta.comments << "CRITICAL: The response message body component appears to have no content.\n"
        @meta.warnings << ['018', '', '']
        return
      end

      warn "\n\n\nFORMAT CHECK \n\n#{body[0..30]}\n\n"
      rdfformat = RDF::Format.for({ sample: body[0..5000] })
      unless rdfformat
        @meta.comments << "CRITICAL: The Champion found what it believed to be RDF (sample:  #{body[0..300].delete!("\n")}), but it could not find a parser.  Please report this error, along with the GUID of the resource, to the maintainer of the system.\n"
        @meta.warnings << ['018', '', '']
        return
      end
      graph = FspHarvester::Cache.checkRDFCache(body)
      if graph.size > 0
        warn "\n\n\n unmarshalling graph from cache\n\ngraph size #{graph.size}\n\n"
        @meta.merge_rdf(graph.to_a)
      else
        warn "\n\n\nfound format #{rdfformat}\n\n"
        @meta.comments << "INFO: The response message body component appears to contain #{rdfformat}.\n"
        reader = ''
        begin
          reader = formattype.reader.new(body)
        rescue Exception => e
          @meta.comments << "WARN: Though linked data was found, it failed to parse (Exception #{e}).  This likely indicates some syntax error in the data.  As a result, no metadata will be extracted from this message.\n"
          @meta.warnings << ['018', '', '']
          return
        end

        begin
          if reader.size == 0
            @meta.comments << "WARN: Though linked data was found, it failed to parse.  This likely indicates some syntax error in the data.  As a result, no metadata will be extracted from this message.\n"
            return
          end
          reader = formattype.reader.new(body) # have to re-read it here, but now its safe because we have already caught errors
          warn 'WRITING TO CACHE'
          FspHarvester::Cache.writeRDFCache(reader, body) # write to the special RDF graph cache
          warn 'WRITING DONE'
          reader = formattype.reader.new(body)  # frustrating that we cannot rewind!
          warn 'RE-READING DONE'
          @meta.merge_rdf(reader.to_a)
          warn 'MERGE DONE'
        rescue RDF::ReaderError => e
          @meta.comments << "CRITICAL: The Linked Data was malformed and caused the parser to crash with error message: #{e.message} ||  (sample of what was parsed:  #{body[0..300].delete("\n")})\n"
          warn "CRITICAL: The Linked Data was malformed and caused the parser to crash with error message: #{e.message} ||  (sample of what was parsed:  #{body[0..300].delete("\n")})\n"
          @meta.warnings << ['018', '', '']
        rescue Exception => e
          meta.comments << "CRITICAL: An unknown error occurred while parsing the (apparent) Linked Data (sample of what was parsed:  #{body[0..300].delete("\n")}).  Moving on...\n"
          warn "\n\nCRITICAL: #{e.inspect} An unknown error occurred while parsing the (apparent) Linked Data (full body:  #{body}).  Moving on...\n\n"
          @meta.warnings << ['018', '', '']
        end
      end
    end
  end
end
