module FspHarvester
  class MetadataObject
    attr_accessor :hash, :graph, :comments, :links, :warnings, :guidtype, :full_response, :all_uris  # a hash of metadata # a RDF.rb graph of metadata  # an array of comments  # the type of GUID that was detected # will be an array of Net::HTTP::Response

    def initialize(_params = {}) # get a name from the "new" call, or set a default
      @hash = {}
      @graph = RDF::Graph.new
      @comments =  []
      @warnings =  []
      @full_response = []
      @links = []
      @all_uris = []
      @warn = File.read("./lib/warnings.json")
      @warn = JSON.parse(@warn)
    end

    def merge_hash(hash)
      # warn "\n\n\nIncoming Hash #{hash.inspect}"
      self.hash = self.hash.merge(hash)
    end

    def merge_rdf(triples) # incoming list of triples
      graph << triples
      graph
    end

    def rdf
      graph
    end

    def add_warning(warning)
      id = warning[0]
      url = warning[1]
      headers = warning[2]
      message = @warn[id]['message']
      linkout = @warn[id]['linkout']
      severity = @warn[id]['severity']
      self.warnings << {"id" => id, "message" => message, "severity" => severity, "linkout" => linkout, "processed_url" => url, "accept_headers": headers}
    end
  end

  class Cache
    def self.retrieveMetaObject(uri)
      filename = (Digest::MD5.hexdigest uri) + '_meta'
      warn "Checking Meta cache for #{filename}"
      if File.exist?("/tmp/#{filename}")
        warn 'FOUND Meta object in cache'
        meta = Marshal.load(File.read("/tmp/#{filename}"))
        warn 'Returning....'
        return meta
      end
      warn 'Meta objectNot Found in Cache'
      false
    end

    def self.cacheMetaObject(meta, uri)
      filename = (Digest::MD5.hexdigest uri) + '_meta'
      warn "in cacheMetaObject Writing to cache for #{filename}"
      File.open("/tmp/#{filename}", 'wb') { |f| f.write(Marshal.dump(meta)) }
    end

    def self.checkRDFCache(body: )
      fs = File.join('/tmp/', '*_graphbody')
      bodies = Dir.glob(fs)
      g = RDF::Graph.new
      bodies.each do |bodyfile|
        next unless File.size(bodyfile) == body.bytesize # compare body size
        next unless bodyfile.match(/(.*)_graphbody$/) # continue if there's no match

        filename = Regexp.last_match(1)
        warn "Regexp match for #{filename} FOUND"
        next unless File.exist?("#{filename}_graph") # @ get the associated graph file

        warn "RDF Cache File #{filename} FOUND"
        graph = Marshal.load(File.read("#{filename}_graph")) # unmarshal it
        graph.each do |statement|
          g << statement # need to do this because the unmarshalled object isn't entirely functional as an RDF::Graph object
        end
        warn "returning a graph of #{g.size}"
        break
      end
      # return an empty graph otherwise
      g
    end

    def self.writeRDFCache(reader:, body:)
      filename = Digest::MD5.hexdigest body
      graph = RDF::Graph.new
      reader.each_statement { |s| graph << s }
      warn "WRITING RDF TO CACHE #{filename}"
      File.open("/tmp/#{filename}_graph", 'wb') { |f| f.write(Marshal.dump(graph)) }
      File.open("/tmp/#{filename}_graphbody", 'wb') { |f| f.write(body) }
      warn "wrote RDF filename: #{filename}"
    end

    def self.checkCache(uri, headers)
      filename = Digest::MD5.hexdigest uri + headers.to_s
      warn "Checking Error cache for #{filename}"
      if File.exist?("/tmp/#{filename}_error")
        warn 'Error file found in cache... returning'
        return ['ERROR', nil, nil]
      end
      if File.exist?("/tmp/#{filename}_head") and File.exist?("/tmp/#{filename}_body")
        warn 'FOUND data in cache'
        head = Marshal.load(File.read("/tmp/#{filename}_head"))
        body = Marshal.load(File.read("/tmp/#{filename}_body"))
        all_uris = ''
        all_uris = Marshal.load(File.read("/tmp/#{filename}_uri")) if File.exist?("/tmp/#{filename}_uri")
        warn 'Returning....'
        return [head, body, all_uris]
      end
      warn 'Not Found in Cache'
    end

    def self.writeToCache(uri, headers, head, body, all_uris)
      filename = Digest::MD5.hexdigest uri + headers.to_s
      warn "in writeToCache Writing to cache for #{filename}"
      headfilename = filename + '_head'
      bodyfilename = filename + '_body'
      urifilename = filename + '_uri'
      File.open("/tmp/#{headfilename}", 'wb') { |f| f.write(Marshal.dump(head)) }
      File.open("/tmp/#{bodyfilename}", 'wb') { |f| f.write(Marshal.dump(body)) }
      File.open("/tmp/#{urifilename}", 'wb') { |f| f.write(Marshal.dump(all_uris)) }
    end

    def self.writeErrorToCache(uri, headers)
      filename = Digest::MD5.hexdigest uri + headers.to_s
      warn "in writeErrorToCache Writing error to cache for #{filename}"
      File.open("/tmp/#{filename}_error", 'wb') { |f| f.write('ERROR') }
    end
  end
end
