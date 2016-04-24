__precompile__()

#=
RequestsCache
A cache mechanism for [Request.jl](https://github.com/JuliaWeb/Requests.jl)

Based on JLD https://github.com/JuliaLang/JLD.jl

Inspired by [requests-cache](http://requests-cache.readthedocs.org/).

=#

module RequestsCache

    #import Dates
    import Base: read
    import Requests: do_request
    import URIParser: URI
    import HttpCommon: Response
    import JLD: jldopen, write

    immutable PreparedQuery
        verb::ASCIIString
        uri::URI
        args::Array{Any,1}
    end
    Base.hash(q::PreparedQuery, h::UInt) = hash(string(q.verb), hash(string(q.uri), hash(q.args)))

    function create_query(verb::ASCIIString, uri::URI; args...)
        return PreparedQuery(verb, uri, args)
    end
    create_query(verb::ASCIIString, uri::AbstractString; args...) = create_query(verb, URI(uri); args...)

    immutable CachedSessionType
        cache_name::AbstractString
        backend::AbstractString
        expire_after
    end

    function CachedSession(; cache_name="cache.jld", backend="jld", expire_after=Base.Dates.Day(1))
        if backend == "jld"
            CachedSessionType(cache_name, backend, expire_after)
        else
            error("'$(backend)' is not a supported backend")
        end
    end

    function Session()
        CachedSessionType("", "", Base.Dates.Day(0))
    end

    immutable CachedResponse
        dt_stored::DateTime
        response::Response
    end

    function UTCnow()
        Dates.now(Dates.UTC)
    end

    function write(session::CachedSessionType, prepared_query::PreparedQuery, response::Response)
        backend = lowercase(session.backend)
        filename = session.cache_name
        key = string(hash(prepared_query))
        cached_response = CachedResponse(UTCnow(), response)
        if backend == "jld"
            jldopen(filename, "w") do file
                println("Write $cached_response with key='$key' to '$filename'")
                write(file, key, cached_response)
            end
        else
            error("'$(backend)' is not a supported backend for writing")
        end
    end

    function read(session::CachedSessionType, prepared_query::PreparedQuery)
        backend = lowercase(session.backend)
        filename = session.cache_name
        key = string(hash(prepared_query))
        if backend == "jld"
            retrieved_response = jldopen(filename, "r") do file
                println("Read key='$key' from '$filename'")
                read(file, key)
            end
            return retrieved_response
        else
            error("'$(backend)' is not a supported backend for reading")
        end        
    end

    function execute_remote(prepared_query::PreparedQuery)
        println("execute_remote $(prepared_query.verb) $(prepared_query.uri) $(prepared_query.args)")
        #prepared_query.verb(string(prepared_query.uri); prepared_query.args...)
        verb = uppercase(string(prepared_query.verb))
        do_request(prepared_query.uri, verb; prepared_query.args...)
    end

    function execute_local(session::CachedSessionType, prepared_query::PreparedQuery)
        println("execute_local")
        try
            retrieved_response = read(session, prepared_query)
            dt_expiration = retrieved_response.dt_stored + session.expire_after
            if dt_expiration > UTCnow()
                println("Not expired")
                return retrieved_response.response
            else
                println("Cache expired - update is necessary")
                response = execute_remote(prepared_query)
                write(session, prepared_query, response)
            end
        catch LoadError
            println("LoadError $session")
            response = execute_remote(prepared_query)
            write(session, prepared_query, response)
            println("Write to $session")
            return response
        end
    end

    function execute(prepared_query::PreparedQuery; session=Session())
        println(session)
        if session.backend == ""
            execute_remote(prepared_query)
        else
            execute_local(session, prepared_query)
        end
    end

    for f in [:get, :post, :put, :delete, :head,
              :trace, :options, :patch, :connect]
        f_str = uppercase(string(f))
        #f_stream = symbol(string(f, "_streaming"))
        @eval begin
            function ($f)(session::CachedSessionType, uri::URI, data::AbstractString; headers::Dict=Dict())
                #do_request(uri, $f_str; data=data, headers=headers)
                prepared_query = create_query($f_str, uri; data=data, headers=headers)
                response = execute(prepared_query; session=session)
            end

            ($f)(session::CachedSessionType, uri::AbstractString; args...) = ($f)(session, URI(uri); args...)
            function ($f)(session::CachedSessionType, uri::URI; args...)
                #do_request(uri, $f_str; args...)
                prepared_query = create_query($f_str, uri; args...)
                response = execute(prepared_query; session=session)
            end

            #function ($f_stream)(uri::URI, data::AbstractString; headers::Dict=Dict())
            #    do_stream_request(uri, $f_str; data=data, headers=headers)
            #end
            #($f_stream)(uri::AbstractString; args...) = ($f_stream)(URI(uri); args...)
            #($f_stream)(uri::URI; args...) = do_stream_request(uri, $f_str; args...)
        end
    end

end


