module Mark.Custom exposing
    ( parse
    , Document, document
    , Block, block, oneOf, map, many
    , nested, Nested(..)
    , bool, int, float, string, multiline, exactly
    , field, record2, record3, record4, record5, record6
    , Text, TextFormatting(..), InlineStyle(..)
    , text, textWith, inline
    , Replacement, replacement, balanced
    , advanced
    , Problem(..), Context(..)
    )

{-|

@docs parse

@docs Document, document

@docs Block, block, oneOf, map, many

@docs nested, Nested

@docs bool, int, float, string, multiline, exactly


## Records

@docs field, record2, record3, record4, record5, record6


## Text

@docs Text, TextFormatting, InlineStyle
@docs text, textWith, inline

@docs Replacement, replacement, balanced


## Advanced

@docs advanced

@docs Problem, Context

-}

import Parser.Advanced as Parser exposing ((|.), (|=), Parser)


{-| -}
parse : Document result -> String -> Result (List (Parser.DeadEnd Context Problem)) result
parse (Document blocks) source =
    Parser.run blocks source


{-| -}
type Block result
    = Block (Parser Context Problem result)


{-| -}
type alias Text =
    { style : TextFormatting
    , link : Maybe String
    }


{-| -}
type TextFormatting
    = NoFormatting String
    | Styles (List InlineStyle) String


textFormttingString form =
    case form of
        NoFormatting str ->
            str

        Styles _ str ->
            str


{-| -}
type TextAccumulator rendered
    = TextAccumulator
        -- Accumulator string
        { text : TextFormatting

        -- Accumulator of element constructors
        , rendered : List rendered
        , balancedReplacements : List String
        }


{-| -}
type Replacement
    = Replacement String String
    | Balanced
        { start : ( String, String )
        , end : ( String, String )
        }


{-| -}
type InlineStyle
    = NoStyleChange
    | Bold
    | Italic
    | Strike
    | Underline
    | Token


{-| -}
type Context
    = InBlock String
    | InInline String
    | InRecordField String


{-| -}
type Problem
    = NoBlocks
    | EmptyBlock
    | ExpectedIndent
    | NonMatchingIndent Int Int
    | InlineStart
    | InlineBar
    | InlineEnd
    | Expecting String
    | ExpectingBlockName String
    | ExpectingInlineName String
    | ExpectingFieldName String
    | RecordField FieldError
    | DoubleField String
    | Escape
    | EscapedChar
    | Dash
    | DoubleQuote
    | Apostrophe
    | Newline
    | Space
    | End
    | Integer
    | FloatingPoint
    | InvalidNumber
    | ExpectingAlphaNumeric
    | CantStartTextWithSpace
    | UnexpectedField
        { found : String
        , options : List String
        , recordName : String
        }


{-| -}
block : String -> (child -> result) -> Block child -> Block result
block name renderer (Block childParser) =
    Block
        (Parser.getIndent
            |> Parser.andThen
                (\indent ->
                    Parser.succeed renderer
                        -- TODO: I'd rather not use backtrackable, but not entirely sure how to avoid it here.
                        |. Parser.backtrackable (Parser.token (Parser.Token "|" (ExpectingBlockName name)))
                        |. Parser.backtrackable
                            (Parser.oneOf
                                [ Parser.chompIf (\c -> c == ' ') Space
                                , Parser.succeed ()
                                ]
                            )
                        |. Parser.keyword (Parser.Token name (ExpectingBlockName name))
                        |. Parser.chompWhile (\c -> c == ' ')
                        |. Parser.chompIf (\c -> c == '\n') Newline
                        |. Parser.token (Parser.Token (String.repeat (indent + 4) " ") ExpectedIndent)
                        |= Parser.withIndent (indent + 4) (Parser.inContext (InBlock name) childParser)
                )
        )


{-| -}
type Document result
    = Document (Parser Context Problem result)


{-| You must have a root parser for your document.

It parses everything at the top-level of indentation.

-}
document : (child -> result) -> Block child -> Document result
document renderer (Block childParser) =
    Document
        (Parser.map renderer (Parser.withIndent 0 childParser))


{-| -}
advanced : Parser Context Problem result -> Block result
advanced parser =
    Block parser


{-| -}
map : (a -> b) -> Block a -> Block b
map fn (Block parser) =
    Block (Parser.map fn parser)


{-| `text` and other `Blocks` don't allow starting with spaces.

However, it can be useful to capture indentation for things like a nested list.

So, for example, here's a list.

    | List
        - item one
        - item two
            - nested item two
            additional text for nested item two
        - item three
            - nested item three

In order to support blocks like this, you can use `nested`, which
captures the indentation and returns it as an `Int`,
which is the number of spaces that it's indented in the block.

In order to parse the above, you could define a block as

    block "List"
        (\items ->
            -- items : List (Int, (), Text)
        )
        (nested
            { item = text
            , delimiter = advanced (Parser.token "-")
            }
        )

Which will result in something like the following(though with `Text` instead of strings):

    ( 0, (), [ "item one" ] )

    ( 0, (), [ "item two" ] )

    ( 4, (), [ "nested item two", "additional text for nested item two" ] )

    ( 0, (), [ "item three" ] )

    ( 4, (), [ "nested item three" ] )

_Note_ the indentation is always a multiple of 4.

-}
nested :
    { item : Block item
    , start : Block icon
    }
    -> Block (List (Nested ( icon, List item )))
nested config =
    Block
        (Parser.getIndent
            |> Parser.andThen
                (\baseIndent ->
                    Parser.map
                        (\items ->
                            let
                                gather ( indent, icon, item ) (TreeBuilder builder) =
                                    addItem (indent - baseIndent) ( icon, item ) (TreeBuilder builder)

                                groupByIcon ( indent, maybeIcon, item ) maybeCursor =
                                    case maybeCursor of
                                        Nothing ->
                                            case maybeIcon of
                                                Just icon ->
                                                    Just
                                                        { indent = indent
                                                        , icon = icon
                                                        , items = [ item ]
                                                        , accumulated = []
                                                        }

                                                Nothing ->
                                                    -- Because of how the code runs, we have a tenuous guarantee that this branch won't execute.
                                                    -- Not entirely sure how to make the types work to eliminate this.
                                                    Nothing

                                        Just cursor ->
                                            Just <|
                                                case maybeIcon of
                                                    Nothing ->
                                                        { indent = cursor.indent
                                                        , icon = cursor.icon
                                                        , items = item :: cursor.items
                                                        , accumulated = cursor.accumulated
                                                        }

                                                    Just icon ->
                                                        { indent = indent
                                                        , icon = icon
                                                        , items = [ item ]
                                                        , accumulated =
                                                            ( cursor.indent, cursor.icon, List.reverse cursor.items )
                                                                :: cursor.accumulated
                                                        }

                                finalizeGrouping maybeCursor =
                                    case maybeCursor of
                                        Nothing ->
                                            []

                                        Just cursor ->
                                            case cursor.items of
                                                [] ->
                                                    cursor.accumulated

                                                _ ->
                                                    ( cursor.indent, cursor.icon, List.reverse cursor.items )
                                                        :: cursor.accumulated

                                tree =
                                    items
                                        |> List.foldl groupByIcon Nothing
                                        |> finalizeGrouping
                                        |> List.reverse
                                        |> List.foldl gather emptyTreeBuilder
                            in
                            case tree of
                                TreeBuilder builder ->
                                    renderLevels builder.levels
                        )
                        (Parser.loop
                            ( { base = baseIndent
                              , prev = baseIndent
                              }
                            , []
                            )
                            (indentedBlocksOrNewlines config.start config.item)
                        )
                )
        )


type alias NestedIndex =
    { base : Int
    , prev : Int
    }


{-| -}
indentedBlocksOrNewlines :
    Block icon
    -> Block thing
    -> ( NestedIndex, List ( Int, Maybe icon, thing ) )
    -> Parser Context Problem (Parser.Step ( NestedIndex, List ( Int, Maybe icon, thing ) ) (List ( Int, Maybe icon, thing )))
indentedBlocksOrNewlines (Block iconParser) (Block itemParser) ( indent, existing ) =
    Parser.oneOf
        [ case existing of
            [] ->
                Parser.end End
                    |> Parser.andThen
                        (\_ -> Parser.problem EmptyBlock)

            _ ->
                Parser.end End
                    |> Parser.map
                        (\_ ->
                            Parser.Done (List.reverse existing)
                        )

        -- Whitespace Line
        , Parser.succeed
            (Parser.Loop ( indent, existing ))
            |. Parser.token (Parser.Token "\n" Newline)
            |. Parser.oneOf
                [ Parser.succeed ()
                    |. Parser.backtrackable (Parser.chompWhile (\c -> c == ' '))
                    |. Parser.backtrackable (Parser.token (Parser.Token "\n" Newline))
                , Parser.succeed ()
                ]
        , case existing of
            [] ->
                -- Indent is already parsed by the block constructor for first element, skip it
                Parser.succeed
                    (\foundIcon foundBlock ->
                        let
                            newIndex =
                                { prev = indent.base
                                , base = indent.base
                                }
                        in
                        Parser.Loop ( newIndex, ( indent.base, Just foundIcon, foundBlock ) :: existing )
                    )
                    |= iconParser
                    |= itemParser

            _ ->
                Parser.oneOf
                    [ -- block with required indent
                      expectIndentation indent.base indent.prev
                        |> Parser.andThen
                            (\newIndent ->
                                -- If the indent has changed, then the delimiter is required
                                Parser.withIndent newIndent <|
                                    Parser.oneOf
                                        ((Parser.succeed
                                            (\icon item ->
                                                let
                                                    newIndex =
                                                        { prev = newIndent
                                                        , base = indent.base
                                                        }
                                                in
                                                Parser.Loop ( newIndex, ( newIndent, Just icon, item ) :: existing )
                                            )
                                            |= iconParser
                                            |= itemParser
                                         )
                                            :: (if newIndent == indent.prev then
                                                    [ itemParser
                                                        |> Parser.map
                                                            (\foundBlock ->
                                                                let
                                                                    newIndex =
                                                                        { prev = newIndent
                                                                        , base = indent.base
                                                                        }
                                                                in
                                                                Parser.Loop ( newIndex, ( newIndent, Nothing, foundBlock ) :: existing )
                                                            )
                                                    ]

                                                else
                                                    []
                                               )
                                        )
                            )

                    -- We reach here because the indentation parsing was not successful,
                    -- This means any issues are handled by whatever parser comes next.
                    , Parser.succeed (Parser.Done (List.reverse existing))
                    ]
        ]


{-| We only expect nearby indentations.

We can't go below the `base` indentation.

Based on the previous indentation:

  - previous - 4
  - previous
  - previous + 4

If we don't match the above rules, we might want to count the mismatched number.

-}
expectIndentation : Int -> Int -> Parser Context Problem Int
expectIndentation base previous =
    Parser.succeed Tuple.pair
        |= Parser.oneOf
            ([ Parser.succeed (previous + 4)
                |. Parser.token (Parser.Token (String.repeat (previous + 4) " ") ExpectedIndent)
             , Parser.succeed previous
                |. Parser.token (Parser.Token (String.repeat previous " ") ExpectedIndent)
             ]
                ++ descending base previous
            )
        |= Parser.getChompedString (Parser.chompWhile (\c -> c == ' '))
        |> Parser.andThen
            (\( indentLevel, extraSpaces ) ->
                if extraSpaces == "" then
                    Parser.succeed indentLevel

                else
                    Parser.problem
                        (NonMatchingIndent
                            base
                            (base + indentLevel + String.length extraSpaces)
                        )
            )


descending base prev =
    if prev <= base then
        []

    else
        List.map
            (\x ->
                let
                    level =
                        x + 4
                in
                Parser.succeed level
                    |. Parser.token (Parser.Token (String.repeat level " ") ExpectedIndent)
            )
            (List.range 0 ((prev - base) // 4))


{-| Many blocks that are all at the same indentation level.
-}
many : Block a -> Block (List a)
many thing =
    Block
        (Parser.getIndent
            |> Parser.andThen
                (\indent ->
                    Parser.loop []
                        (blocksOrNewlines thing indent)
                )
        )


{-| -}
blocksOrNewlines : Block thing -> Int -> List thing -> Parser Context Problem (Parser.Step (List thing) (List thing))
blocksOrNewlines (Block myBlock) indent existing =
    Parser.oneOf
        [ Parser.end End
            |> Parser.map
                (\_ ->
                    Parser.Done (List.reverse existing)
                )

        -- Whitespace Line
        , Parser.succeed
            (Parser.Loop existing)
            |. Parser.token (Parser.Token "\n" Newline)
            |. Parser.oneOf
                [ Parser.succeed ()
                    |. Parser.backtrackable (Parser.chompWhile (\c -> c == ' '))
                    |. Parser.backtrackable (Parser.token (Parser.Token "\n" Newline))
                , Parser.succeed ()
                ]
        , case existing of
            -- First thing already has indentation accounted for.
            [] ->
                myBlock
                    |> Parser.map
                        (\foundBlock ->
                            Parser.Loop (foundBlock :: existing)
                        )

            _ ->
                Parser.oneOf
                    [ Parser.succeed
                        (\foundBlock ->
                            Parser.Loop (foundBlock :: existing)
                        )
                        |. Parser.token (Parser.Token (String.repeat indent " ") ExpectedIndent)
                        |= myBlock

                    -- We reach here because the indentation parsing was not successful,
                    -- meaning the indentation has been lowered and the block is done
                    , Parser.succeed (Parser.Done (List.reverse existing))
                    ]
        ]


{-| -}
oneOf : List (Block a) -> Block a
oneOf blocks =
    Block (Parser.oneOf (List.map (\(Block parser) -> parser) blocks))


{-| -}
exactly : String -> value -> Block value
exactly key val =
    Block
        (Parser.succeed val
            |. Parser.token (Parser.Token key (Expecting key))
        )


{-| -}
int : Block Int
int =
    Block
        (Parser.int Integer InvalidNumber)


{-| -}
float : Block Float
float =
    Block
        (Parser.float FloatingPoint InvalidNumber)


{-| -}
bool : Block Bool
bool =
    Block
        (Parser.oneOf
            [ Parser.token (Parser.Token "True" (Expecting "True"))
                |> Parser.map (always True)
            , Parser.token (Parser.Token "False" (Expecting "False"))
                |> Parser.map (always False)
            ]
        )


{-| -}
string : Block String
string =
    Block
        (Parser.getChompedString
            (Parser.chompWhile
                (\c -> c /= '\n')
            )
        )


{-| -}
type Field value
    = Field String (Block value)


{-| -}
record2 :
    String
    -> (one -> two -> data)
    -> Field one
    -> Field two
    -> Block data
record2 recordName renderer field1 field2 =
    let
        recordParser =
            Parser.succeed renderer
                |= fieldParser field1
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field2
    in
    masterRecordParser recordName [ fieldName field1, fieldName field2 ] recordParser


{-| -}
record3 :
    String
    -> (one -> two -> three -> data)
    -> Field one
    -> Field two
    -> Field three
    -> Block data
record3 recordName renderer field1 field2 field3 =
    let
        recordParser =
            Parser.succeed renderer
                |= fieldParser field1
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field2
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field3
    in
    masterRecordParser recordName [ fieldName field1, fieldName field2, fieldName field3 ] recordParser


{-| -}
record4 :
    String
    -> (one -> two -> three -> four -> data)
    -> Field one
    -> Field two
    -> Field three
    -> Field four
    -> Block data
record4 recordName renderer field1 field2 field3 field4 =
    let
        recordParser =
            Parser.succeed renderer
                |= fieldParser field1
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field2
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field3
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field4
    in
    masterRecordParser recordName [ fieldName field1, fieldName field2, fieldName field3, fieldName field4 ] recordParser


{-| -}
record5 :
    String
    -> (one -> two -> three -> four -> five -> data)
    -> Field one
    -> Field two
    -> Field three
    -> Field four
    -> Field five
    -> Block data
record5 recordName renderer field1 field2 field3 field4 field5 =
    let
        recordParser =
            Parser.succeed renderer
                |= fieldParser field1
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field2
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field3
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field4
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field5
    in
    masterRecordParser recordName
        [ fieldName field1
        , fieldName field2
        , fieldName field3
        , fieldName field4
        , fieldName field5
        ]
        recordParser


{-| -}
record6 :
    String
    ->
        (one
         -> two
         -> three
         -> four
         -> five
         -> six
         -> data
        )
    -> Field one
    -> Field two
    -> Field three
    -> Field four
    -> Field five
    -> Field six
    -> Block data
record6 recordName renderer field1 field2 field3 field4 field5 field6 =
    let
        recordParser =
            Parser.succeed renderer
                |= fieldParser field1
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field2
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field3
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field4
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field5
                |. Parser.chompIf (\c -> c == '\n') Newline
                |= fieldParser field6
    in
    masterRecordParser recordName
        [ fieldName field1
        , fieldName field2
        , fieldName field3
        , fieldName field4
        , fieldName field5
        , fieldName field6
        ]
        recordParser


masterRecordParser recordName names recordParser =
    Block
        (Parser.getIndent
            |> Parser.andThen
                (\indent ->
                    (Parser.succeed identity
                        -- TODO: I'd rather not use backtrackable, but not entirely sure how to avoid it here.
                        |. Parser.backtrackable (Parser.token (Parser.Token "|" (ExpectingBlockName recordName)))
                        |. Parser.backtrackable
                            (Parser.oneOf
                                [ Parser.chompIf (\c -> c == ' ') Space
                                , Parser.succeed ()
                                ]
                            )
                        |. Parser.keyword (Parser.Token recordName (ExpectingBlockName recordName))
                        |. Parser.chompWhile (\c -> c == ' ')
                        |. Parser.chompIf (\c -> c == '\n') Newline
                        |= Parser.withIndent (indent + 4)
                            (Parser.inContext (InBlock recordName)
                                (Parser.loop [] (indentedFieldNames recordName (indent + 4) names))
                            )
                    )
                        |> Parser.andThen
                            (\fieldList ->
                                let
                                    join ( key, val ) str =
                                        case str of
                                            "" ->
                                                key ++ " = " ++ val

                                            _ ->
                                                str ++ "\n" ++ key ++ " = " ++ val

                                    recomposed =
                                        fieldList
                                            |> reorderFields names
                                            |> Result.map (List.foldl join "")
                                in
                                case recomposed of
                                    Ok str ->
                                        case Parser.run recordParser str of
                                            Ok ok ->
                                                Parser.succeed ok

                                            Err err ->
                                                let
                                                    _ =
                                                        Debug.log "Recomposed" str

                                                    _ =
                                                        Debug.log "Error" err
                                                in
                                                Parser.problem (ExpectingFieldName "Charles")

                                    Err recordError ->
                                        Parser.problem (RecordField recordError)
                            )
                )
        )


type FieldError
    = NonMatchingFields
        { expecting : List String
        , found : List String
        }
    | MissingField String


reorderFields : List String -> List ( String, String ) -> Result FieldError (List ( String, String ))
reorderFields desiredOrder found =
    if List.length desiredOrder /= List.length found then
        Err
            (NonMatchingFields
                { expecting = desiredOrder
                , found = List.map Tuple.first found
                }
            )

    else
        List.foldl (gatherFields found) (Ok []) desiredOrder
            |> Result.map List.reverse


gatherFields : List ( String, String ) -> String -> Result FieldError (List ( String, String )) -> Result FieldError (List ( String, String ))
gatherFields cache desired found =
    case found of
        Ok ok ->
            case getField cache desired of
                Ok newField ->
                    Ok (newField :: ok)

                Err str ->
                    Err str

        _ ->
            found


getField cache desired =
    case cache of
        [] ->
            Err (MissingField desired)

        ( name, top ) :: rest ->
            if desired == name then
                Ok ( name, top )

            else
                getField rest desired


fieldParser (Field _ (Block parser)) =
    parser


fieldName (Field name _) =
    name



-- order


{-| -}
field : String -> Block value -> Field value
field name (Block child) =
    Field name (Block (withFieldName name child))


withFieldName name parser =
    Parser.getIndent
        |> Parser.andThen
            (\indent ->
                Parser.succeed identity
                    |. Parser.keyword (Parser.Token name (ExpectingFieldName name))
                    |. Parser.chompIf (\c -> c == ' ') Space
                    |. Parser.chompIf (\c -> c == '=') (Expecting "=")
                    |. Parser.chompIf (\c -> c == ' ') Space
                    |= Parser.inContext (InRecordField name) parser
            )


indentedFieldNames : String -> Int -> List String -> List ( String, String ) -> Parser Context Problem (Parser.Step (List ( String, String )) (List ( String, String )))
indentedFieldNames recordName indent fields found =
    let
        _ =
            Debug.log "record indent" indent

        fieldNameParser name =
            Parser.succeed
                (\contentStr ->
                    Parser.Loop (( name, contentStr ) :: found)
                )
                |. Parser.token (Parser.Token name (Expecting name))
                |. Parser.chompWhile (\c -> c == ' ')
                |. Parser.chompIf (\c -> c == '=') (Expecting "=")
                |= Parser.getChompedString
                    (Parser.chompWhile
                        (\c -> c /= '\n')
                    )

        unexpectedField =
            Parser.getChompedString
                (Parser.chompWhile (\c -> c /= '=' && c /= '\n'))
                |> Parser.andThen
                    (\unexpected ->
                        let
                            trimmed =
                                String.trim unexpected
                        in
                        Parser.problem
                            (UnexpectedField
                                { found = trimmed
                                , options = fields
                                , recordName = recordName
                                }
                            )
                    )

        content =
            Parser.succeed
                (\str ->
                    case found of
                        [] ->
                            Parser.Loop found

                        ( name, contentStr ) :: remain ->
                            Parser.Loop (( name, contentStr ++ "\n" ++ str ) :: remain)
                )
                |. Parser.chompIf (\c -> c == ' ') ExpectedIndent
                |= Parser.getChompedString
                    (Parser.chompWhile
                        (\c -> c /= '\n')
                    )
    in
    Parser.oneOf
        [ Parser.succeed
            identity
            |. Parser.token (Parser.Token (String.repeat indent " ") ExpectedIndent)
            |= Parser.oneOf
                (case found of
                    [] ->
                        List.map fieldNameParser fields ++ [ unexpectedField ]

                    _ ->
                        content
                            :: List.map fieldNameParser fields
                            ++ [ unexpectedField ]
                )
        , Parser.token (Parser.Token "\n" Newline)
            |> Parser.map (\_ -> Parser.Loop found)
        , Parser.succeed (Parser.Done found)
        ]


{-| -}
multiline : Block String
multiline =
    Block
        (Parser.getIndent
            |> Parser.andThen
                (\indent ->
                    Parser.loop "" (indentedString indent)
                )
        )


indentedString : Int -> String -> Parser Context Problem (Parser.Step String String)
indentedString indent found =
    Parser.oneOf
        [ Parser.succeed (\str -> Parser.Loop (str ++ found))
            |. Parser.token (Parser.Token (String.repeat indent " ") ExpectedIndent)
            |= Parser.getChompedString
                (Parser.chompWhile
                    (\c -> c /= '\n')
                )
        , Parser.token (Parser.Token "\n" Newline)
            |> Parser.map (\_ -> Parser.Loop (found ++ "\n"))
        , Parser.succeed (Parser.Done found)
        ]


{-| -}
text : Block (List Text)
text =
    textWith
        basicTextOptions


basicTextOptions =
    { view = identity
    , inlines = []
    , merge = identity
    , replacements = []
    }


{-| -}
textWith :
    { view : Text -> rendered
    , inlines : List (Inline rendered)
    , merge : List rendered -> result
    , replacements : List Replacement
    }
    -> Block result
textWith options =
    Block (styledText options [] [])


{-| -}
type Inline result
    = Inline (List InlineStyle -> Parser Context Problem result)


{-| -}
inline : String -> (List Text -> result) -> Inline result
inline name renderer =
    Inline
        (\styles ->
            Parser.succeed renderer
                |. Parser.keyword (Parser.Token name (ExpectingInlineName name))
                |. Parser.token (Parser.Token "|" InlineBar)
                |= styledText basicTextOptions styles [ '}' ]
                |. Parser.token (Parser.Token "}" InlineEnd)
        )


{-| -}
replacement : String -> String -> Replacement
replacement =
    Replacement


{-| -}
balanced :
    { end : ( String, String )
    , start : ( String, String )
    }
    -> Replacement
balanced =
    Balanced


{-| -}
emptyText : TextAccumulator rendered
emptyText =
    TextAccumulator
        { text = NoFormatting ""
        , rendered = []
        , balancedReplacements = []
        }



{- Text Parsing -}


{-| -}
styledText :
    { view : Text -> rendered
    , inlines : List (Inline rendered)
    , merge : List rendered -> result
    , replacements : List Replacement
    }
    -> List InlineStyle
    -> List Char
    -> Parser Context Problem result
styledText options inheritedStyles until =
    let
        vacantText =
            case inheritedStyles of
                [] ->
                    TextAccumulator { text = NoFormatting "", rendered = [], balancedReplacements = [] }

                x ->
                    TextAccumulator { text = Styles inheritedStyles "", rendered = [], balancedReplacements = [] }

        untilStrings =
            List.map String.fromChar until

        meaningful =
            '\n' :: until ++ stylingChars ++ replacementStartingChars options.replacements
    in
    Parser.oneOf
        [ Parser.chompIf
            (\c -> c == ' ')
            CantStartTextWithSpace
            |> Parser.andThen
                (\_ ->
                    Parser.problem CantStartTextWithSpace
                )
        , Parser.loop vacantText
            (styledTextLoop options meaningful untilStrings)
        ]


{-| -}
styledTextLoop :
    { view : Text -> rendered
    , inlines : List (Inline rendered)
    , merge : List rendered -> result
    , replacements : List Replacement
    }
    -> List Char
    -> List String
    -> TextAccumulator rendered
    -> Parser Context Problem (Parser.Step (TextAccumulator rendered) result)
styledTextLoop options meaningful untilStrings found =
    Parser.oneOf
        [ Parser.oneOf (replace options.replacements found)
            |> Parser.map Parser.Loop

        -- If a char matches the first character of a replacement,
        -- but didn't match the full replacement captured above,
        -- then stash that char.
        , Parser.oneOf (almostReplacement options.replacements found)
            |> Parser.map Parser.Loop

        -- Capture style command characters
        , Parser.succeed
            (Parser.Loop << changeStyle options found)
            |= Parser.oneOf
                [ Parser.map (always Italic) (Parser.token (Parser.Token "/" (Expecting "/")))
                , Parser.map (always Underline) (Parser.token (Parser.Token "_" (Expecting "_")))
                , Parser.map (always Strike) (Parser.token (Parser.Token "~" (Expecting "~")))
                , Parser.map (always Bold) (Parser.token (Parser.Token "*" (Expecting "*")))
                , Parser.map (always Token) (Parser.token (Parser.Token "`" (Expecting "`")))
                ]

        -- Custom inline block
        , Parser.succeed
            (\rendered ->
                let
                    current =
                        case changeStyle options found NoStyleChange of
                            TextAccumulator accum ->
                                accum
                in
                Parser.Loop
                    (TextAccumulator
                        { rendered = rendered :: current.rendered

                        -- TODO: This should inherit formatting from the inline parser
                        , text = NoFormatting ""
                        , balancedReplacements = current.balancedReplacements
                        }
                    )
            )
            |. Parser.token
                (Parser.Token "{" InlineStart)
            |= Parser.oneOf
                (List.map (\(Inline inlineParser) -> inlineParser (currentStyles found)) options.inlines)

        -- Link
        , Parser.succeed
            (\textList url ->
                case changeStyle options found NoStyleChange of
                    TextAccumulator current ->
                        Parser.Loop <|
                            TextAccumulator
                                { rendered =
                                    List.map
                                        (\textNode ->
                                            options.view
                                                { link = Just url
                                                , style = textNode.style
                                                }
                                        )
                                        (List.reverse textList)
                                        ++ current.rendered
                                , text =
                                    case List.map .style (List.reverse textList) of
                                        [] ->
                                            NoFormatting ""

                                        (NoFormatting _) :: _ ->
                                            NoFormatting ""

                                        (Styles styles _) :: _ ->
                                            Styles styles ""
                                , balancedReplacements = current.balancedReplacements
                                }
            )
            |. Parser.token (Parser.Token "[" (Expecting "["))
            |= styledText basicTextOptions (currentStyles found) [ ']' ]
            |. Parser.token (Parser.Token "]" (Expecting "]"))
            |. Parser.token (Parser.Token "(" (Expecting "("))
            |= Parser.getChompedString
                (Parser.chompWhile (\c -> c /= ')' && c /= '\n' && c /= ' '))
            |. Parser.token (Parser.Token ")" (Expecting ")"))
        , -- chomp until a meaningful character
          Parser.chompWhile
            (\c ->
                not (List.member c meaningful)
            )
            |> Parser.getChompedString
            |> Parser.map
                (\new ->
                    if new == "" || new == "\n" then
                        Parser.Done (finishText options found)

                    else if List.member (String.right 1 new) untilStrings then
                        Parser.Done (finishText options (addText (String.dropRight 1 new) found))

                    else
                        Parser.Loop (addText new found)
                )
        ]


currentStyles (TextAccumulator formatted) =
    case formatted.text of
        NoFormatting _ ->
            []

        Styles s _ ->
            s


finishText :
    { view : Text -> rendered
    , inlines : List (Inline rendered)
    , merge : List rendered -> result
    , replacements : List Replacement
    }
    -> TextAccumulator rendered
    -> result
finishText opts accum =
    case changeStyle opts accum NoStyleChange of
        TextAccumulator txt ->
            opts.merge (List.reverse txt.rendered)


{-| -}
almostReplacement : List Replacement -> TextAccumulator rendered -> List (Parser Context Problem (TextAccumulator rendered))
almostReplacement replacements existing =
    let
        captureChar char =
            Parser.succeed
                (\c ->
                    addText c existing
                )
                |= Parser.getChompedString
                    (Parser.chompIf (\c -> c == char && char /= '{') EscapedChar)

        first repl =
            case repl of
                Replacement x y ->
                    firstChar x

                Balanced range ->
                    firstChar (Tuple.first range.start)

        allFirstChars =
            List.filterMap first replacements
    in
    List.map captureChar allFirstChars


{-| **Reclaimed typography**

This function will replace certain characters with improved typographical ones.
Escaping a character will skip the replacement.

    -> "<>" -> a non-breaking space.
        - This can be used to glue words together so that they don't break
        - It also avoids being used for spacing like `&nbsp;` because multiple instances will collapse down to one.
    -> "--" -> "en-dash"
    -> "---" -> "em-dash".
    -> Quotation marks will be replaced with curly quotes.
    -> "..." -> ellipses

-}
replace : List Replacement -> TextAccumulator rendered -> List (Parser Context Problem (TextAccumulator rendered))
replace replacements existing =
    let
        -- Escaped characters are captured as-is
        escaped =
            Parser.succeed
                (\esc ->
                    existing
                        |> addText esc
                )
                |. Parser.token
                    (Parser.Token "\\" Escape)
                |= Parser.getChompedString
                    (Parser.chompIf (always True) EscapedChar)

        replaceWith repl =
            case repl of
                Replacement x y ->
                    Parser.succeed
                        (addText y existing)
                        |. Parser.token (Parser.Token x (Expecting x))
                        |. Parser.loop ()
                            (\_ ->
                                Parser.oneOf
                                    [ Parser.token (Parser.Token x (Expecting x))
                                        |> Parser.map (always (Parser.Loop ()))
                                    , Parser.succeed (Parser.Done ())
                                    ]
                            )

                Balanced range ->
                    let
                        balanceCache =
                            case existing of
                                TextAccumulator cursor ->
                                    cursor.balancedReplacements

                        id =
                            balanceId range
                    in
                    -- TODO: implement range replacement
                    if List.member id balanceCache then
                        case range.end of
                            ( x, y ) ->
                                Parser.succeed
                                    (addText y existing
                                        |> removeBalance id
                                    )
                                    |. Parser.token (Parser.Token x (Expecting x))

                    else
                        case range.start of
                            ( x, y ) ->
                                Parser.succeed
                                    (addText y existing
                                        |> addBalance id
                                    )
                                    |. Parser.token (Parser.Token x (Expecting x))
    in
    escaped :: List.map replaceWith replacements


balanceId balance =
    let
        join ( x, y ) =
            x ++ y
    in
    join balance.start ++ join balance.end


stylingChars =
    [ '~'
    , '_'
    , '/'
    , '*'
    , '['
    , '\n'
    , '<'
    , '`'
    ]


firstChar str =
    case String.uncons str of
        Nothing ->
            Nothing

        Just ( fst, _ ) ->
            Just fst


replacementStartingChars replacements =
    let
        first repl =
            case repl of
                Replacement x y ->
                    firstChar x

                Balanced range ->
                    firstChar (Tuple.first range.start)
    in
    List.filterMap first replacements


addBalance id (TextAccumulator cursor) =
    TextAccumulator <|
        { cursor | balancedReplacements = id :: cursor.balancedReplacements }


removeBalance id (TextAccumulator cursor) =
    TextAccumulator <|
        { cursor | balancedReplacements = List.filter ((/=) id) cursor.balancedReplacements }


addText newTxt (TextAccumulator cursor) =
    case cursor.text of
        NoFormatting txt ->
            TextAccumulator { cursor | text = NoFormatting (txt ++ newTxt) }

        Styles styles txt ->
            TextAccumulator { cursor | text = Styles styles (txt ++ newTxt) }


changeStyle options (TextAccumulator cursor) styleToken =
    let
        textIsEmpty =
            case cursor.text of
                NoFormatting "" ->
                    True

                Styles _ "" ->
                    True

                _ ->
                    False

        newText =
            case styleToken of
                NoStyleChange ->
                    cursor.text

                Bold ->
                    flipStyle Bold cursor.text

                Italic ->
                    flipStyle Italic cursor.text

                Strike ->
                    flipStyle Strike cursor.text

                Underline ->
                    flipStyle Underline cursor.text

                Token ->
                    flipStyle Token cursor.text
    in
    if textIsEmpty then
        TextAccumulator { rendered = cursor.rendered, text = newText, balancedReplacements = cursor.balancedReplacements }

    else
        TextAccumulator
            { rendered =
                options.view
                    { style = cursor.text
                    , link = Nothing
                    }
                    :: cursor.rendered
            , text = newText
            , balancedReplacements = cursor.balancedReplacements
            }


flipStyle newStyle textStyle =
    case textStyle of
        NoFormatting str ->
            Styles [ newStyle ] ""

        Styles styles str ->
            if List.member newStyle styles then
                Styles (List.filter ((/=) newStyle) styles) ""

            else
                Styles (newStyle :: styles) ""


{-| = indentLevel icon space content
| indentLevel content

Where the second variation can only occur if the indentation is larger than the previous one.

A list item started with a list icon.

    If indent stays the same
    -> add to items at the current stack

    if ident increases
    -> create a new level in the stack

    if ident decreases
    -> close previous group
    ->

    <list>
        <*item>
            <txt> -> add to head sections
            <txt> -> add to head sections
            <item> -> add to head sections
            <item> -> add to head sections
                <txt> -> add to content
                <txt> -> add to content
                <item> -> add to content
                <item> -> add to content
            <item> -> add to content

        <*item>
        <*item>

    Section
        [ IconSection
            { icon = *
            , sections =
                [ Text
                , Text
                , IconSection Text
                , IconSection
                    [ Text
                    , Text
                    , item
                    , item
                    ]
                ]
            }
        , Icon -> Content
        , Icon -> Content
        ]

-}
type TreeBuilder item
    = TreeBuilder
        { previousIndent : Int
        , levels :
            -- (mostRecent :: remaining)
            List (Level item)
        }


{-| -}
type Level item
    = Level (List (Nested item))


{-| -}
type Nested item
    = Nested
        { content : item
        , children :
            List (Nested item)
        }


emptyTreeBuilder : TreeBuilder item
emptyTreeBuilder =
    TreeBuilder
        { previousIndent = 0
        , levels = []
        }


{-| A list item started with a list icon.

If indent stays the same
-> add to items at the current stack

if ident increases
-> create a new level in the stack

if ident decreases
-> close previous group
->

    1 Icon
        1.1 Content
        1.2 Icon
        1.3 Icon
           1.3.1 Icon

        1.4

    2 Icon

    Steps =
    []

    [ Level [ Item 1. [] ]
    ]

    [ Level [ Item 1.1 ]
    , Level [ Item 1. [] ]
    ]

    [ Level [ Item 1.2, Item 1.1 ]
    , Level [ Item 1. [] ]
    ]

    [ Level [ Item 1.3, Item 1.2, Item 1.1 ]
    , Level [ Item 1. [] ]
    ]

    [ Level [ Item 1.3.1 ]
    , Level [ Item 1.3, Item 1.2, Item 1.1 ]
    , Level [ Item 1. [] ]
    ]


    [ Level [ Item 1.4, Item 1.3([ Item 1.3.1 ]), Item 1.2, Item 1.1 ]
    , Level [ Item 1. [] ]
    ]

    [ Level [ Item 2., Item 1. (Level [ Item 1.4, Item 1.3([ Item 1.3.1 ]), Item 1.2, Item 1.1 ]) ]
    ]

-}
addItem :
    Int
    -> node
    -> TreeBuilder node
    -> TreeBuilder node
addItem indent content (TreeBuilder builder) =
    let
        newItem =
            Nested
                { children = []
                , content = content
                }

        deltaLevel =
            indent
                - List.length builder.levels

        addToLevel brandNewItem levels =
            case levels of
                [] ->
                    [ Level
                        [ brandNewItem ]
                    ]

                (Level lvl) :: remaining ->
                    Level (newItem :: lvl)
                        :: remaining
    in
    case builder.levels of
        [] ->
            TreeBuilder
                { previousIndent = indent
                , levels =
                    [ Level
                        [ newItem ]
                    ]
                }

        (Level lvl) :: remaining ->
            if deltaLevel == 0 then
                -- add to current level
                TreeBuilder
                    { previousIndent = indent
                    , levels =
                        Level (newItem :: lvl)
                            :: remaining
                    }

            else if deltaLevel > 0 then
                -- add new level
                TreeBuilder
                    { previousIndent = indent
                    , levels =
                        Level [ newItem ]
                            :: Level lvl
                            :: remaining
                    }

            else
                -- We've dedented, so we need to first collapse the current level
                -- into the one below, then add an item to that level
                TreeBuilder
                    { previousIndent = indent
                    , levels =
                        collapseLevel (abs deltaLevel) builder.levels
                            |> addToLevel newItem
                    }


{-|

    1.
        1.1
    2.


    Steps =
    []

    [ Level [ Item 1. [] ]
    ]

    [ Level [ Item 1.1 ]
    , Level [ Item 1. [] ]
    ]

    -- collapse into lower level
    [ Level [ Item 1. [ Item 1.1 ] ]
    ]

    -- add new item
    [ Level [ Item 2, Item 1. [ Item 1.1 ] ]
    ]

-}
collapseLevel : Int -> List (Level item) -> List (Level item)
collapseLevel num levels =
    if num == 0 then
        levels

    else
        case levels of
            [] ->
                levels

            (Level topLevel) :: (Level ((Nested lowerItem) :: lower)) :: remaining ->
                collapseLevel (num - 1) <|
                    Level
                        (Nested
                            { lowerItem
                                | children = topLevel ++ lowerItem.children
                            }
                            :: lower
                        )
                        :: remaining

            _ ->
                levels


renderLevels levels =
    case levels of
        [] ->
            []

        _ ->
            case collapseLevel (List.length levels - 1) levels of
                [] ->
                    []

                (Level top) :: ignore ->
                    -- We just collapsed everything down to the top level.
                    List.reverse top
