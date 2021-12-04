module SourceTools

import ..Hygiene: @nolinenodes, hasnode

mutable struct Source
    __source__ :: LineNumberNode
    text       :: String
    ix         :: Int
end

"""
    HAML.SourceTools.Source("/path/to/file.hamljl")
    HAML.SourceTools.Source(::LineNumberNode, ::AbstractString)

Represent Julia-flavoured HAML source code that can be parsed using
the `Meta.parse` function.
"""
Source(__source__::LineNumberNode, text::AbstractString) = Source(__source__, text, 1)
Source(path::AbstractString) = Source(LineNumberNode(1, Symbol(path)), read(path, String), 1)

function linecol(s::Source, ix::Int=s.ix)
    line, col = 1, 1
    i = firstindex(s.text)
    while i < ix
        if s.text[i] == '\n'
            line += 1
            col = 1
        else
            col += 1
        end
        i = nextind(s.text, i)
    end
    return line, col, LineNumberNode(line + s.__source__.line - 1, s.__source__.file)
end

Base.LineNumberNode(s::Source, ix::Int=s.ix) = linecol(s, ix)[3]

Base.getindex(s::Source, ix::Int) = s.text[s.ix + ix - 1]
Base.getindex(s::Source, ix::AbstractRange) = SubString(s.text, s.ix .+ ix .- 1)

Base.isempty(s::Source) = s.ix > length(s.text)

Base.match(needle::Regex, haystack::Source, args...; kwds...) = match(needle, SubString(haystack.text, haystack.ix), args...; kwds...)

function _replace_dummy_linenodes(expr, origin::LineNumberNode)
    if !hasnode(:macrocall, expr)
        return expr
    elseif expr isa Expr && expr.head == :macrocall && expr.args[2].file == :none
        delta = expr.args[2].line - 1
        line = LineNumberNode(origin.line + delta, origin.file)
        return Expr(:macrocall, expr.args[1], line, expr.args[3:end]...)
    elseif expr isa Expr
        args = Vector{Any}(undef, length(expr.args))
        map!(a -> _replace_dummy_linenodes(a, origin), args, expr.args)
        return Expr(expr.head, args...)
    else
        return expr
    end
end

function parse_juliacode(s::Source; kwds...)
    expr, offset = Base.Meta.parse(s.text, s.ix; kwds...)
    expr = _replace_dummy_linenodes(expr, LineNumberNode(s))
    advance!(s, offset - s.ix)
    expr
end

function parse_juliacode(s::Source, snippet::AbstractString, snippet_location::SubString = snippet; raise=true, with_linenode=true, kwds...)
    @assert snippet_location.string == s.text
    ix = snippet_location.offset + 1
    expr = Base.Meta.parse(snippet; raise=false, kwds...)
    loc = LineNumberNode(s, ix)
    expr = _replace_dummy_linenodes(expr, loc)
    if raise && expr isa Expr && expr.head == :error
        error(s, ix, expr.args[1])
    end
    if expr isa Expr && expr.head == :incomplete
        return expr
    end
    return with_linenode ? Expr(:block, loc, expr) : expr
end

struct ParseError <: Exception
    source :: Source
    error  :: Any
end

linecol(p::ParseError) = linecol(p.source)
linecol(p::LoadError) = linecol(p.error.source)

function Base.show(io::IO, err::ParseError)
    line, col, linenode = linecol(err)
    lines = split(err.source.text, "\n")
    source_snippet = join(lines[max(1, line-1) : line], "\n")
    point_at_column = " " ^ (col - 1) * "^^^ here"
    message = """
    $(err.error) at $(linenode.file):$(linenode.line):
    $source_snippet
    $point_at_column
    """
    print(io, message)
end

Base.error(s::Source, msg) = error(s, s.ix, msg)
Base.error(s::Source, ix::Int, msg) = throw(ParseError(Source(s.__source__, s.text, ix), msg))

function advance!(s::Source, delta)
    s.ix += delta
end

function capture(haystack, needle)
    # eval into Main to avoid Revise.jl compaining about eval'ing "into
    # the closed module HAML.Parse".
    r = Base.eval(Main, needle)
    hay = esc(haystack)
    captures = Base.PCRE.capture_names(r.regex)
    if !isempty(captures)
        maxix = maximum(keys(captures))
        symbols = map(1:maxix) do ix
            capturename = get(captures, ix, "_")
            esc(Symbol(capturename))
        end
        assign = :( ($(symbols...),) = m.captures )
    else
        assign = :( )
    end
    return quote
        m = match($r, $hay.text, $hay.ix, Base.PCRE.ANCHORED)
        if isnothing(m)
            false
        else
            $assign
            advance!($hay, length(m.match))
            true
        end
    end
end

macro capture(haystack, needle)
    return capture(haystack, needle)
end

macro mustcapture(haystack, msg, needle)
    return quote
        succeeded = $(capture(haystack, needle))
        succeeded || error($(esc(haystack)), $msg)
    end
end

function parse_contentline(s::Source)
    exprs = []
    newline = ""
    while !isempty(s)
        @mustcapture s "Expecting literal content or interpolation" r"""
            (?<literal>[^\\\$\v]*)
            (?<nextchar>[\\\$\v]?)
        """mx
        if nextchar == "\\"
            @mustcapture s "Expecting escaped character" r"(?<escaped_char>.)"
            if escaped_char == "\\" || escaped_char == "\$"
                literal *= escaped_char
            else
                literal *= nextchar * escaped_char
            end
        end
        !isempty(literal) && push!(exprs, literal)
        if nextchar == "\$"
            expr = esc(parse_juliacode(s, greedy=false))
            push!(exprs, expr)
        end
        if nextchar != "\\" && nextchar != "\$"
            @mustcapture s "Expected vertical whitespace" r"(?<ws>(?:\h*(?:\v|$))*)"
            newline = nextchar * ws
            break
        end
    end
    expr = isempty(exprs) ? nothing : Expr(:hamloutput, exprs...)
    return expr, newline
end

function parse_expressionline(s::Source; with_linenode=true, kwds...)
    loc = LineNumberNode(s)
    startix = s.ix
    while !isempty(s)
        @mustcapture s "Expecting Julia expression" r"""
            [^'",\#\v]*
            (?:
                (?=(?<begin_of_string_literal>['"]))
                |
                (?<comma_before_end_of_line>
                    ,
                    \h*
                    (?:\#.*)?
                    $\v?
                )
                |
                (?<just_a_comma>,)
                |
                (?<comment>\#.*$)
                |
                (?<newline>$(?:\h*(?:\v|$))*)
            )
        """mx
        if !isnothing(begin_of_string_literal)
            # advance the location in s by the run length of the string.
            # Julia takes care of escaping etc. We will eventually parse
            # the whole thing again in the branch below.
            parse_juliacode(s; greedy=false)
        elseif !isnothing(comma_before_end_of_line) ||
                !isnothing(just_a_comma) ||
                !isnothing(comment)
            continue
        else
            snippet = SubString(s.text, startix, s.ix - 1 - length(newline))
            expr = parse_juliacode(s, snippet; kwds..., with_linenode=false)
            if expr isa Expr && expr.head == :incomplete
                expr = parse_juliacode(s, "$snippet\nend", snippet; kwds..., with_linenode=false)
                head = expr.head
            else
                head = nothing
            end
            expr = with_linenode ? Expr(:block, loc, expr) : expr
            return expr, head, newline
        end
    end
    return nothing, nothing, ""
end


end # module
