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
require_relative './metadata_harvester'
require_relative './metadata_object'
require_relative './fsp_harvester'
require_relative './harvester_utils'
require_relative './external_tools'
require_relative './metadata_parser'


module HarvesterTools
  class Error < StandardError
  end

  class Utils

    def self.resolve_guid(guid:)
      @meta = HarvesterTools::MetadataObject.new
      @meta.all_uris = [guid]
      type, url = convertToURL(guid: guid)
      links = Array.new
      if type
        links = resolve_url(url: url)
        @meta.links << links
      else
        @meta.add_warning(['006', guid, ''])
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
      GUID_TYPES.each do |type, regex|
        return type if regex.match(guid)
      end
      false
    end

    def self.resolve_url(url:, method: :get, nolinkheaders: false, header: ACCEPT_STAR_HEADER)
      @meta.guidtype = 'uri' if @meta.guidtype.nil?
      warn "\n\n FETCHING #{url} #{header}\n\n"
      response = HarvesterTools::WebUtils.fspfetch(url: url, headers: header, method: method, meta: @meta)
      warn "\n\n head #{response.headers.inspect}\n\n" if response

      unless response
        @meta.add_warning(['001', url, header])
        @meta.comments << "WARN: Unable to resolve #{url} using HTTP Accept header #{header}.\n"
        return []
      end

      @meta.comments << "INFO: following redirection using this header led to the following URL: #{@meta.all_uris.last}.  Using the output from this URL for the next few tests..."
      @meta.full_response << response.body

      links = process_link_headers(response: response) unless nolinkheaders
      links
    end

    def self.process_link_headers(response:)
      warn "\n\n parsing #{response.headers}\n\n"

      parser = LinkHeaders::Processor.new(default_anchor: @meta.all_uris.last)
      parser.extract_and_parse(response: response)
      factory = parser.factory # LinkHeaders::LinkFactory

      warn "\n\n length bfore #{factory.all_links.length}\n\n"
      signpostingcheck(factory: factory)
      warn "\n\n length aftr #{factory.all_links.length}\n\n"
      warn "\n\n links #{factory.all_links}\n\n"
      factory.all_links
    end
  end
end
