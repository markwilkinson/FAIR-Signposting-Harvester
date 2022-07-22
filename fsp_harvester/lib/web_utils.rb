module FspHarvester

  class WebUtils
    def self.fspfetch(url:, headers: ACCEPT_ALL_HEADER)  # we will try to retrieve turtle whenever possible
      warn 'In fetch routine now.  '

      begin
        warn "executing call over the Web to #{url}"
        response = RestClient::Request.execute({
                                                method: :get,
                                                url: url.to_s,
                                                # user: user,
                                                # password: pass,
                                                headers: headers
                                              })
        @meta.finalURI |= [response.request.url] if @meta  # it's possible to call this method without affecting the metadata object being created by the harvester
        warn "There was a response to the call #{url}"
        warn "There was a response to the call #{response.request.url}"
        warn "Response code #{response.code}"
        if response.code == 203 && @meta
          @meta.warnings << ["002", url, headers]
          @meta.comments << "WARN: Response is non-authoritative (HTTP response code: #{response.code}).  Headers may have been manipulated encountered when trying to resolve #{url}\n"
        end
        response
      rescue RestClient::ExceptionWithResponse => e
        warn "EXCEPTION WITH RESPONSE! #{e.response}\n#{e.response.headers}"
        @meta.warnings << ["003", url, headers] if @meta
        @meta.comments << "WARN: HTTP error #{e} encountered when trying to resolve #{url}\n" if @meta
        if e.response.code == 500
          return false
        else
          e.response
        end
        # now we are returning the headers and body that were returned
      rescue RestClient::Exception => e
        warn "EXCEPTION WITH NO RESPONSE! #{e}"
        @meta.warnings << ["003", url, headers] if @meta
        @meta.comments << "WARN: HTTP error #{e} encountered when trying to resolve #{url}\n" if @meta
        false
        # now we are returning 'False', and we will check that with an \"if\" statement in our main code
      rescue Exception => e
        warn "EXCEPTION UNKNOWN! #{e}"
        @meta.warnings << ["003", url, headers] if @meta
        @meta.comments << "WARN: HTTP error #{e} encountered when trying to resolve #{url}\n" if @meta
        false
        # now we are returning 'False', and we will check that with an \"if\" statement in our main code
      end
    end
  end
end
