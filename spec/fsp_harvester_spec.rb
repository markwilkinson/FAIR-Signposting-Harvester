# frozen_string_literal: true
require_relative '../lib/harvester'

RSpec.describe FspHarvester do
  it 'has a version number' do
    expect(FspHarvester::VERSION).not_to be nil
  end

  it "should find a graph of size 1 from benchmark 22" do
    guid = 'https://w3id.org/a2a-fair-metrics/22-http-html-citeas-describedby-mixed/'
    links, metadata = HarvesterTools::Utils.resolve_guid(guid: guid)
    meta = FspHarvester::Utils.gather_metadata_from_describedby_links(links: links, metadata: metadata)
    expect(meta.graph.size).to eq 1
  end

end

