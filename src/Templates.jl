module Templates

import HAML

import ..Hygiene: make_hygienic, replace_expression_nodes_unescaped
import ..Parse: Source
import ..Codegen: generate_haml_writer_codeblock, replace_output_nodes, @output, @io

function tokwds(assignments...)
    kwds = map(assignments) do a
        a isa Expr || error()
        a.head == :(=) || error()
        Expr(:kw, a.args[1], esc(a.args[2]))
    end

    return Expr(:parameters, kwds...)
end

const files_included = Set()

macro include(relpath, args...)
    args = try
        tokwds(args...)
    catch err
        throw(ArgumentError("Invalid use of @include: $(args...)"))
    end

    at_dir = getproperty(Base, Symbol("@__DIR__"))
    dir = macroexpand(__module__, Expr(:macrocall, at_dir, __source__))

    path = realpath(joinpath(dir, relpath))
    sym = Symbol(path)

    # hasproperty(__module__, sym) doesn't work at pre-compilation time
    key = (objectid(__module__), sym)
    if key ∉ files_included
        includehaml(__module__, sym, path)
        push!(files_included, key)
    end

    res = :( $(esc(sym))($args) do (content...)
        $(Expr(:hamloutput, :(content...)))
    end )
    return res
end

"""
    includehaml(mod::Module, fn::Symbol, path, indent="")

Define methods for the function `mod.fn` that allow rendering the HAML
template in the file `path`. These methods have the following signatures:

    fn(io::IO; variables...)
    fn(f::Function; variables...)
    fn(io::IO, indent; variables...)
    fn(f::Function, indent; variables...)

where the output of the template will be written to `io` / passed to `f`
respectively.

The methods without an `indent` parameter may apply more aggressive
compile-time string concatenation.
"""
includehaml(mod::Module, fn::Symbol, path, indent="") = _includehaml(mod, fn, path, indent)


function _includehaml(mod::Module, fn::Symbol, path, indent="")
    s = Source(path)
    code = generate_haml_writer_codeblock(mod, s, string(indent))
    code = replace_expression_nodes_unescaped(:hamloutput, code) do esc, content...
        :( f($(map(esc, content)...)) )
    end
    code = replace_expression_nodes_unescaped(:$, code) do esc, sym
        sym isa Symbol || error("Can only use variables as interpolations")
        :( variables.data.$sym )
    end
    fn = esc(fn)
    code = quote
        $fn(f::Function; variables...) = $code
        $fn(io::IO; variables...) = $fn(; variables...) do content...
            write(io, content...)
        end
        $fn(; variables...) = let io = IOBuffer()
            $fn(; variables...) do (content...)
                write(io, content...)
            end
            String(take!(io))
        end
    end
    code = make_hygienic(mod, code)
    Base.eval(mod, code)
end

function render(io, path; variables=(), indent="")
    path = abspath(path)
    fn = Symbol(path)
    if !hasproperty(HamlOnFileSystem, fn)
        includehaml(HamlOnFileSystem, fn, path, indent)
    end
    Base.invokelatest(getproperty(HamlOnFileSystem, fn), io; variables...)
end

module HamlOnFileSystem
    import ...Templates: @output, @io, @include
end


end # module
