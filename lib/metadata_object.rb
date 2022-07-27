module FspHarvester
  class MetadataObject
    attr_accessor :hash, :graph, :comments, :warnings, :guidtype, :full_response, :finalURI  # a hash of metadata # a RDF.rb graph of metadata  # an array of comments  # the type of GUID that was detected # will be an array of Net::HTTP::Response

    def initialize(_params = {}) # get a name from the "new" call, or set a default
      @hash = {}
      @graph = RDF::Graph.new
      @comments =  []
      @warnings =  []
      @full_response = []
      @finalURI = []
    end

    def merge_hash(hash)
      # $stderr.puts "\n\n\nIncoming Hash #{hash.inspect}"
      self.hash = self.hash.merge(hash)
    end

    def merge_rdf(triples)  # incoming list of triples
      graph << triples
      graph
    end

    def rdf
      graph
    end
  end
end
