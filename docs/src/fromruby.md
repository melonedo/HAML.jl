# Differences from Ruby-flavoured HAML

Julia-flavoured HAML is quite close to Ruby-flavoured HAML. Below
we describe the differences between [the syntax for the latter](http://haml.info/docs/yardoc/file.REFERENCE.html) and the former.

## Attributes use named tuple syntax

In Ruby-flavoured HAML [the attributes](http://haml.info/docs/yardoc/file.REFERENCE.html#attributes)
are specified in a Ruby-like syntax. In the Julia-flavoured version, we
use the same syntax as for named tuples. Examples:

```
- link = "https://youtu.be/dQw4w9WgXcQ"
- attr = :href
%a(href=link) Click me
%a(attr=>link) Click me
```

Just like in the Ruby-flavoured version, nested attributes are joined by `-` and
underscores in keys are replaced by dashes:

```
%a(href="/posts", data=(author_id=123, category=7)) Posts By Author
```

If you need another special character in the attribute, use the `var"..."` syntax.
For example, the attribute `xml:lang`:

```
%html(xmlns = "http://www.w3.org/1999/xhtml", var"xml:lang"="en", lang="en")
```

## Many helper methods are not implemented yet

Many of the [Ruby-flavoured helper methods](http://haml.info/docs/yardoc/Haml/Helpers.html) are
not supported (yet).

## Interpolation expects Julia syntax

Use `$` for interpolation in literal text instead of `#{...}`. Example:

```
- quality = "scruptious"
%p This is $quality cake!
```

!!! note

    If you need to combine this with keyword parameters to a template file,
    you'll need double quotes:

    ```
    %p This is $($quality) cake!
    ```

## Helper macros/methods may need to be imported

If you use [`@haml_str`](@ref) or [`HAML.includehaml`](@ref) the HAML code runs in a
module you own. If you want to use macros or helper methods (e.g.,
[`@include`](@ref) or [`surround`](@ref) then you need to either use `using
HAML` or import them.

## Literal content is always escaped

You cannot include literal HTML directly. For example:

```
<p id='literal-html'>This is some literal html</p>
```

If you need to, use interpolation syntax together with the `LiteralHTML` type:

```
$(LiteralHTML("<p id='literal-html'>This is some literal html</p>"))
```
