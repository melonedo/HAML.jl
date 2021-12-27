module Templates

import HAML

import ..Hygiene: make_hygienic, replace_expression_nodes_unescaped
import ..SourceTools: Source
import ..Codegen: generate_haml_writer_codeblock, replace_output_nodes, InternalNamespace
import ..Parse: @nolinenodes
import ..Escaping

function tokwds(assignments...)
    kwds = map(assignments) do a
        a isa Expr || error()
        a.head == :(=) || error()
        Expr(:kw, a.args[1], esc(a.args[2]))
    end

    return Expr(:parameters, kwds...)
end

const files_included = Set()

"""
    @include(relpath, args...)

Include HAML code from another file. This macro can only be used
from within other HAML code. `args` should be `key=value` parameters
and they will be accessible in the included code by using `\$key`.
"""
macro include(relpath, args...)
    args = try
        tokwds(args...)
    catch err
        throw(ArgumentError("Invalid use of @include: $(args...)"))
    end

    at_dir = Base.var"@__DIR__"
    dir = macroexpand(__module__, Expr(:macrocall, at_dir, __source__))

    path = realpath(joinpath(dir, relpath))
    sym = Symbol(path)

    # hasproperty(__module__, sym) doesn't work at pre-compilation time
    key = (objectid(__module__), sym)
    if key ∉ files_included
        push!(files_included, key)
        includehaml(__module__, sym, path)
    end

    res = Expr(:hamloutput, Expr(:call, esc(sym), args, Expr(:hamlindentation)))
    return res
end

"""
    includehaml(mod::Module, fn::Symbol, path, indent="")
    includehaml(mod::Module, fns::Pair{Symbol}...)

Define methods for the function `mod.fn` that allow rendering the HAML
template in the file `path`. These methods have the following signatures:

    fn(io::IO, indent=""; variables...)
    fn(f::Function, indent=""; variables...)
    fn(indent=""; variables...)

where the output of the template will be written to `io` / passed to `f`
/ returned respectively.
"""
function includehaml(mod::Module, fn::Symbol, path, indent="")
    revisehook(mod, fn, path, indent)
    _includehaml(mod, fn, path, indent)
end

includehaml(mod::Module, fns::Pair{Symbol}...) = foreach(fns) do (fn, path)
    includehaml(mod, fn, path)
end

revisehook(mod, fn, path, indent) = nothing

function _includehaml(mod::Module, fn::Symbol, path, indent="")
    Base.include_dependency(path)
    s = Source(path)
    code = generate_haml_writer_codeblock(mod, s, Expr(:string, indent, :indent))
    code = replace_output_nodes(code, :io)
    code = replace_expression_nodes_unescaped(:$, code) do esc, sym
        sym isa Symbol || error("Can only use variables as interpolations")
        :( variables[$(QuoteNode(sym))] )
    end
    fn = esc(fn)
    interpolate = GlobalRef(Escaping, :interpolate)
    code = @nolinenodes quote
        $fn(io::IO, indent=""; variables...) = $code
        $interpolate(io::IO, ::typeof($fn), args...; kwds...) = $fn(io, args...; kwds...)
        $fn(indent=""; variables...) = LiteralHTML(io -> $fn(io, indent; variables...))
    end
    pushfirst!(code.args, s.__source__)
    code = make_hygienic(InternalNamespace, code)
    Base.eval(mod, code)
end

"""
    render(io, path; variables=(), indent="")

Evaluate HAML code in the file specified by `path` and write
the result to `io`. Any variables passed as `variables` will be
available to the resulting code as `\$key`.
"""
function render(io, path; variables=(), indent="")
    path = abspath(path)
    fn = Symbol(path)
    if !hasproperty(HamlOnFileSystem, fn)
        includehaml(HamlOnFileSystem, fn, path, indent)
    end
    Base.invokelatest(getproperty(HamlOnFileSystem, fn), io; variables...)
end

module HamlOnFileSystem
    import ...Helpers: @output
    import ...Templates: @include
end


end # module
