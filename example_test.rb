require 'cgi'
require 'json'
require 'uri'
require 'rdf'
require 'rdf/turtle'
require 'sparql'
require 'fsp_harvester'

def testGUID(guid:)


  links, metadata = FspHarvester::Utils.resolve_guid(guid: guid)

  warn links  

  if metadata.guidtype == 'unknown'
    metadata.comments << "FAILURE: The identifier #{guid} did not match any known identification system.\n"
  else
    metadata.comments << "SUCCESS: The identifier #{guid} matched known GUID type system #{metadata.guidtype}.\n"
  end
  return metadata.comments
end

guid = ARGV[0]
response = testGUID(guid: guid)

warn response
