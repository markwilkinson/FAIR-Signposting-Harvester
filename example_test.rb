# frozen string literal = false
require 'cgi'
require 'json'
require 'uri'
require 'rdf'
require 'rdf/turtle'
require 'sparql'
require 'fsp_harvester'

def test_guid(guid:)
  _links, metadata = FspHarvester::Utils.resolve_guid(guid: guid)  # [LinkHeader::Link], FspHarvester::MetadataObject

  metadata.comments << if metadata.guidtype == 'unknown'
                         "FAILURE: The identifier #{guid} did not match any known identification system.\n"
                       else
                         "SUCCESS: The identifier #{guid} matched known GUID type system #{metadata.guidtype}.\n"
                       end
  metadata.comments
end

guid = ARGV[0] || 'https://s11.no/2022/a2a-fair-metrics/07-http-describedby-citeas-linkset-json/'
response = test_guid(guid: guid)

puts response
