# frozen_string_literal: true

module FspHarvester
  class Error < StandardError
  end

  class ExternalTools

    def initialize(metadata: FspHarvester::MetadataObject.new)
      @meta = metadata
    end

    def process_with_distiller(body:)
      bhash = Digest::SHA256.hexdigest(body)
      if @@distillerknown[bhash]
        @meta.comments << "INFO: data is already parsed by distiller.\n"
        #parse_rdf(body: body)
      else
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
          @meta.comments << "INFO: The Distiller found parseable data.  Parsing as JSON-LD\n"
          parse_rdf(result: result, content_type: "application/ld+json")
        end
        @@distillerknown[bhash] = true
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

        parse_rdf(body: json['json-ld'].to_json, content_type: 'application/ld+json') if json['json-ld'].any? # RDF
        @meta.merge_hash(json['microdata'].first) if json['microdata'].any?
        @meta.merge_hash(json['microformat'].first) if json['microformat'].any?
        @meta.merge_hash(json['opengraph'].first) if json['opengraph'].any?
        parse_rdf(body: json['rdfa'].to_json, content_type: 'application/ld+json') if json['rdfa'].any? # RDF

        @meta.merge_hash(json.first) if json.first.is_a? Hash
      else
        @meta.comments << "WARN: the extruct tool failed to find parseable data at #{uri}\n"
      end
    end
  end
end
