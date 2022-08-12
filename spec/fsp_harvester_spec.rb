# frozen_string_literal: true

require_relative '../lib/harvester'
require_relative 'spec_helper'


RSpec.describe FspHarvester do
  it 'has a version number' do
    expect(FspHarvester::VERSION).not_to be nil
  end

  it 'should find a graph of size 1 from benchmark 22' do
    guid = 'https://w3id.org/a2a-fair-metrics/22-http-html-citeas-describedby-mixed/'
    links, metadata = HarvesterTools::Utils.resolve_guid(guid: guid)
    meta = FspHarvester::Utils.gather_metadata_from_describedby_links(links: links, metadata: metadata)
    expect(meta.graph.size).to eq 1
  end

  it 'should find a graph from a DOI the hard way' do
    guid = '10.5061/dryad.6tb1702'
    _links, metadata = HarvesterTools::Utils.resolve_guid(guid: guid)
    meta = HarvesterTools::BruteForce.begin_brute_force(guid: guid, metadata: metadata)
    expect(meta.graph.size).to eq 55
    expect(meta.hash.size).to eq 0
    expect(meta.links.length).to eq 9
    warnings = extract_warning_ids(warnings: meta.warnings)
    expect(warnings.include? '003').to be true
  end
end
