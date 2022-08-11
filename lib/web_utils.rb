module HarvesterTools

  class WebUtils
    def self.fspfetch(url:, headers: ACCEPT_ALL_HEADER, method: :get, meta: HarvesterTools::MetadataObject.new)
      warn 'In fetch routine now.  '

      begin
        warn "executing call over the Web to #{url}"
        response = RestClient::Request.execute({
                                                method: method,
                                                url: url.to_s,
                                                # user: user,
                                                # password: pass,
                                                headers: headers
                                              })
        meta.all_uris |= [response.request.url]  # it's possible to call this method without affecting the metadata object being created by the harvester
        warn "starting URL #{url}"
        warn "final URL #{response.request.url}"
        warn "Response code #{response.code}"
        if response.code == 203 
          meta.warnings << ["002", url, headers]
          meta.comments << "WARN: Response is non-authoritative (HTTP response code: #{response.code}).  Headers may have been manipulated encountered when trying to resolve #{url}\n"
        end
        response
      rescue RestClient::ExceptionWithResponse => e
        warn "EXCEPTION WITH RESPONSE! #{e.response}\n#{e.response.headers}"
        meta.warnings << ["003", url, headers] 
        meta.comments << "WARN: HTTP error #{e} encountered when trying to resolve #{url}\n"
        if (e.response.code == 500 or e.response.code == 404)
          return false
        else
          e.response
        end
        # now we are returning the headers and body that were returned
      rescue RestClient::Exception => e
        warn "EXCEPTION WITH NO RESPONSE! #{e}"
        meta.warnings << ["003", url, headers]
        meta.comments << "WARN: HTTP error #{e} encountered when trying to resolve #{url}\n"
        false
        # now we are returning 'False', and we will check that with an \"if\" statement in our main code
      rescue Exception => e
        warn "EXCEPTION UNKNOWN! #{e}"
        meta.warnings << ["003", url, headers]
        meta.comments << "WARN: HTTP error #{e} encountered when trying to resolve #{url}\n"
        false
        # now we are returning 'False', and we will check that with an \"if\" statement in our main code
      end
    end
  end
end
