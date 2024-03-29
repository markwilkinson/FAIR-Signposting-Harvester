# frozen_string_literal: true
module HarvesterTools
  class Error < StandardError
  end

  class MetadataParser
    # attr_accessor :distillerknown

    @@distillerknown = {}

    def initialize(metadata_object: HarvesterTools::MetadataObject.new)
      @meta = metadata_object
    end

    def process_html(body:, uri:, metadata: @meta)
      tools = HarvesterTools::ExternalTools.new(metadata: @meta)
      tools.process_with_distiller(body: body, metadata: @meta) # adds to @meta

      jsonld, microdata, microformat, opengraph, rdfa = tools.process_with_extruct(uri: uri, metadata: @meta)
      parse_rdf(body: jsonld, content_type: 'application/ld+json', metadata: metadata)
      @meta.merge_hash(microdata)
      @meta.merge_hash(microformat) 
      @meta.merge_hash(opengraph) 
      parse_rdf(body: rdfa, content_type: 'application/ld+json', metadata: @meta)
    end

    def process_xml(body:, metadata:)
      
      begin
        hash = XmlSimple.xml_in(body)
      rescue
        metadata.comments << "CRITICAL: Malformed XML detected.  Cannot process metadata.\n"
        metadata.add_warning(['020', '', ''])
      end
      metadata.comments << "INFO: The XML is being merged in the metadata object\n"
      metadata.hash.merge hash
    end

    def process_json(body:, metadata:)
      begin
        hash = JSON.parse(body)
      rescue
        metadata.comments << "CRITICAL: Malformed JSON detected.  Cannot process metadata.\n"
        metadata.add_warning(['021', '', ''])
      end
      metadata.comments << "INFO: The JSON is being merged in the metadata object\n"
      metadata.hash.merge hash
    end

    def process_ld(body:, content_type:, metadata:)
      parse_rdf(body: body, content_type: content_type, metadata: metadata)
    end

    def parse_rdf(body:, content_type:, metadata:)
      self.class.parse_rdf(body: body, content_type: content_type, metadata: metadata)
    end

    def self.parse_rdf(body:, content_type:, metadata:)
      @meta = metadata
      warn "1 PARSING RDF #{body}"
      unless body
        metadata.comments << "CRITICAL: The response message body component appears to have no content.\n"
        metadata.add_warning(['018', '', ''])
        return
      end
      warn "2 PARSING RDF #{body}"

      unless body.match(/\w/)
        metadata.comments << "CRITICAL: The response message body component appears to have no content.\n"
        metadata.add_warning(['018', '', ''])
        return
      end
      warn "3 PARSING RDF #{body} content type #{content_type.class}"

      rdfformat = RDF::Format.for(content_type: content_type)
      warn "FORMAT #{rdfformat}"
      warn "FORMAT #{RDF::Format.for(content_type: 'text/turtle')}"
      unless rdfformat
        metadata.comments << "CRITICAL: Found what appears to be RDF (sample:  #{body[0..300].delete!("\n")}), but it could not find a parser.  Please report this error, along with the GUID of the resource, to the maintainer of the system.\n"
        metadata.add_warning(['018', '', ''])
        return
      end

      graph = HarvesterTools::Cache.checkRDFCache(body: body)
      if graph.size > 0
        warn "\n\n\n unmarshalling graph from cache\n\ngraph size #{graph.size}\n\n"
        metadata.merge_rdf(graph.to_a)
      else
        warn "\n\n\nfound format #{rdfformat}\n\n"
        metadata.comments << "INFO: The response message body component appears to contain #{rdfformat}.\n"
        reader = ''
        begin
          reader = rdfformat.reader.new(body.force_encoding('UTF-8'))
        rescue Exception => e
          metadata.comments << "WARN: Though linked data was found, it failed to parse (Exception #{e}).  This likely indicates some syntax error in the data.  As a result, no metadata will be extracted from this message.\n"
          metadata.add_warning(['018', '', ''])
          return
        end

        begin
          if reader.size.zero?
            metadata.comments << "WARN: Though linked data was found, it failed to parse.  This likely indicates some syntax error in the data.  As a result, no metadata will be extracted from this message.\n"
            return
          end
          reader = rdfformat.reader.new(body) # have to re-read it here, but now its safe because we have already caught errors
          warn 'WRITING TO CACHE'
          HarvesterTools::Cache.writeRDFCache(reader: reader, body: body.force_encoding('UTF-8')) # write to the special RDF graph cache
          warn 'WRITING DONE'
          reader = rdfformat.reader.new(body.force_encoding('UTF-8'))  # frustrating that we cannot rewind!
          warn 'RE-READING DONE'
          metadata.merge_rdf(reader.to_a)
          warn 'MERGE DONE'
        rescue RDF::ReaderError => e
          metadata.comments << "CRITICAL: The Linked Data was malformed and caused the parser to crash with error message: #{e.message} ||  (sample of what was parsed:  #{body[0..300].delete("\n")})\n"
          warn "CRITICAL: The Linked Data was malformed and caused the parser to crash with error message: #{e.message} ||  (sample of what was parsed:  #{body[0..300].delete("\n")})\n"
          metadata.add_warning(['018', '', ''])
        rescue Exception => e
          metadata.comments << "CRITICAL: An unknown error occurred while parsing the (apparent) Linked Data (sample of what was parsed:  #{body[0..300].delete("\n")}).  Moving on...\n"
          warn "\n\nCRITICAL: #{e.inspect} An unknown error occurred while parsing the (apparent) Linked Data (full body:  #{body.force_encoding('UTF-8')}).  Moving on...\n"
          metadata.add_warning(['018', '', ''])
        end
      end
    end
  end
end
