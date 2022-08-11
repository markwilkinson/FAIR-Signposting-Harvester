require_relative '../lib/harvester'
require_relative 'spec_helper'
Type = String
  
describe Type do
  context "When testing the FSP Harvester type functions" do

    it 'should fail to find at least one type in https://w3id.org/a2a-fair-metrics/03-http-citeas-only/' do
      guid = 'https://w3id.org/a2a-fair-metrics/03-http-citeas-only/'
      links, metadata = HarvesterTools::Utils.resolve_guid(guid: guid)
      hrefs = extract_type_links(links: links)
      expect(hrefs.length >= 1).to be false
    end

    it 'should report warning 015 for https://w3id.org/a2a-fair-metrics/03-http-citeas-only/' do
      guid = 'https://w3id.org/a2a-fair-metrics/03-http-citeas-only/'
      links, metadata = HarvesterTools::Utils.resolve_guid(guid: guid)
      ids = extract_warning_ids(warnings: metadata.warnings)
      expect(ids.include? '015').to be true
    end

    # https://s11.no/2022/a2a-fair-metrics/23-http-citeas-describedby-item-license-type-author/
    it 'should find at least one type in https://s11.no/2022/a2a-fair-metrics/23-http-citeas-describedby-item-license-type-author/' do
      guid = 'https://s11.no/2022/a2a-fair-metrics/23-http-citeas-describedby-item-license-type-author/'
      links, metadata = HarvesterTools::Utils.resolve_guid(guid: guid)
      hrefs = extract_type_links(links: links)
      expect(hrefs.length >= 1).to be true
    end
  end
end
