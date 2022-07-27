# frozen_string_literal: true

require_relative "fsp_harvester/version"
require "json/ld"
require "json/ld/preloaded"
require "json"
require "linkheader/processor"
require "addressable"
require "tempfile"
require "xmlsimple"
require "nokogiri"
require "parseconfig"
require "rest-client"
require "cgi"
require "digest"
require "open3"
require "metainspector"
require "rdf/xsd"
require_relative "./metadata_object"
require_relative "./constants"
require_relative "./web_utils"

module FspHarvester
  class Error < StandardError
  end

  class Utils
    # @@distillerknown = {} # global, hash of sha256 keys of message bodies - have they been seen before t/f
    # @warnings = JSON.parse(File.read("warnings.json"))
    @meta = FspHarvester::MetadataObject.new

    def self.resolve_guid(guid:)
      @meta.finalURI = [guid]
      type, url = convertToURL(guid: guid)
      links = Array.new
      unless type
        @meta.warnings << ["006", guid, ""]
        @meta.comments << "FATAL: GUID type not recognized.\n"
      else
        links, @meta = resolve_url(url: url)
      end
      [links, @meta]
    end

    def self.convertToURL(guid:)
      GUID_TYPES.each do |k, regex|
        if k == "inchi" and regex.match(guid)
          return "inchi", "https://pubchem.ncbi.nlm.nih.gov/rest/rdf/inchikey/#{guid}"
        elsif k == "handle1" and regex.match(guid)
          return "handle", "http://hdl.handle.net/#{guid}"
        elsif k == "handle2" and regex.match(guid)
          return "handle", "http://hdl.handle.net/#{guid}"
        elsif k == "uri" and regex.match(guid)
          return "uri", guid
        elsif k == "doi" and regex.match(guid)
          return "doi", "https://doi.org/#{guid}"
        end
      end
      [nil, nil]
    end

    def self.typeit(guid:)
      Utils::GUID_TYPES.each do |type, regex|
        return type if regex.match(guid)
      end
      false
    end

    def self.resolve_url(url:, nolinkheaders: false, header: ACCEPT_ALL_HEADER)
      @meta.guidtype = "uri" if @meta.guidtype.nil?
      warn "\n\n FETCHING #{url} #{header}\n\n"
      response = FspHarvester::WebUtils.fspfetch(url: url, headers: header)
      warn "\n\n head #{response.headers.inspect}\n\n"

      unless response
        @meta.warnings << ["001", url, header]
        @meta.comments << "WARN: Unable to resolve #{url} using HTTP Accept header #{header}.\n"
        return [[], @meta]
      end

      @meta.comments << "INFO: following redirection using this header led to the following URL: #{@meta.finalURI.last}.  Using the output from this URL for the next few tests..."
      @meta.full_response << response.body

      links = process_link_headers(response: response) unless nolinkheaders
      [links, @meta]
    end

    def self.process_link_headers(response:)
      warn "\n\n parsing #{response.headers}\n\n"

      parser = LinkHeader::Parser.new(default_anchor: @meta.finalURI.last)
      parser.extract_and_parse(response: response)
      factory = parser.factory  # LinkHeader::LinkFactory

      citeas = 0
      describedby = 0
      warn "\n\n length #{factory.all_links.length}\n\n"

      factory.all_links.each do |l|
        case l.relation
        when "cite-as"
          citeas += 1
        when "describedby"
          describedby += 1
          unless l.respond_to? "type"
            @meta.warnings << ["005", l.url, ""]
            @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard, which requires any describedby links to also have a 'type' attribute\n"    
          end
        end
      end
      if citeas > 1
        self.check_for_conflicts(factory: factory)  # this merelty adsds to the metadata objects if there are conflicts
      end

      unless citeas == 1 && describedby > 0
        @meta.warnings << ["004", "", ""]
        @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard, which requires exactly one cite-as header, and at least one describedby header\n"
      end
      factory.all_links
    end

    def self.check_for_conflicts(factory:) # incoming: {"link1" => {"sectiontype1" => value, "sectiontype2" => value2}}
      @meta.comments << "INFO: checking for conflicting cite-as links"
      citeas = Array.new
      factory.all_links.each do |link|
        next unless link.relation == 'cite-as'
        citeas << link.href
      end
      unless citeas == citeas.uniq
        @meta.warnings << ["007", url, header]
        @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard: Found conflicting cite-as link headers\n"
      else
        @meta.comments << "INFO: No conflicting cite-as links found."
      end
    end
  end
end
