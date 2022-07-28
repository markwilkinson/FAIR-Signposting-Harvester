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
      links = []
      if type
        links, @meta = resolve_url(url: url)
      else
        @meta.warnings << ['006', guid, '']
        @meta.comments << "FATAL: GUID type not recognized.\n"
      end
      [links, @meta]
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

    def self.resolve_url(url:, method: :get, nolinkheaders: false, header: ACCEPT_ALL_HEADER)
      @meta.guidtype = 'uri' if @meta.guidtype.nil?
      warn "\n\n FETCHING #{url} #{header}\n\n"
      response = FspHarvester::WebUtils.fspfetch(url: url, headers: header, method: method)
      warn "\n\n head #{response.headers.inspect}\n\n" if response

      unless response
        @meta.warnings << ['001', url, header]
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

      parser = LinkHeaders::Processor.new(default_anchor: @meta.finalURI.last)
      parser.extract_and_parse(response: response)
      factory = parser.factory # LinkHeaders::LinkFactory

      warn "\n\n length #{factory.all_links.length}\n\n"
      signpostingcheck(factory: factory)
    end

    def self.signpostingcheck(factory:)
      citeas = 0
      describedby = 0
      factory.all_links.each do |l|
        case l.relation
        when 'cite-as'
          citeas += 1
        when 'item'
          if !(l.respond_to? 'type')
            @meta.warnings << ['011', l.href, '']
            @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard, which encourages any item links to also have a 'type' attribute.\n"
          end
          type = l.type if l.respond_to? 'type'
          type = '*/*' unless type  # this becomes a frozen string
          header = { accept: type }
          response = FspHarvester::WebUtils.fspfetch(url: l.href, headers: header, method: :head)
          
          if response
            if response.headers[:content_type] and !(type == '*/*')
              rtype = type.gsub(%r{/}, "\/")   # because type is a frozen string
              rtype = rtype.gsub(/\+/, '.')
              typeregex = Regexp.new(type)
              if response.headers[:content_type].match(typeregex)
                warn response.headers[:content_type]
                warn typeregex.inspect
                @meta.comments << "INFO: item link responds according to Signposting specifications\n"
              else
                @meta.warnings << ['012', l.href, header]
                @meta.comments << "WARN: Content type of returned item link does not match the 'type' attribute\n"
              end
            else
              @meta.warnings << ['013', l.href, header]
              @meta.comments << "WARN: Content type of returned item link is not specified in response headers or cannot be matched against accept headers\n"
            end
          else
            @meta.warnings << ['014', l.href, header]
            @meta.comments << "WARN: item link doesn't resolve\n"
          end

        when 'describedby'
          describedby += 1
          if !(l.respond_to? 'type')
            @meta.warnings << ['005', l.href, '']
            @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard, which requires any describedby links to also have a 'type' attribute.\n"
          end
          type = l.type if l.respond_to? 'type'
          type = '*/*' unless type
          header = { accept: type }
          response = FspHarvester::WebUtils.fspfetch(url: l.href, headers: header, method: :head)
          if response
            if response.headers[:content_type] and !(type == '*/*')
              rtype = type.gsub(%r{/}, "\/")
              rtype = rtype.gsub(/\+/, '.')
              typeregex = Regexp.new(rtype)
              if response.headers[:content_type].match(typeregex)
                warn response.headers[:content_type]
                warn typeregex.inspect
                @meta.comments << "INFO: describedby link responds according to Signposting specifications\n"
              else
                @meta.warnings << ['009', l.href, header]
                @meta.comments << "WARN: Content type of returned describedby link does not match the 'type' attribute\n"
              end
            else
              @meta.warnings << ['010', l.href, header]
              @meta.comments << "WARN: Content type of returned describedby link is not specified in response headers or cannot be matched against accept headers\n"
            end
          else
            @meta.warnings << ['008', l.href, header]
            @meta.comments << "WARN: describedby link doesn't resolve\n"
          end
        end
      end
      if citeas > 1
        @meta.comments << "INFO: multiple cite-as links found. Checking for conflicts\n"
        citeas = check_for_citeas_conflicts(factory: factory) # this adds to the metadata objects if there are conflicts, returns the list of unique citeas (SHOULD ONLY BE ONE!)
      end

      unless citeas == 1 && describedby > 0
        @meta.warnings << ['004', '', '']
        @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard, which requires exactly one cite-as header, and at least one describedby header\n"
      end
      factory.all_links
    end

    def self.check_for_citeas_conflicts(factory:)
      @meta.comments << 'INFO: checking for conflicting cite-as links'
      citeas = []
      factory.all_links.each do |link|
        next unless link.relation == 'cite-as'

        @meta.comments << "INFO: Adding citeas #{link.href} to the testing queue."
        citeas << link.href
      end

      if citeas.uniq.length == 1
        @meta.comments << 'INFO: No conflicting cite-as links found.'
      else  # only one allowed!
        @meta.warnings << ['007', '', '']
        @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard: Found conflicting cite-as link headers\n"
      end
      citeas.uniq
    end
  end
end
