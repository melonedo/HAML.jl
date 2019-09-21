module Codegen

import Base.Meta: parse, quot

import DataStructures: OrderedDict
import Markdown: htmlesc

import HAML: hamlfilter
import ..Parse: @capture, @mustcapture, Source

function replace_interpolations(f, expr)
    !(expr isa Expr) && return expr
    if expr.head == :$ && length(expr.args) == 1 && expr.args[1] isa Symbol
        return f(expr.args[1])
    else
        return Expr(expr.head, map(a -> replace_interpolations(f, a), expr.args)...)
    end
end

indentlength(s) = mapreduce(c -> c == '\t' ? 8 : 1, +, s, init=0)
indentlength(::Nothing) = -1

function makeattr(name, val)
    ignore(x) = isnothing(x) || x === false
    val = filter(!ignore, [val;])
    isempty(val) && return (false, nothing, nothing)

    if name == :class
        value = join(val, " ")
    elseif name == :id
        value = join(val, "-")
    else
        ix = findlast(!ignore, val)
        value = val[ix]
    end
    if value === true
        valuerepr = string(name)
    else
        valuerepr = string(value)
    end
    namerepr = replace(string(name), "_" => "-")
    return (true, htmlesc(namerepr), htmlesc(valuerepr))
end

join_attr_name(x...) = Symbol(join(x, "-"))
recurse_attributes(x, path...) = (join_attr_name(path...) => x,)
recurse_attributes(x::Pair, path...) = recurse_attributes(x[2], path..., x[1])
recurse_attributes(x::Union{NamedTuple,AbstractDict}, path...) = (attr for pair in pairs(x) for attr in recurse_attributes(pair, path...))
recurse_attributes(x::AbstractVector, path...) = (attr for pair in x for attr in recurse_attributes(pair, path...))

function writeattributes(io, attributes)
    collected_attributes = OrderedDict()
    for (name, value) in recurse_attributes(attributes)
        a = get!(Vector, collected_attributes, name)
        append!(a, [value;])
    end
    for (name, value) in pairs(collected_attributes)
        (valid, name, value) = makeattr(name, value)
        valid || continue
        write(io, " ", name, "='", value, "'")
    end
end

function extendblock!(block, expr)
    @assert block isa Expr && block.head == :block

    if expr isa Expr && expr.head == :block
        for e in expr.args
            extendblock!(block, e)
        end
        return
    end
    if !isempty(block.args) && expr isa Expr
        prev = block.args[end]
        if prev isa Expr && prev.head == :call && prev.args[1] == :write && expr.head == :call && expr.args[1] == :write && prev.args[end] isa AbstractString && expr.args[3] isa AbstractString
            prev.args[end] *= expr.args[3]
            append!(prev.args, expr.args[4:end])
            return
        end
    end
    if !(expr isa LineNumberNode)
        push!(block.args, expr)
    end
end

function parse_tag_stanza!(code, curindent, source; outerindent, io, esc, dir)
    @mustcapture source "Expecting a tag name" r"(?:%(?<tagname>[A-Za-z0-9]+)?)?"
    tagname = something(tagname, "div")

    let_block = :( let attributes = []; end )
    push!(code.args, let_block)
    block = let_block.args[2]
    while @capture source r"""
        (?=(?<openbracket>\())
        |
        (?:
            (?<sigil>\.|\#)
            (?<value>[A-Za-z0-9]+)
        )
    """x
        if !isnothing(openbracket)
            attributes_tuple_expr = parse(source, greedy=false)
            if attributes_tuple_expr.head == :(=)
                attributes_tuple_expr = :( ($attributes_tuple_expr,) )
            end
            extendblock!(block, quote
                let attributes_tuple = $(esc(attributes_tuple_expr))
                    for (attr, value) in pairs(attributes_tuple)
                        push!(attributes, attr => value)
                    end
                end
            end)
        else
            if sigil == "."
                extendblock!(block, quote
                    push!(attributes, :class => $value)
                end)
            elseif sigil == "#"
                extendblock!(block, quote
                    push!(attributes, :id => $value)
                end)
            else
                error(source, "Unknown sigil: $sigil")
            end
        end
    end

    @mustcapture source "Expecting '=', '/', or whitespace" r"""
        (?<equalssign>\=)
        |
        (?<closingslash>/)?
        (?:
          \h+
          (?<rest_of_line>.+)
        )?
        $
        (?<nl>\v*)
    """mx

    code_for_inline_val = nothing
    if !isnothing(equalssign)
        @mustcapture source "Expecting an expression" r"""
            \h*
            (?<code_to_parse>
                (?:,\h*(?:\#.*)?\v|.)*
            )
            $(?<nl>\v?)
        """mx
        expr = parse(source, code_to_parse)
        code_for_inline_val = :( let val = $(esc(expr))
            htmlesc($io, string(val))
        end )
    elseif !isnothing(rest_of_line)
        code_for_inline_val = quote
            write($io, $rest_of_line)
        end
    end

    body = quote end
    haveblock = parse_indented_block!(body, curindent, source, outerindent=outerindent, io=io, esc=esc, dir=dir)
    if !isnothing(closingslash)
        @assert isnothing(code_for_inline_val)
        extendblock!(block, quote
            write($io, $"$outerindent$curindent<$tagname")
            writeattributes($io, attributes)
            write($io, $" />$nl")
        end)
    elseif haveblock
        @assert isnothing(code_for_inline_val)
        extendblock!(block, quote
            write($io, $"$outerindent$curindent<$tagname")
            writeattributes($io, attributes)
            write($io, ">\n")
            $body
            write($io, $"$outerindent$curindent</$tagname>$nl")
        end)
    else
        extendblock!(block, quote
            write($io, $"$outerindent$curindent<$tagname")
            writeattributes($io, attributes)
            write($io, ">")
            $code_for_inline_val
            write($io, $"</$tagname>$nl")
        end)
    end
end


function parse_indented_block!(code, curindent, source; outerindent="", io, esc, dir)
    parsed_something = false

    controlflow_this = nothing
    controlflow_prev = nothing
    while !isempty(source)
        controlflow_this, controlflow_prev = nothing, controlflow_this
        if indentlength(match(r"\A\h*", source).match) <= indentlength(curindent)
             return parsed_something
         end
        if @capture source r"""
            ^
            (?<indent>\h*)                      # indentation
            (?=(?<sigil>%|\#|\.|-|=|\\|:|!!!))? # stanza type
            (?:-|=|\\|:|!!!)?                   # consume these stanza types
        """xm
            parsed_something = true

            if sigil in ("%", "#", ".")
                parse_tag_stanza!(code, indent, source, outerindent=outerindent, io=io, esc=esc, dir=dir)
            elseif sigil == "-"
                @mustcapture source "Expecting an expression" r"""
                    \h*
                    (?<code_to_parse>
                        (?:,\h*(?:\#.*)?\v|.)*
                    )$\v?
                """mx
                if startswith(code_to_parse, r"\h*(?:for|if|while)\b")
                    block = parse(source, "$code_to_parse\nend", code_to_parse)
                    block.args[1] = esc(block.args[1])
                    extendblock!(code, block)
                    parse_indented_block!(block.args[2], indent, source, outerindent=outerindent, io=io, esc=esc, dir=dir)
                    controlflow_this = block
                elseif !isnothing(match(r"\A\h*else\h*\z", code_to_parse))
                    block = quote end
                    push!(controlflow_prev.args, block)
                    parse_indented_block!(block, indent, source, outerindent=outerindent, io=io, esc=esc, dir=dir)
                elseif (block = parse(source, "$code_to_parse\nend", code_to_parse, raise=false); block isa Expr && block.head == :do)
                    block.args[1] = esc(block.args[1])
                    block.args[2].args[1] = esc(block.args[2].args[1])
                    extendblock!(code, block)
                    body_of_fun = block.args[2].args[2]
                    parse_indented_block!(body_of_fun, indent, source, outerindent=outerindent, io=io, esc=esc, dir=dir)
                else
                    expr = parse(source, code_to_parse)
                    extendblock!(code, esc(expr))
                end
            elseif sigil == "="
                @mustcapture source "Expecting an expression" r"""
                    \h*
                    (?<code_to_parse>
                        (?:.*|,\h*\v)*
                    )
                    $(?<nl>\v?)
                """mx
                expr = parse(source, code_to_parse)
                extendblock!(code, quote
                    write($io, $indent)
                    let val = $(esc(expr))
                        htmlesc($io, string(val))
                    end
                    write($io, $nl)
                end)
            elseif sigil == "\\" || sigil == nothing
                @mustcapture source "Expecting literal data" r"\h*(?<rest_of_line>.*)$(?<nl>\v*)"m
                extendblock!(code, quote
                    write($io, $"$indent$rest_of_line$nl")
                end)
            elseif sigil == ":"
                @mustcapture source "Expecting an expression" r"""
                    (?<code_to_parse>
                        (?:.*|,\h*\v)*
                    )
                    $(?<nl>\v?)
                """mx
                filter_expr = parse(source, code_to_parse)
                if filter_expr isa Expr && filter_expr.head == :call
                    extendblock!(code, quote
                        hamlfilter(Val($(quot(filter_expr.args[1]))), $io, $dir, Val(Symbol($(outerindent * indent))), $(filter_expr.args[2:end]...))
                    end)
                    # TODO: define semantics for collapsing newlines
                    #push!(code.args, quote
                    #    write($io, $nl)
                    #end)
                else
                    error(source, "Unrecognized filter: $filter_expr")
                end
            elseif sigil == "!!!"
                @mustcapture source "Only support '!!! 5'" r"\h*5\h*$(?<nl>\v?)"m
                extendblock!(code, quote
                    write($io, $"<!DOCTYPE html>$nl")
                end)
            else
                error(source, "Unrecognized sigil: $sigil")
            end
        else
            error(source, "Unrecognized")
        end
    end
    return parsed_something
end

function generate_haml_writer_codeblock(source; outerindent="", io, esc, interp, dir)
    code = quote end
    transform_user_code(expr) = esc(replace_interpolations(interp, expr))
    parse_indented_block!(code, nothing, Source(source), outerindent=outerindent, io=io, esc=transform_user_code, dir=dir)
    return code
end

macro _haml(io, outerindent, variables, dir, source)
    generate_haml_writer_codeblock(source, outerindent=outerindent, io=esc(io), esc=identity, interp=sym -> :( $(esc(variables)).data.$sym ), dir=dir)
end

macro haml_str(source)
    if isnothing(__source__.file)
        rootdir = pwd()
    else
        rootdir = dirname(String(__source__.file))
        if isempty(rootdir)
            rootdir = pwd()
        end
    end
    dirfd = ccall(:open, RawFD, (Cstring, Int32), rootdir, 0)
    reinterpret(Int32, dirfd) < 0 && error("Couldn't open $rootdir")

    code = generate_haml_writer_codeblock(source, io=:io, esc=Base.esc, interp=identity, dir=dirfd)
    quote
        io = IOBuffer()
        $code
        String(take!(io))
    end
end

end # module
