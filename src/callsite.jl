abstract type CallInfo; end

# Call could be resolved to a singular MI
struct MICallInfo <: CallInfo
    mi::MethodInstance
    rt
end
get_mi(ci::MICallInfo) = ci.mi

# Failed
struct FailedCallInfo <: CallInfo
    sig
    rt
end
get_mi(ci::FailedCallInfo) = error("MethodInstance extraction failed")

# Generated
struct GeneratedCallInfo <: CallInfo
    sig
    rt
end
get_mi(genci::GeneratedCallInfo) = error("Can't extract MethodInstance from call to generated functions")

struct MultiCallInfo <: CallInfo
    sig
    rt
    callinfos::Vector{CallInfo}
end
get_mi(ci::MultiCallInfo) = error("Can't extract MethodInstance from multiple call informations")

struct ThreadsCallInfo <: CallInfo
    ci::CallInfo
end
get_mi(thrci::ThreadsCallInfo) = get_mi(thrci.ci)

# Special handling for ReturnTypeCall
struct ReturnTypeCallInfo <: CallInfo
    called_mi::MICallInfo
end
get_mi(rtci::ReturnTypeCallInfo) = get_mi(rtci.called_mi)

struct Callsite
    id::Int # ssa-id
    info::CallInfo
end
get_mi(c::Callsite) = get_mi(c.info)

# Callsite printing
mutable struct TextWidthLimiter
    io::IO
    width::Int
    limit::Int
end
TextWidthLimiter(io::IO, limit) = TextWidthLimiter(io, 0, limit)
has_space(limiter::TextWidthLimiter, width::Int) = limiter.width + width < limiter.limit - 1
has_space(limiter::TextWidthLimiter, s) = has_space(limiter, textwidth(string(s)))
function Base.print(io::TextWidthLimiter, s::String)
    io.width == io.limit && return 0
    width = textwidth(s::String)
    if has_space(io, width)
        print(io.io, s)
        io.width += width
        return
    else
        for c in graphemes(s)
            cwidth = textwidth(c)
            if has_space(io, cwidth)
                print(io, c)
                io.width += cwidth
            else
                break
            end
        end
        print(io, '…')
        io.width += 1
    end
end

function __show_limited(limiter, name, tt, rt)
    if !has_space(limiter, name)
        print(limiter, '…')
        return
    end
    print(limiter, string(name))
    pstrings = map(string, tt)
    headstrings = map(x->isa(x, Union) ? string(x) : string(Base.unwrap_unionall(x).name), tt)
    print(limiter, "(")
    if length(pstrings) != 0
        # See if we have space to print all the parameters fully
        if has_space(limiter, sum(textwidth, pstrings) + 3*length(pstrings))
            print(limiter, join(map(T->string("::", T), pstrings), ","))
        # Alright, see if we at least have enough space for each head
        elseif has_space(limiter, sum(textwidth, headstrings) + 6*length(pstrings))
            print(limiter, join(map(T->string("::", T, "{…}"), headstrings), ","))
        # Fine, what about just indicating the number of arguments
        elseif has_space(limiter, 2*(length(tt)))
            print(limiter, join(map(T->"…", pstrings), ","))
        else
            print(limiter, "…")
        end
    end
    print(limiter, ")")

    # If we have space for the return type, print it
    rts = string(rt)
    if has_space(limiter, textwidth(rts)+2)
        print(limiter, string("::", rts))
    end
end

function show_callinfo(limiter, mici::MICallInfo)
    mi = mici.mi
    tt = mi.specTypes.parameters[2:end]
    name = mi.def.name
    rt = mici.rt
    __show_limited(limiter, name, tt, rt)
end

function show_callinfo(limiter, ci::Union{MultiCallInfo, FailedCallInfo, GeneratedCallInfo})
    types = ci.sig.parameters
    f = types[1]
    name = nameof(f)
    tt = types[2:end]
    rt = ci.rt
    __show_limited(limiter, name, tt, rt)
end

function Base.show(io::IO, c::Callsite)
    limit = get(io, :limit, false)
    cols = limit ? displaysize(io)[2] : typemax(Int)
    limiter = TextWidthLimiter(io, cols)
    print(limiter, string("%", c.id, " "))
    if isa(c.info, MICallInfo)
        print(limiter, " = invoke ")
        show_callinfo(limiter, c.info)
    elseif c.info isa MultiCallInfo || 
           c.info isa FailedCallInfo ||
           c.info isa GenFailedCallInfo
        # TODO differentiate by color
        print(limiter, " = call ")
        show_callinfo(limiter, c.info)
    elseif c.info isa ThreadsCallInfo
        print(limiter, " = thread_call < ")
        show_callinfo(limiter, c.info.ci)
        print(limiter, " >")
    elseif isa(c.info, ReturnTypeCallInfo)
        print(limiter, " = return_type < ")
        show_callinfo(limiter, c.info.called_mi)
        print(limiter, " >")
    end
end
