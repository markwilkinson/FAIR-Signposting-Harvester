# frozen_string_literal: true

module HarvesterTools
  class Error < StandardError
  end

  class ExternalTools

    def initialize(metadata: HarvesterTools::MetadataObject.new)
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
        command = "LANG=en_US.UTF-8 #{RDFCommand} serialize --input-format rdfa --output-format jsonld #{file.path}"
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
          @meta.add_warning(['018', '', ''])
          result = "{}"
        else
          @meta.comments << "INFO: The Distiller found parseable data.  Parsing as JSON-LD\n"
        end
        @@distillerknown[bhash] = true
      end
      result
    end

    def processs_with_extruct(uri:)
      @meta.comments << "INFO:  Using 'extruct' to try to extract metadata from return value (message body) of #{uri}.\n"
      warn 'begin open3'
      stdout, stderr, status = Open3.capture3(EXTRUCT_COMMAND + ' ' + uri)
      warn "open3 status: #{status} #{stdout}"
      result = stderr # absurd that the output comes over stderr!  LOL!
      jsonld = {}
      microdata = Hash.new
      microformat = Hash.new
      opengraph = Hash.new
      rdfa = Hash.new

      if result.to_s.match(/(Failed\sto\sextract.*?)\n/)
        @meta.comments << "WARN: extruct threw an error #{Regexp.last_match(1)} when attempting to parse return value (message body) of #{uri}.\n"
        @meta.add_warning(['019', '', ''])
        if result.to_s.match(/(ValueError:.*?)\n/)
          @meta.comments << "WARN: extruct error was #{Regexp.last_match(1)}\n"
          @meta.add_warning(['019', '', ''])
        end
      elsif result.to_s.match(/^\s+?\{/) or result.to_s.match(/^\s+\[/) # this is JSON
        json = JSON.parse result
        @meta.comments << "INFO: the extruct tool found parseable data at #{uri}\n"
        jsonld = json['json-ld'].to_json if json['json-ld'].any?
        microdata = json['microdata'].first if json['microdata'].any
        microformat = json['microformat'].first if json['microformat'].any?
        opengraph = json['opengraph'].first if json['opengraph'].any?
        rdfa = json['rdfa'].to_json if json['rdfa'].any?
        # @meta.merge_hash(json.first) if json.first.is_a? Hash
      else
        @meta.comments << "WARN: the extruct tool failed to find parseable data at #{uri}\n"
      end
      [jsonld, microdata, microformat, opengraph, rdfa]
    end
  end
end
