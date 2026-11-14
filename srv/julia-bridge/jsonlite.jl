"""
jsonlite.jl — a tiny stdlib-only JSON codec for the orchestrator sidecar.

WHY THIS EXISTS: the full `server.jl` uses JSON.jl + HTTP.jl, whose
pkgimages CANNOT compile in this container's Julia (1.11.1 segfaults
compiling a pkgimage for any registered package -- see the env note in
labs/prd-perf-bridges.md). That makes the orchestrator sidecar
unrunnable here and in CI, so the "live" path could never be exercised.
This module + `server_lite.jl` are the stdlib-only replacements: the
same HTTP API, no registered-package dependency, so the sidecar boots
anywhere Julia boots.

CODEGEN DISCIPLINE (this Julia build): the parser is written in a purely
functional index-passing style -- `_value(b, i) -> (value, next_index)`.
A `Ref` field access inside a loop MISCOMPILES to a segfault on this
build, exactly like the out-of-bounds read documented in propmath.jl.
Passing the index by value sidesteps it entirely.

Scope: enough JSON for the orchestrator's wire (flat objects, arrays,
strings, numbers, booleans, null). Not a general-purpose parser.
"""
module JsonLite

## ---- encoding ----------------------------------------------------------

"""Escape a string into a JSON string literal (including the quotes)."""
function esc(s::AbstractString)::String
    io = IOBuffer()
    print(io, '"')
    for c in s
        if c == '"'
            print(io, "\\\"")
        elseif c == '\\'
            print(io, "\\\\")
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\r'
            print(io, "\\r")
        elseif c == '\t'
            print(io, "\\t")
        elseif Int(c) < 0x20
            print(io, "\\u", lpad(string(Int(c); base = 16), 4, '0'))
        else
            print(io, c)
        end
    end
    print(io, '"')
    return String(take!(io))
end

encode(v::AbstractString) = esc(v)
encode(v::Bool) = v ? "true" : "false"
encode(::Nothing) = "null"
encode(v::Integer) = string(v)
encode(v::AbstractFloat) = isfinite(v) ? string(Float64(v)) : "null"
encode(v::AbstractVector) = "[" * join((encode(x) for x in v), ",") * "]"
function encode(v::AbstractDict)
    parts = String[]
    for (k, val) in v
        push!(parts, esc(string(k)) * ":" * encode(val))
    end
    return "{" * join(parts, ",") * "}"
end

## ---- decoding ----------------------------------------------------------
## Every `_x` returns a (value, next_index) pair. `b` is 1-based.

function parse_json(s::AbstractString)
    b = Vector{UInt8}(codeunits(s))
    v, _ = _value(b, _ws(b, 1))
    return v
end

function _ws(b::Vector{UInt8}, i::Int)
    n = length(b)
    while i <= n
        c = b[i]
        (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) || break
        i += 1
    end
    return i
end

function _value(b::Vector{UInt8}, i::Int)
    i = _ws(b, i)
    c = b[i]
    if c == 0x7b                      # {
        return _object(b, i)
    elseif c == 0x5b                  # [
        return _array(b, i)
    elseif c == 0x22                  # "
        return _string(b, i)
    elseif c == 0x74                  # t
        return (true, i + 4)
    elseif c == 0x66                  # f
        return (false, i + 5)
    elseif c == 0x6e                  # n
        return (nothing, i + 4)
    else
        return _number(b, i)
    end
end

function _object(b::Vector{UInt8}, i::Int)
    d = Dict{String,Any}()
    i += 1                            # consume '{'
    i = _ws(b, i)
    if b[i] == 0x7d                   # }
        return (d, i + 1)
    end
    while true
        i = _ws(b, i)
        k, i = _string(b, i)
        i = _ws(b, i)
        i += 1                        # consume ':'
        v, i = _value(b, i)
        d[k] = v
        i = _ws(b, i)
        c = b[i]
        i += 1                        # consume ',' or '}'
        c == 0x7d && break
    end
    return (d, i)
end

function _array(b::Vector{UInt8}, i::Int)
    a = Any[]
    i += 1                            # consume '['
    i = _ws(b, i)
    if b[i] == 0x5d                   # ]
        return (a, i + 1)
    end
    while true
        v, i = _value(b, i)
        push!(a, v)
        i = _ws(b, i)
        c = b[i]
        i += 1
        c == 0x5d && break
    end
    return (a, i)
end

function _string(b::Vector{UInt8}, i::Int)
    i += 1                            # consume opening quote
    io = IOBuffer()
    while true
        c = b[i]
        i += 1
        if c == 0x22                  # closing quote
            break
        elseif c == 0x5c              # backslash
            e = b[i]
            i += 1
            if e == 0x22
                print(io, '"')
            elseif e == 0x5c
                print(io, '\\')
            elseif e == 0x2f
                print(io, '/')
            elseif e == 0x6e
                print(io, '\n')
            elseif e == 0x72
                print(io, '\r')
            elseif e == 0x74
                print(io, '\t')
            elseif e == 0x62
                print(io, '\b')
            elseif e == 0x66
                print(io, '\f')
            elseif e == 0x75          # \uXXXX -> the raw code unit
                hex = String(b[i:i+3]); i += 4
                print(io, Char(parse(UInt16, hex; base = 16)))
            end
        else
            write(io, c)
        end
    end
    return (String(take!(io)), i)
end

function _number(b::Vector{UInt8}, i::Int)
    n = length(b)
    start = i
    isf = false
    while i <= n
        c = b[i]
        if c == 0x2e || c == 0x65 || c == 0x45       # . e E
            isf = true
            i += 1
        elseif (c >= 0x30 && c <= 0x39) || c == 0x2d || c == 0x2b
            i += 1
        else
            break
        end
    end
    tok = String(b[start:i-1])
    return (isf ? parse(Float64, tok) : parse(Int64, tok), i)
end

end # module JsonLite
