
require_relative 'harvester'
module FspHarvester
  class Error < StandardError
  end

  class Utils

    def self.gather_metadata_from_describedby_links(links: [], metadata: HarvesterTools::MetadataObject.new) # meta should have already been created by resolve+guid, but maybe not
      @meta = metadata
      db = []
      links.each do |l|
        db << l if l.relation == 'describedby'
      end
      HarvesterTools::MetadataHarvester.extract_metadata(links: db, metadata: @meta)  # everything is gathered into the @meta metadata object
      @meta
    end

    def self.signpostingcheck(factory:, metadata: HarvesterTools::MetadataObject.new)
      @meta = metadata
      citeas = Array.new
      describedby = Array.new
      item = Array.new
      types = Array.new

      factory.all_links.each do |l|
        case l.relation
        when 'cite-as'
          citeas << l
        when 'item'
          item << l
        when 'describedby'
          describedby << l
        when 'type'
          types << l
        end
      end

      check_describedby_rules(describedby: describedby)
      check_item_rules(item: item)

      if citeas.length > 1
        warn "INFO: multiple cite-as links found. Checking for conflicts\n"
        @meta.comments << "INFO: multiple cite-as links found. Checking for conflicts\n"
        citeas = check_for_citeas_conflicts(citeas: citeas) # this adds to the metadata objects if there are conflicts, returns the list of unique citeas (SHOULD ONLY BE ONE!)
      end

      unless citeas.length == 1 && describedby.length > 0
        @meta.add_warning(['004', '', ''])
        @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard, which requires exactly one cite-as header, and at least one describedby header\n"
      end

      unless types.length >=1
        @meta.add_warning(['015', '', ''])
        @meta.comments << "WARN: The resource does not follow the FAIR Signposting standard, which requires one or two 'type' link headers\n"
      end
    end
  end
end
