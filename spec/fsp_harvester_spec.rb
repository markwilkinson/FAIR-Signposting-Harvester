# frozen_string_literal: true
require_relative '../lib/fsp_harvester'
require_relative '../lib/fsp_metadata_harvester'
require_relative '../lib/fsp_metadata_parser'
require_relative '../lib/fsp_metadata_external_tools'

RSpec.describe FspHarvester do
  it 'has a version number' do
    expect(FspHarvester::VERSION).not_to be nil
  end

  it "should not find a graph of size 1 from benchmark 22" do
    guid = 'https://w3id.org/a2a-fair-metrics/22-http-html-citeas-describedby-mixed/'
    links, metadata = FspHarvester::Utils.resolve_guid(guid: guid)
    meta = FspHarvester::Utils.gather_metadata_from_describedby_links(links: links)
    expect(meta.graph.size).to eq 1
  end

end

