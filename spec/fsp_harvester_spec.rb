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
    expect(meta.graph.size).to eq 159
    expect(meta.hash.size).to eq 0
    expect(meta.links.length).to eq 13
    warnings = extract_warning_ids(warnings: meta.warnings)
    expect(warnings.include? '003').to be true
  end

  it 'should have a metadata object that has a date' do
    guid = '10.5061/dryad.6tb1702'
    _links, metadata = HarvesterTools::Utils.resolve_guid(guid: guid)
    expect(metadata.date == nil).to be false 
  end

  it 'should have a metadata object that has a date' do
    guid = '10.5061/dryad.6tb1702'
    _links, metadata = HarvesterTools::Utils.resolve_guid(guid: guid)
    expect(FspHarvester::RDF_COMMAND == nil).to be false
  end

  it 'it should find no conflict between content-type and what is returned; should find a conflict between the accept headers and what is returned, so throw a 023 error' do
    guid = 'https://go-fair.org'
    links, metadata = HarvesterTools::Utils.resolve_guid(guid: guid)
    meta = HarvesterTools::BruteForce.begin_brute_force(guid: guid, metadata: metadata, links: links )
    warnings = extract_warning_ids(warnings: meta.warnings)
    expect(warnings.include? '022').to be false
    expect(warnings.include? '023').to be true
  end

  it 'should accept a DOI' do
    guid = '10.5281/zenodo.3385997'
    links, metadata = HarvesterTools::Utils.resolve_guid(guid: guid)
    HarvesterTools::BruteForce.begin_brute_force(guid: guid, metadata: metadata, links: links)
    expect(metadata.graph.size > 1).to be true
  end

end
