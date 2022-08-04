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
      tools = FspHarvester::ExternalTools.new(metadata: @meta)
      tools.process_with_distiller(body: body)
      tools.process_with_extruct(uri: uri)
    end

    def process_xml(body:)
      begin
        hash = XmlSimple.xml_in(body)
      rescue
        @meta.comments << "CRITICAL: Malformed XML detected.  Cannot process metadata.\n"
        @meta.warnings << ['020', '', '']
      end
      @meta.comments << "INFO: The XML is being merged in the metadata object\n"
      @meta.hash.merge hash
    end

    def process_json(body:)
      begin
        hash = JSON.parse(body)
      rescue
        @meta.comments << "CRITICAL: Malformed JSON detected.  Cannot process metadata.\n"
        @meta.warnings << ['021', '', '']
      end
      @meta.comments << "INFO: The JSON is being merged in the metadata object\n"
      @meta.hash.merge hash
    end

    def process_ld(body:, content_type:)
      parse_rdf(body: body, content_type: content_type)
    end

    def parse_rdf(body:, content_type:)
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

      rdfformat = RDF::Format.for(content_type: content_type)
      unless rdfformat
        @meta.comments << "CRITICAL: Found what appears to be RDF (sample:  #{body[0..300].delete!("\n")}), but it could not find a parser.  Please report this error, along with the GUID of the resource, to the maintainer of the system.\n"
        @meta.warnings << ['018', '', '']
        return
      end

      graph = FspHarvester::Cache.checkRDFCache(body: body)
      if graph.size > 0
        warn "\n\n\n unmarshalling graph from cache\n\ngraph size #{graph.size}\n\n"
        @meta.merge_rdf(graph.to_a)
      else
        warn "\n\n\nfound format #{rdfformat}\n\n"
        @meta.comments << "INFO: The response message body component appears to contain #{rdfformat}.\n"
        reader = ''
        begin
          reader = rdfformat.reader.new(body)
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
          reader = rdfformat.reader.new(body) # have to re-read it here, but now its safe because we have already caught errors
          warn 'WRITING TO CACHE'
          FspHarvester::Cache.writeRDFCache(reader: reader, body: body) # write to the special RDF graph cache
          warn 'WRITING DONE'
          reader = rdfformat.reader.new(body)  # frustrating that we cannot rewind!
          warn 'RE-READING DONE'
          @meta.merge_rdf(reader.to_a)
          warn 'MERGE DONE'
        rescue RDF::ReaderError => e
          @meta.comments << "CRITICAL: The Linked Data was malformed and caused the parser to crash with error message: #{e.message} ||  (sample of what was parsed:  #{body[0..300].delete("\n")})\n"
          warn "CRITICAL: The Linked Data was malformed and caused the parser to crash with error message: #{e.message} ||  (sample of what was parsed:  #{body[0..300].delete("\n")})\n"
          @meta.warnings << ['018', '', '']
        rescue Exception => e
          meta.comments << "CRITICAL: An unknown error occurred while parsing the (apparent) Linked Data (sample of what was parsed:  #{body[0..300].delete("\n")}).  Moving on...\n"
          warn "\n\nCRITICAL: #{e.inspect} An unknown error occurred while parsing the (apparent) Linked Data (full body:  #{body}).  Moving on...\n"
          @meta.warnings << ['018', '', '']
        end
      end
    end
  end
end
