# frozen_string_literal: true

require_relative '../lib/harvester'

ENV['EXTRUCT_COMMAND'] = 'extruct'
ENV['RDF_COMMAND'] = 'rdf'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  # config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

def extract_warning_ids(warnings:)
  warn_ids = []
  warnings.each do |warn|
    warn_ids << warn["id"]
  end
  warn_ids
end

def extract_citeas_hrefs(links:)
  hrefs = []
  links.each do |l|
    hrefs << l.href if l.relation == 'cite-as'
  end
  hrefs
end

def extract_describedby_hrefs(links:)
  hrefs = []
  links.each do |l|
    hrefs << l.href if l.relation == 'describedby'
  end
  hrefs
end

def extract_describedby_profiles(links:)
  profiles = []
  links.each do |l|
    profiles << l.profile if l.relation == 'describedby' and l.respond_to? 'profile'
  end
  profiles
end

def extract_item_hrefs(links:)
  hrefs = []
  links.each do |l|
    hrefs << l.href if l.relation == 'item'
  end
  hrefs
end

def extract_item_types(links:)
  types = []
  links.each do |l|
    types << l.type if l.relation == 'item' and l.respond_to? 'type'
  end
  types
end

def extract_type_links(links:)
  types = []
  links.each do |l|
    types << l.href if l.relation == 'type'
  end
  types
end
