# frozen_string_literal: true

require_relative 'fsp_harvester/version'
require 'json/ld'
require 'json/ld/preloaded'
require 'json'
require 'linkheaders/processor'
require 'addressable'
require 'tempfile'
require 'xmlsimple'
require 'nokogiri'
require 'parseconfig'
require 'rest-client'
require 'cgi'
require 'digest'
require 'open3'
require 'metainspector'
require 'rdf/xsd'
require_relative './metadata_object'
require_relative './constants'
require_relative './web_utils'
require_relative './signposting_tests'
require_relative './fsp_metadata_harvester'
require_relative './fsp_metadata_parser'


module FspHarvester
  class Error < StandardError
  end

  class Utils
    # @@distillerknown = {} # global, hash of sha256 keys of message bodies - have they been seen before t/f
    # @warnings = JSON.parse(File.read("warnings.json"))
    

    def self.resolve_guid(guid:)
      @meta = FspHarvester::MetadataObject.new
      @meta.finalURI = [guid]
      type, url = convertToURL(guid: guid)
      links = Array.new
      if type
        links = resolve_url(url: url)
      else
        @meta.warnings << ['006', guid, '']
        @meta.comments << "FATAL: GUID type not recognized.\n"
      end
      [links, @meta]
    end

    def self.gather_metadata_from_describedby_links(links: [], metadata: FspHarvester::MetadataObject.new) # meta should have already been created by resolve+guid, but maybe not
      @meta = metadata
      db = []
      links.each do |l|
        db << l if l.relation == 'describedby'
      end
      FspHarvester::MetadataHarvester.extract_metadata(links: db, metadata: @meta)  # everything is gathered into the @meta metadata object
      @meta
    end

    def self.convertToURL(guid:)
      GUID_TYPES.each do |k, regex|
        if k == 'inchi' and regex.match(guid)
          return 'inchi', "https://pubchem.ncbi.nlm.nih.gov/rest/rdf/inchikey/#{guid}"
        elsif k == 'handle1' and regex.match(guid)
          return 'handle', "http://hdl.handle.net/#{guid}"
        elsif k == 'handle2' and regex.match(guid)
          return 'handle', "http://hdl.handle.net/#{guid}"
        elsif k == 'uri' and regex.match(guid)
          return 'uri', guid
        elsif k == 'doi' and regex.match(guid)
          return 'doi', "https://doi.org/#{guid}"
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

    def self.resolve_url(url:, method: :get, nolinkheaders: false, header: ACCEPT_STAR_HEADER)
      @meta.guidtype = 'uri' if @meta.guidtype.nil?
      warn "\n\n FETCHING #{url} #{header}\n\n"
      response = FspHarvester::WebUtils.fspfetch(url: url, headers: header, method: method)
      warn "\n\n head #{response.headers.inspect}\n\n" if response

      unless response
        @meta.warnings << ['001', url, header]
        @meta.comments << "WARN: Unable to resolve #{url} using HTTP Accept header #{header}.\n"
        return []
      end

      @meta.comments << "INFO: following redirection using this header led to the following URL: #{@meta.finalURI.last}.  Using the output from this URL for the next few tests..."
      @meta.full_response << response.body

      links = process_link_headers(response: response) unless nolinkheaders
      links
    end

    def self.process_link_headers(response:)
      warn "\n\n parsing #{response.headers}\n\n"

      parser = LinkHeaders::Processor.new(default_anchor: @meta.finalURI.last)
      parser.extract_and_parse(response: response)
      factory = parser.factory # LinkHeaders::LinkFactory

      warn "\n\n length bfore #{factory.all_links.length}\n\n"
      signpostingcheck(factory: factory)
      warn "\n\n length aftr #{factory.all_links.length}\n\n"
      warn "\n\n links #{factory.all_links}\n\n"
      factory.all_links
    end

    def self.signpostingcheck(factory:)
      citeas = Array.new
      describedby = Array.new
      item = Array.new
      types = Array.new

      factory.all_links.each do |l|
        case l.relation
        when 'cite-as'
          citeas << l
        when 'item'
          item << l
        when 'describedby'
          describedby << l
        when 'type'
          types << l
        end
      end

      check_describedby_rules(describedby: describedby)
      check_item_rules(item: item)

      uniqueciteas = Array.new
      if citeas.length > 1
        warn "INFO: multiple cite-as links found. Checking for conflicts\n"
        @meta.comments << "INFO: multiple cite-as links found. Checking for conflicts\n"
        uniqueciteas = check_for_citeas_conflicts(citeas: citeas) # this adds to the metadata objects if there are conflicts, returns the list of unique citeas (SHOULD ONLY BE ONE!)
      end

      unless uniqueciteas == 1 && describedby.length > 0
        @meta.warnings << ['004', '', '']
        @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard, which requires exactly one cite-as header, and at least one describedby header\n"
      end

      unless types.length >=1
        @meta.warnings << ['015', '', '']
        @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard, which requires one or two 'type' link headers\n"
      end
    end
  end
end
