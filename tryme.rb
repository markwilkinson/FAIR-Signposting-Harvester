require 'require_all'
warn `pwd`
require_all './lib/'

guid = 'https://w3id.org/a2a-fair-metrics/22-http-html-citeas-describedby-mixed/'
guid = 'https://doi.org/10.7910/DVN/Z2JD58'
links, metadata = HarvesterTools::Utils.resolve_guid(guid: guid)
meta = FspHarvester::Utils.gather_metadata_from_describedby_links(links: links, metadata: metadata)
puts meta.graph.triples