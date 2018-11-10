module Mark.Custom exposing
    ( Inline, inline
    , Block, block, block1, block2, block3
    , Param, bool, int, float, string, oneOf
    , paragraph, section, indented
    , parser
    )

{-|

@docs Inline, inline


## Block functions with arguments

@docs Block, block, block1, block2, block3


## Parameters

`block1`-`block3` can take parameters specified in the markup. Here are the parameter types you can use:

@docs Param, bool, int, float, string, oneOf


## Styled

@docs paragraph, section, indented


## Advanced

@docs parser

-}

import Element exposing (Element)
import Internal.Model as Internal
import Parser.Advanced as Parser exposing ((|.), (|=), Parser)


{-| -}
type alias Block model msg =
    Internal.Block model msg


{-| -}
type alias Inline model msg =
    Internal.Inline model msg


{-| Create a custom inline styler.

    Custom.inline "intro"
        (\string styling model ->
            let
                txt =
                    String.trim string
            in
            if txt == "" then
                []

            else
                [ Element.el [ Element.alignLeft, Font.size 48 ]
                    (Element.text (String.toUpper (String.slice 0 1 txt)))
                , Element.el [ Font.size 24 ]
                    (Element.text (String.toUpper (String.dropLeft 1 txt)))
                ]
        )

When applied via `parseWith`, can then be used in markup like the following

    {intro| Lorem Ipsum is simply dummy text } of the printing and...

It will turn the first letter into a [dropped capital](https://en.wikipedia.org/wiki/Initial) and lead in with [small caps](https://practicaltypography.com/small-caps.html)

**styling** is the `styling` record that is passed in the options of `parseWith`. This means you can make an inline element that can be paragraph via the options.

-}
inline : String -> (String -> model -> List (Element msg)) -> Inline model msg
inline name renderer =
    Internal.Inline name
        renderer


{-| A simple block that will insert Elm html.

    import Element
    import Element.Font as Font
    import Mark.Custom as Custom

    myParser =
        Mark.parseWith
            { styling = Mark.defaultStyling
            , inlines = []
            , blocks =
                [ Custom.block "red"
                    (\styling model ->
                        Element.el
                            [ Font.color (Element.rgb 1 0 0) ]
                            (Element.text "Some statically defined, red text!")
                    )
                ]
            }

Which can then be used in your markup like so:

    | red

The element you defined will show up there.

-}
block : String -> (model -> Element msg) -> Block model msg
block name renderer =
    Internal.Block name
        (Parser.succeed renderer)


{-| Same as `block`, but you can parse one parameter as well.

For example, here's how the builtin block, `image`, using `block2` and two `Custom.string` parameters.

    Custom.block2 "image"
        (\src description styling model ->
            Element.image
                []
                { src = String.trim src
                , description = String.trim description
                }
        )
        Custom.string
        Custom.string

Which can then be used in your markup:

    | image "http://placekitten/200/500"
        "Here's a great picture of my cat, pookie.""

or as

    | image
        "http://placekitten/200/500"
        "Here's a great picture of my cat, pookie.""

-}
block1 :
    String
    -> (arg -> model -> Element msg)
    -> Param arg
    -> Block model msg
block1 name renderer (Param param) =
    Internal.Block name
        (Parser.succeed renderer
            |= param
        )


{-| -}
block2 :
    String
    -> (arg -> arg2 -> model -> Element msg)
    -> Param arg
    -> Param arg2
    -> Block model msg
block2 name renderer (Param param1) (Param param2) =
    Internal.Block name
        (Parser.succeed renderer
            |= param1
            |= param2
        )


{-| -}
block3 :
    String
    -> (arg -> arg2 -> arg3 -> model -> Element msg)
    -> Param arg
    -> Param arg2
    -> Param arg3
    -> Block model msg
block3 name renderer (Param param1) (Param param2) (Param param3) =
    Internal.Block name
        (Parser.succeed renderer
            |= param1
            |= param2
            |= param3
        )


{-| Parse a double quoted string.
-}
string : Param String
string =
    Param
        (Parser.succeed identity
            |. Parser.chompWhile (\c -> c == ' ' || c == '\n')
            |. Parser.token (Parser.Token "\"" Internal.DoubleQuote)
            |= quotedString
        )


quotedString =
    Parser.loop
        ""
        (\found ->
            Parser.oneOf
                [ Parser.succeed
                    (\new ->
                        Parser.Loop (found ++ new)
                    )
                    |. Parser.token (Parser.Token "\\" Internal.Escape)
                    |= Parser.getChompedString
                        (Parser.chompIf (always True) Internal.EscapedChar)
                , Parser.map (\_ -> Parser.Done found) (Parser.token (Parser.Token "\"" Internal.DoubleQuote))
                , Parser.getChompedString
                    (Parser.chompWhile
                        (\c ->
                            c
                                /= doubleQuote
                                && c
                                /= '\\'
                        )
                    )
                    |> Parser.map
                        (\new ->
                            Parser.Loop (found ++ new)
                        )
                ]
        )


{-| Define a list of options. Useful for working with custom types.
-}
oneOf : List ( String, value ) -> Param value
oneOf opts =
    let
        parseOption ( name, val ) =
            Parser.keyword (Parser.Token name (Internal.Expecting name))
                |> Parser.map (always val)
    in
    Param
        (Parser.oneOf
            (List.map parseOption opts)
        )


{-| A parameter to use with `block1` or `block2`.
-}
type Param arg
    = Param (Parser Internal.Context Internal.Problem arg)


{-| -}
int : Param Int
int =
    Param
        (Parser.succeed identity
            |. Parser.chompIf (\c -> c == ' ') Internal.Space
            |= Parser.int Internal.Integer Internal.InvalidNumber
        )


{-| -}
float : Param Float
float =
    Param
        (Parser.succeed identity
            |. Parser.chompIf (\c -> c == ' ') Internal.Space
            |= Parser.float Internal.FloatingPoint Internal.InvalidNumber
        )


{-| -}
bool : Param Bool
bool =
    Param
        (Parser.succeed identity
            |. Parser.chompIf (\c -> c == ' ') Internal.Space
            |= Parser.oneOf
                [ Parser.token (Parser.Token "True" (Internal.Expecting "True"))
                    |> Parser.map (always True)
                , Parser.token (Parser.Token "False" (Internal.Expecting "False"))
                    |> Parser.map (always False)
                ]
        )


{-| A block that expects a single paragraph of styled text as input. The `header` block that is built in uses this.

    | header
        My super sweet, /styled/ header.

**Note** The actual paragraph text is required to be on the next line and indented four spaces.

-}
paragraph :
    String
    ->
        (List (Element msg)
         -> model
         -> Element msg
        )
    -> Block model msg
paragraph name renderer =
    Internal.Parse name
        (\inlineParser ->
            Parser.succeed
                (\almostElements model ->
                    renderer (almostElements model) model
                )
                |. Parser.token (Parser.Token "\n" Internal.Newline)
                |. Parser.token (Parser.Token "    " Internal.ExpectedIndent)
                |= inlineParser
                |. Parser.token (Parser.Token "\n" Internal.Newline)
        )


{-| Like `Custom.paragraph`, but parses many styled paragraphs.

**Note** Parsing ends when there are three consecutive newlines.

-}
section :
    String
    ->
        (List (Element msg)
         -> model
         -> Element msg
        )
    -> Block model msg
section name renderer =
    Internal.Parse name
        (\inlineParser ->
            Parser.succeed
                (\almostElements model ->
                    renderer (almostElements model) model
                )
                |. Parser.token (Parser.Token "\n" Internal.Newline)
                |. Parser.token (Parser.Token "    " Internal.ExpectedIndent)
                |= Parser.loop []
                    (\els ->
                        Parser.oneOf
                            [ Parser.end Internal.End
                                |> Parser.map
                                    (\_ ->
                                        Parser.Done
                                            (\model ->
                                                List.foldl
                                                    (\fn elems ->
                                                        fn model :: elems
                                                    )
                                                    []
                                                    els
                                            )
                                    )
                            , Parser.token (Parser.Token "\n\n" (Internal.Expecting "\n\n"))
                                |> Parser.map
                                    (\_ ->
                                        Parser.Done
                                            (\model ->
                                                List.foldl
                                                    (\fn elems ->
                                                        fn model :: elems
                                                    )
                                                    []
                                                    els
                                            )
                                    )
                            , Parser.token (Parser.Token "\n    " Internal.ExpectedIndent)
                                |> Parser.map
                                    (\_ ->
                                        Parser.Loop els
                                    )
                            , inlineParser
                                |> Parser.map
                                    (\found ->
                                        Parser.Loop
                                            ((\model ->
                                                Element.paragraph []
                                                    (found model)
                                             )
                                                :: els
                                            )
                                    )
                            ]
                    )
        )


{-| Parse a 4-space-indented, unstyled block of text.

It ends after three consecutive newline characters.

-}
indented :
    String
    ->
        (String
         -> model
         -> Element msg
        )
    -> Block model msg
indented name renderer =
    Internal.Parse name
        (\opts ->
            Parser.succeed renderer
                |. Parser.chompWhile (\c -> c == '\n')
                |= Parser.loop ""
                    (\txt ->
                        Parser.oneOf
                            [ Parser.end Internal.End
                                |> Parser.map
                                    (\_ ->
                                        Parser.Done txt
                                    )
                            , Parser.token (Parser.Token "\n\n" Internal.DoubleNewline)
                                |> Parser.map
                                    (\_ ->
                                        Parser.Done txt
                                    )
                            , if txt == "" then
                                Parser.token (Parser.Token "    " Internal.ExpectedIndent)
                                    |> Parser.map
                                        (\_ ->
                                            Parser.Loop txt
                                        )

                              else
                                Parser.token (Parser.Token "\n    " Internal.ExpectedIndent)
                                    |> Parser.map
                                        (\_ ->
                                            Parser.Loop (txt ++ "\n")
                                        )
                            , Parser.getChompedString
                                (Parser.chompWhile (\c -> c /= '\n'))
                                |> Parser.map
                                    (\found ->
                                        if found == "" then
                                            Parser.Done txt

                                        else
                                            Parser.Loop
                                                (txt ++ found)
                                    )
                            ]
                    )
        )


{-| Run a parser created with [elm/parser](https://package.elm-lang.org/packages/elm/parser/latest/) where you can parse whatever you'd like. This is actually how the `list` block is implemented.

I highly recommend using the other `Custom` parsers if possible as this is the only one that can "break" an elm-markup file.

You're in charge of defining when this parser will stop parsing.

Current conventions:

  - stop parsing after three consecutive newlines
  - blocks should be indented 4 spaces

These conventions may be enforced in the future.

Here's a terrible example.

    Custom.parser "bananaTree"
        (\inlines ->
            -- `inlines` is a parser for styled text which you may or maynot need,
            Parser.succeed identity
                |. Parser.token  " "
                |= (Parser.map
                        -- the result of our parser should be a function that
                        -- takes a `styling` and a `model` and returns `Element msg`
                        (\_ styling model ->
                                Element.el [] (Element.text "bananas"
                        )
                        (Parser.token "bananas")
                    )
                |. Parser.token "\n"
        )

It parses bananas and then says `bananas`. If you wanted to do exactly this in real life, you would probably use some form of `Custom.block`.

-}
parser :
    String
    -> (Parser Internal.Context Internal.Problem (model -> List (Element msg)) -> Parser Internal.Context Internal.Problem (model -> Element msg))
    -> Block model msg
parser name actualParser =
    Internal.Parse name
        (\inlines ->
            Parser.succeed identity
                |. Parser.chompWhile (\c -> c == '\n')
                |= actualParser inlines
        )


doubleQuote =
    '"'
