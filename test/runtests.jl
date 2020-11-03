using Test
using HAML

using DataStructures: OrderedDict

macro expandsto(str1, str2)
    :( @test $(esc(str1)) == $(esc(str2)) )
end

macro errorat(rowcol, expr)
    quote
        err = try
            eval($(QuoteNode(expr)))
        catch err
            err isa LoadError || rethrow(err)
            err
        end
        loc = HAML.Parse.linecol(err)
        (loc[1], loc[2]) == $(esc(rowcol))
    end
end

module Foo end
hamljl(name) = joinpath(@__DIR__, "hamljl", name)

@testset "HAML" begin
    @testset "Plain Text" begin
        @expandsto """
        <gee>
          <whiz>
            Wow this is cool!
          </whiz>
        </gee>
        """ haml"""
        %gee
          %whiz
            Wow this is cool!
        """
        @expandsto """
        <p>
          <div id="blah">Blah!</div>
        </p>
        """ haml"""
        %p
          <div id="blah">Blah!</div>
        """
        let title = "MyPage"
            @expandsto """
            <title>
              MyPage
              = title
            </title>
            """ haml"""
            %title
              = title
              \= title
            """
        end
    end
    @testset "HTML elements" begin
        @expandsto """
        <one>
          <two>
            <three>Hey there</three>
          </two>
        </one>
        """ haml"""
        %one
          %two
            %three Hey there
        """
        @expandsto """
        <html xmlns='http://www.w3.org/1999/xhtml' xml:lang='en' lang='en'></html>
        """ haml"""
        %html(xmlns = "http://www.w3.org/1999/xhtml", var"xml:lang"="en", lang="en")
        """
        @expandsto """
        <html xmlns='http://www.w3.org/1999/xhtml' xml:lang='en' lang='en'></html>
        """ haml"""
        %html(xmlns = "http://www.w3.org/1999/xhtml", Symbol("xml:lang") => "en", lang="en")
        """
        @expandsto """
        <script type='text/javascript' src='javascripts/script_9'></script>
        """ haml"""
        %script(type = "text/javascript",
                src  = "javascripts/script_$(2 + 7)")
        """
        let sortdir = :ascending, sortcol = (id=1, _type=:numeric)
            @expandsto """
            <div class='numeric sort ascending'>Contents</div>
            <div class='numeric'>Contents</div>
            <div>Contents</div>
            """ haml"""
            - for item in [ (id=1, _type=:numeric), (id=2, _type=:numeric), (id=3, _type=nothing) ]
              %div(class = [item._type; item == sortcol && [:sort, sortdir]]) Contents
            """
        end
        begin
            hash1() = OrderedDict(:bread => "white", :filling => "peanut butter and jelly")
            hash2() = OrderedDict(:bread => "whole wheat")
            @expandsto """
            <sandwich bread='whole wheat' filling='peanut butter and jelly' delicious='yes' />
            """ haml"""
            %sandwich(hash1()..., hash2()..., delicious = "yes")/
            """
        end

        let item = []
            @expandsto """
            <div class='item empty'></div>
            """ haml"""
            .item(class = isempty(item) && "empty")
            """
        end

        let items = ["foo", "bar"]
            @expandsto """
            <div id='foo-bar'></div>
            """ haml"""
            %(id=items)
            """

            @expandsto """
            <div class='foo bar'></div>
            """ haml"""
            %(class=items)
            """
        end

        @expandsto """
        <a href='/posts' data-author-id='123' data-category='7'>Posts By Author</a>
        """ haml"""
        %a(href="/posts", data=(author_id=123, category=7)) Posts By Author
        """

        @expandsto """
        <input selected='selected' />
        """ haml"""
        %input(selected=true)/
        """

        @expandsto """
        <input />
        """ haml"""
        %input(selected=false)/
        """

        @expandsto """
        <div id='things'>
            <span id='rice'>Chicken Fried</span>
            <p class='beans' food='true'>The magical fruit</p>
            <h1 class='class otherclass' id='id'>La La La</h1>
        </div>
        """ haml"""
        %div#things
            %span#rice Chicken Fried
            %p.beans(food = "true") The magical fruit
            %h1.class.otherclass#id La La La
        """

        @expandsto """
        <blockquote><div>
          Foo!
        </div></blockquote>
        """ haml"""
        %blockquote<
          %div
            Foo!
        """

        @expandsto """
        <div class='foo-bar'></div>
        """ haml"""
        .foo-bar
        """
    end
    @testset "Whitespace" begin
        @expandsto "" haml""
        @expandsto "
        " haml"
        "
        @expandsto "

        " haml"

        "
        # no closing newline
        @expandsto "<div class='hello'></div>" haml"%div.hello"

        # extra closing newline after expression
        @expandsto """
        <p>42</p>

        """ haml"""
        %p= 42

        """

        # keep indentation even with intermediate code lines
        @expandsto """
        <div>
          <p>Hello</p>
          <p>How are you?</p>
          <p>Bye</p>
        </div>
        """ haml"""
        %
          %p Hello
          - msg = "How are you?"
          %p= msg
          - msg = "Bye"
          %p= msg
        """

        # completely empty line in the middle of an indented block
        @expandsto """
        <div>
          <p>First paragraph</p>

          <p>Second paragraph</p>
        </div>
        """ haml"""
        %div
          %p First paragraph

          %p Second paragraph
        """

        # equally indented empty line in the middle of an indented block
        @expandsto """
        <div>
          <p>First paragraph</p>
          
          <p>Second paragraph</p>
        </div>
        """ haml"""
        %div
          %p First paragraph
          
          %p Second paragraph
        """

        # overly indented empty line in the middle of an indented block
        @expandsto """
        <div>
          <p>First paragraph</p>
               
          <p>Second paragraph</p>
        </div>
        """ haml"""
        %div
          %p First paragraph
               
          %p Second paragraph
        """
    end

    @testset "Julia syntax embedding" begin
        # a comment after the comma
        @expandsto """
        <a href='#' c='d'>Hello everyone!</a>
        <div>1</div>
        <div>2</div>
        """ haml"""
        %a(href="#", # set href to #
              c="d") Hello everyone!
        - array = [1, # the first element
                   2]
        - for a in array
          %= a
        """

        # the characters #"' in annoying places
        @expandsto """
        #
        &#36;
        &quot;
        &quot;
        """ haml"""
        - for s in ["#", "\$", "\\""] # correctly parse some special characters
          = s
        - for s in ['"']
          = s
        """
    end
    @testset "Escaping" begin
        let motto="Let's get ready"
            @expandsto """
            <span motto='Let&#39;s get ready'></span>
            <div>Let&#39;s get ready</div>
            Let&#39;s get ready
            The motto is Let&#39;s get ready
            <p>Let&#39;s get ready</p>
            """ haml"""
            %span(motto=motto)
            %= motto
            = motto
            The motto is $motto
            %p $motto
            """
        end
    end
    @testset "Doctype" begin
        @expandsto """
        <!DOCTYPE html>
        """ haml"""
        !!! 5
        """
    end
    @testset "Comments" begin
        @expandsto """
        <peanutbutterjelly>
          <!-- This is the peanutbutterjelly element -->
          I like sandwiches!
        </peanutbutterjelly>
        """ haml"""
        %peanutbutterjelly
          / This is the peanutbutterjelly element
          I like sandwiches!
        """
        @expandsto """
        <!--
          <p>This doesn't render...</p>
          <div>
            <h1>Because it's commented out!</h1>
          </div>
        -->
        """ haml"""
        /
          %p This doesn't render...
          %div
            %h1 Because it's commented out!
        """
        @expandsto """
        <p>foo</p>
        <p>bar</p>
        """ haml"""
        %p foo
        -# This is a comment
        %p bar
        """
        @expandsto """
        <p>foo</p>
        <p>bar</p>
        """ haml"""
        %p foo
        -#
          This won't be displayed
            Nor will this
                           Nor will this.
        %p bar
        """
    end
    @testset "Helper methods" begin
        @expandsto """
        (<a href='#'>learn more</a>)
        """ haml"""
        - @surround("(", ")") do
          %a(href="#") learn more
        """
        @expandsto """
        *<span>Required</span>
        """ haml"""
        - @precede("*") do
          %span Required
        """
        @expandsto """
        Begin by
        <a href='#'>filling out your profile</a>,
        <a href='#'>adding a bio</a>,
        and
        <a href='#'>inviting friends</a>.
        """ haml"""
        Begin by
        - @succeed(",") do
          %a(href="#") filling out your profile
        - @succeed(",") do
          %a(href="#") adding a bio
        and
        - @succeed(".") do
          %a(href="#") inviting friends
        """

        @expandsto """
        <div>
          <p>A paragraph from a source file</p>
        </div>""" haml"""
        %
          - @sourcefile("hamljl/paragraph.html")
        """

        @expandsto """
        <script>
          <![CDATA[
          function foo() {
          }
          ]]>
        </script>""" haml"""
        %script
          - @cdatafile("hamljl/foo.js")
        """
    end
    @testset "Julia evaluation" begin
        @expandsto """
        <p>
          hi there reader&#33;
          yo
        </p>
        """ haml"""
        %p
          = join(["hi", "there", "reader!"], " ")
          = "yo"
        """
        @expandsto """
        &lt;script&gt;alert&#40;&quot;I&#39;m evil&#33;&quot;&#41;;&lt;/script&gt;
        """ haml"""
        = "<script>alert(\\"I'm evil!\\");</script>"
        """
        @expandsto """
        <p>hello</p>
        """ haml"""
        %p= "hello"
        """
        @expandsto """
        <p>hello there you&#33;</p>
        """ haml"""
        - foo = "hello"
        - foo *= " there"
        - foo *= " you!"
        %p= foo
        """
        let quality = "scrumptious"
            @expandsto """
            <p>This is scrumptious cake!</p>
            """ haml"""
            %p This is $quality cake!
            """
        end
        let word = "yon"
            @expandsto raw"""
            <p>
              Look at \yon lack of backslash: $foo
              And yon presence thereof: \foo
            </p>
            """ haml"""
            %p
              Look at \\$word lack of backslash: \$foo
              And yon presence thereof: \foo
            """
        end
    end
    @testset "Scoping" begin
        let a = 2
            haml"""
            - @test a == 2
            - a = 3
            """
            @test a == 3
        end
    end
    @testset "Hygiene w.r.t. internal variables" begin
        @expandsto """
        <p>42</p>
        """ haml"""
        - io = 42
        %p= io
        """
        @expandsto """
        <p>42</p>
        """ haml"""
        - writeattributes = 42
        %p= writeattributes
        """
        @expandsto """
        <p>42</p>
        """ haml"""
        - writehaml = 42
        %p= writehaml
        """
        @expandsto """
        <p>42</p>
        """ haml"""
        - forest = 42 # don't mistake this for a for loop because it starts with for
        %p= forest
        """
        @expandsto """
        1 2 3 4 5 6 7 8 9 10
        """ haml"""
        = haml"= join(1:10, ' ')"
        """
        @expandsto """
        Hi!
        Hello!
        Bye!
        """ haml"""
        Hi!
        - @output "Hello!\n"
        - @HAML.output "Bye!\n"
        """
        @expandsto """
        Using the @output macro
        """ haml"""
        - @include("hamljl/at-output.hamljl")
        """
        let attribute = :href # hygiene of the => operator inside a named tuple
            @expandsto """
            <a class='link' href='/index.html'>Home</a>
            """ haml"""
            %a(class="link", attribute => "/index.html") Home
            """
        end
    end
    @testset "Control flow" begin
        @expandsto """
        <div>1</div>
        <div>2</div>
        <div>3</div>
        """ haml"""
        - for i in 1:3
          %= i
        """

        @expandsto """
        <div>1</div>
        <div>2</div>
        <div>3</div>
        """ haml"""
        - map(1:3) do i
          %= i
        """

        @expandsto """
        <div>3</div>
        <div>2</div>
        <div>1</div>
        """ haml"""
        - list = collect(1:3)
        - while !isempty(list)
          %= pop!(list)
        """

        @expandsto """
        <p>All else follows</p>
        """ haml"""
        - if 2 + 2 == 4
          %p All else follows
        - else
          %p I love Big Brother
        """

        @expandsto """
        <p>I love Big Brother</p>
        """ haml"""
        - if 2 + 2 == 5
          %p All else follows
        - else # with a comment
          %p I love Big Brother
        """

        @expandsto """
        <p>Hello</p>
        """ haml"""
        - begin
          %p Hello
        """

        @expandsto """
        <p>Hello</p>
        """ haml"""
        - let greeting = "Hello"
          %p= greeting
        """

        @expandsto """
        <p>hello</p>
        <p>world</p>
        """ haml"""
        - macro paragraph(text)
          %p= text
        - @paragraph("hello")
        - @paragraph("world")
        """
    end

    @testset "File format" begin

        @expandsto """
        <html>
          <head>
            <title>The Hitchhiker's guide to the galaxy</title>
          </head>
          <body>
            <h1>What's the question?</h1>
            <p>What&#39;s the answer to life, the universe, and everything?</p>
            <h2>What's the answer?</h2>
            <p>42</p>
          </body>
        </html>
        """ haml"""
        - answer = 42
        - @include("hamljl/hitchhiker.hamljl", question = "What's the answer to life, the universe, and everything?", answer = answer)
        """

        @expandsto """
        <form>
          <p>Here's a little button:</p>
          <!-- button below -->
          <button onclick='javascript:alert&#40;Thank you for clicking&#41;'>Click me</button>
          <!-- button above -->
          <p>Did you see the little button?</p>
        </form>
        """ haml"""
        - @include("hamljl/form.hamljl")
        """

        let io = IOBuffer()  # test the render(...) entrypoint
            render(io, hamljl("hitchhiker.hamljl"),
                variables = (
                    question = "What's the answer to life, the universe, and everything?",
                    answer = "42",
                ),
            )
            @test """
            <html>
              <head>
                <title>The Hitchhiker's guide to the galaxy</title>
              </head>
              <body>
                <h1>What's the question?</h1>
                <p>What&#39;s the answer to life, the universe, and everything?</p>
                <h2>What's the answer?</h2>
                <p>42</p>
              </body>
            </html>
            """ == String(take!(io))
        end

        @test Meta.parse(HAML.Source(hamljl("hitchhiker.hamljl"))) isa Expr

        @test includehaml(Foo, :hitchhiker, hamljl("hitchhiker.hamljl")) isa Function
        @test includehaml(Foo, :foo => hamljl("hitchhiker.hamljl"), :bar => hamljl("hitchhiker.hamljl")) == nothing
        @test Foo.hitchhiker(question="Q", answer="A") ==
            Foo.foo(question="Q", answer="A") ==
            Foo.bar(question="Q", answer="A") == """
        <html>
          <head>
            <title>The Hitchhiker's guide to the galaxy</title>
          </head>
          <body>
            <h1>What's the question?</h1>
            <p>Q</p>
            <h2>What's the answer?</h2>
            <p>A</p>
          </body>
        </html>
        """

        # recursion
        @expandsto """
        1
        2
        3
        4
        5
        """ haml"""
        - @include("hamljl/recursion.hamljl", count=5)
        """

        @expandsto """
        <dl>
          <dt>Module</dt>
          <dd>Main</dd>
          <dt>Directory</dt>
          <dd>$(@__DIR__)</dd>
          <dt>File</dt>
          <dd>$(@__FILE__)</dd>
        </dl>
        """ haml"""
        %dl
          %dt Module
          %dd= @__MODULE__
          %dt Directory
          %dd= @__DIR__
          %dt File
          %dd= @__FILE__
        """

        includehaml(Foo, :context, hamljl("context.hamljl"))

        @test Foo.context() == """
        <dl>
          <dt>Module</dt>
          <dd>Main.Foo</dd>
          <dt>Directory</dt>
          <dd>$(joinpath(@__DIR__, "hamljl"))</dd>
          <dt>File</dt>
          <dd>$(hamljl("context.hamljl"))</dd>
        </dl>
        """
    end

    @testset "File/line information" begin
        line = @__LINE__
        @expandsto """
        <ul>
          <li>$(line +  9)</li>
          <li>$(line + 10)</li>
          <li>$(line + 11)</li>
        </ul>
        """ haml"""
        %ul
          %li= @__LINE__
          %li= @__LINE__
          %li= @__LINE__
        """

        @test haml"= @__FILE__" == @__FILE__

        @test haml"""
        - @include("hamljl/at-file.hamljl")
        """ == realpath(joinpath(@__DIR__, "hamljl", "at-file.hamljl")) * "\n"

        includehaml(Foo, :atfile => hamljl("at-file.hamljl"))
        @test Foo.atfile() == realpath(joinpath(@__DIR__, "hamljl", "at-file.hamljl")) * "\n"
    end

    @testset "Syntax error reporting" begin
        @test @errorat (1, 2) haml"""
        - %a
        """

        @test @errorat (2, 2) haml"""
        - a = 1
        - %a
        """

        @test @errorat (1, 3) haml"""
        %a(3)
        """

        # TODO
        #@test @errorat (1, 12) haml"""
        #%a(href=1, 3)
        #"""

        @test @errorat (1, 6) haml"""
        %br/ Syntax error: content after /
        """

        @test @errorat (2, 1) haml"""
        %br/
          Syntax error: a block after /
        """

        @test @errorat (2, 1) haml"""
        %p= 3
          Syntax error: a block after =
        """

        @test @errorat (3, 3) haml"""
        %div
            %div
          %div
        """
    end

    @testset "Compile-time expansion where possible" begin
        @test @macroexpand(haml"""
        %p Hallo
        %a(href="./index.html") Home
        """) isa String

        @test @macroexpand(haml"""
        %p Hallo
        %a(href="./index.html")
        """) isa String

        @test @macroexpand(haml"""
        !!! 5
        %html
          %head
            %title= title
          %body
            %ul
              %li= item1
              %li= item2
        """).head == :string

        @test_broken @macroexpand(haml"""
        - macro paragraph(text)
          %p= text
        - @paragraph("hello")
        - @paragraph("world")
        """).head == :string
    end

    @testset "Macros" begin
        haml"""
        - macro my_first_macro()
          %p Hello from my first macro
        """

        @expandsto """
        <p>Hello from my first macro</p>
        """ haml"""
        - @my_first_macro
        """
    end
end
