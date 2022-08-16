# FspHarvester

EXPERIMENTAL:  DO NOT USE

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'fsp_harvester'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install fsp_harvester

## Usage

```
require 'fsp_harvester'

ENV['EXTRUCT_COMMAND'] = "extruct"
ENV['RDF_COMMAND'] = "/home/user/.rvm/gems/ruby-3.0.0/bin/rdf" # kelloggs distiller
ENV['TIKA_COMMAND'] = "http://localhost:9998/meta" # assumes using the docker version of tika

# to only follow the FAIR signposting specification:
links, metadata = HarvesterTools::Utils.resolve_guid(guid: guid)

links.each do |link|
    puts link.href
    puts link.relation
end

# note, you don't need to catch the return value here.  The metadata object that is passed in will be modified
metadata = FspHarvester::Utils.gather_metadata_from_describedby_links(links: links, metadata: metadata)

linkeddata = metadata.graph
hashdata = metadata.hash
comments = metadata.comments
warnings = metadata.warnings

# if you want to try other things like content negotiation and "scraping" from HTML, do this:
# note, you don't need to catch the return value here.  The metadata object that is passed in will be modified
metadata = HarvesterTools::BruteForce.begin_brute_force(guid: guid, metadata: metadata)

linkeddata = metadata.graph
hashdata = metadata.hash
comments = metadata.comments
warnings = metadata.warnings

```


## Development


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/markwilkinson/fsp_harvester.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
