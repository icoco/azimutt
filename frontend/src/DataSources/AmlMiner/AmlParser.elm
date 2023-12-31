module DataSources.AmlMiner.AmlParser exposing (AmlColumn, AmlColumnName, AmlColumnProps, AmlColumnRef, AmlColumnType, AmlColumnValue, AmlComment, AmlEmpty, AmlNotes, AmlParsedColumnType, AmlRelation, AmlSchemaName, AmlStatement(..), AmlTable, AmlTableName, AmlTableProps, AmlTableRef, column, columnName, columnProps, columnRef, columnType, columnValue, comment, constraint, empty, notes, parse, parser, properties, property, relation, schemaName, statement, table, tableName, tableProps, tableRef)

import Dict exposing (Dict)
import Libs.Maybe as Maybe
import Libs.Models.Position exposing (Position)
import Libs.Nel as Nel exposing (Nel)
import Libs.Tailwind as Color exposing (Color)
import Parser exposing ((|.), (|=), DeadEnd, Parser, Step(..), Trailing(..), chompIf, chompWhile, end, getChompedString, loop, oneOf, problem, sequence, succeed, symbol, variable)
import Set



-- see /docs/aml/README.md


type AmlStatement
    = AmlTableStatement AmlTable
    | AmlRelationStatement AmlRelation
    | AmlEmptyStatement AmlEmpty


type alias AmlEmpty =
    { comment : Maybe AmlComment }


type alias AmlRelation =
    { from : AmlColumnRef, to : AmlColumnRef, comment : Maybe AmlComment }


type alias AmlTable =
    { schema : Maybe AmlSchemaName
    , table : AmlTableName
    , isView : Bool
    , props : Maybe AmlTableProps
    , notes : Maybe AmlNotes
    , comment : Maybe AmlComment
    , columns : List AmlColumn
    }


type alias AmlTableProps =
    { position : Maybe Position, color : Maybe Color }


type alias AmlColumn =
    { name : AmlColumnName
    , kind : Maybe AmlColumnType
    , kindSchema : Maybe AmlSchemaName
    , values : Maybe (Nel AmlColumnValue)
    , default : Maybe AmlColumnValue
    , nullable : Bool
    , primaryKey : Bool
    , index : Maybe String
    , unique : Maybe String
    , check : Maybe String
    , foreignKey : Maybe AmlColumnRef
    , props : Maybe AmlColumnProps
    , notes : Maybe AmlNotes
    , comment : Maybe AmlComment
    }


type alias AmlColumnProps =
    { hidden : Bool }


type alias AmlTableRef =
    { schema : Maybe AmlSchemaName, table : AmlTableName }


type alias AmlColumnRef =
    { schema : Maybe AmlSchemaName, table : AmlTableName, column : AmlColumnName }


type alias AmlSchemaName =
    String


type alias AmlTableName =
    String


type alias AmlColumnName =
    String


type alias AmlColumnType =
    String


type alias AmlColumnValue =
    String


type alias AmlParsedColumnType =
    { schema : Maybe AmlSchemaName, name : AmlColumnType, values : Maybe (Nel AmlColumnValue), default : Maybe AmlColumnValue }


type alias AmlNotes =
    String


type alias AmlComment =
    String


parse : String -> Result (List DeadEnd) (List AmlStatement)
parse input =
    if input |> String.endsWith "\n" then
        input |> Parser.run parser

    else
        input ++ "\n" |> Parser.run parser


parser : Parser (List AmlStatement)
parser =
    succeed identity
        |= list statement
        |. end


statement : Parser AmlStatement
statement =
    oneOf
        [ empty |> Parser.map AmlEmptyStatement
        , relation |> Parser.map AmlRelationStatement
        , table |> Parser.map AmlTableStatement
        ]


empty : Parser AmlEmpty
empty =
    succeed (\coms -> { comment = coms })
        |= maybe (succeed identity |= comment |. spaces)
        |. endOfLine


relation : Parser AmlRelation
relation =
    succeed (\from to coms -> { from = from, to = to, comment = coms })
        |. symbolI "fk"
        |. spaces
        |= columnRef
        |. spaces
        |. symbol "->"
        |. spaces
        |= columnRef
        |. spaces
        |= maybe (succeed identity |= comment |. spaces)
        |. endOfLine


table : Parser AmlTable
table =
    succeed
        (\ref view props ntes coms cols ->
            { schema = ref.schema
            , table = ref.table
            , isView = view /= Nothing
            , props = props
            , notes = ntes
            , comment = coms
            , columns = cols
            }
        )
        |. spaces
        |= tableRef
        |= maybe (succeed identity |. symbol "*" |. spaces)
        |. spaces
        |= maybe (succeed identity |= tableProps |. spaces)
        |= maybe (succeed identity |= notes |. spaces)
        |= maybe (succeed identity |= comment |. spaces)
        |. endOfLine
        |= list column


column : Parser AmlColumn
column =
    succeed
        (\name kind nullable pk idx unq chk fk props ntes coms ->
            { name = name
            , kind = kind |> Maybe.map .name
            , kindSchema = kind |> Maybe.andThen .schema
            , values = kind |> Maybe.andThen .values
            , default = kind |> Maybe.andThen .default
            , nullable = nullable /= Nothing
            , primaryKey = pk /= Nothing
            , index = idx
            , unique = unq
            , check = chk
            , foreignKey = fk
            , props = props
            , notes = ntes
            , comment = coms
            }
        )
        |. symbol "  "
        |= columnName
        |. spaces
        |= maybe (succeed identity |= columnType |. spaces)
        |= maybe (succeed identity |. symbolI "nullable" |. spaces)
        |= maybe (succeed identity |. symbolI "pk" |. spaces)
        |= maybe (succeed identity |= constraint "index" |. spaces)
        |= maybe (succeed identity |= constraint "unique" |. spaces)
        |= maybe (succeed identity |= constraint "check" |. spaces)
        |= maybe (succeed identity |. symbolI "fk" |. spaces |= columnRef |. spaces)
        |= maybe (succeed identity |= columnProps |. spaces)
        |= maybe (succeed identity |= notes |. spaces)
        |= maybe (succeed identity |= comment |. spaces)
        |. endOfLine


constraint : String -> Parser String
constraint kind =
    succeed (\value -> value |> Maybe.withDefault "")
        |. symbolI kind
        |. spaces
        |= maybe
            (succeed identity
                |. symbol "="
                |. spaces
                |= oneOf [ quoted '"' '"', until [ ' ', '\n' ] ]
            )


tableProps : Parser AmlTableProps
tableProps =
    properties
        |> Parser.andThen
            (\p ->
                p
                    |> Dict.foldl
                        (\k v acc ->
                            case k of
                                "color" ->
                                    Color.from v
                                        |> Maybe.map (\c -> acc |> Parser.map (\a -> { a | color = Just c }))
                                        |> Maybe.withDefault (problem ("Unknown color '" ++ v ++ "'"))

                                "left" ->
                                    case ( v |> String.toFloat, p |> Dict.get "top" |> Maybe.map String.toFloat ) of
                                        ( Just left, Just (Just top) ) ->
                                            acc |> Parser.map (\a -> { a | position = Just { left = left, top = top } })

                                        ( Nothing, _ ) ->
                                            problem "Property 'left' should be a number"

                                        ( _, Just Nothing ) ->
                                            problem "Property 'top' should be a number"

                                        ( _, Nothing ) ->
                                            problem "Missing property 'top'"

                                "top" ->
                                    case ( p |> Dict.get "left" |> Maybe.map String.toFloat, v |> String.toFloat ) of
                                        ( Just (Just left), Just top ) ->
                                            acc |> Parser.map (\a -> { a | position = Just { left = left, top = top } })

                                        ( _, Nothing ) ->
                                            problem "Property 'top' should be a number"

                                        ( Just Nothing, _ ) ->
                                            problem "Property 'left' should be a number"

                                        ( Nothing, _ ) ->
                                            problem "Missing property 'left'"

                                _ ->
                                    problem ("Unknown property '" ++ k ++ "'")
                        )
                        (succeed { color = Nothing, position = Nothing })
            )


columnProps : Parser AmlColumnProps
columnProps =
    properties
        |> Parser.andThen
            (Dict.foldl
                (\k v acc ->
                    case k of
                        "hidden" ->
                            if v == "" then
                                acc |> Parser.map (\a -> { a | hidden = True })

                            else
                                problem "Property 'hidden' should have no value"

                        _ ->
                            problem ("Unknown property '" ++ k ++ "'")
                )
                (succeed { hidden = False })
            )


properties : Parser (Dict String String)
properties =
    sequence
        { start = "{"
        , separator = ","
        , end = "}"
        , spaces = spaces
        , item = property
        , trailing = Forbidden
        }
        |> Parser.map Dict.fromList


property : Parser ( String, String )
property =
    succeed (\key value -> ( key, value |> Maybe.withDefault "" ))
        |= oneOf [ quoted '"' '"', untilNonEmpty [ ' ', '=', ',', '}' ] ]
        |. spaces
        |= maybe
            (succeed identity
                |. symbol "="
                |. spaces
                |= oneOf [ quoted '"' '"', until [ ' ', ',', '}' ] ]
            )


tableRef : Parser AmlTableRef
tableRef =
    succeed
        (\schema tbl ->
            case tbl of
                Just t ->
                    { schema = Just schema, table = t }

                Nothing ->
                    { schema = Nothing, table = schema }
        )
        |= schemaName
        |= maybe
            (succeed identity
                |. symbol "."
                |= tableName
            )


columnRef : Parser AmlColumnRef
columnRef =
    succeed
        (\name1 name2 name3 ->
            name3
                |> Maybe.map (\c -> { schema = Just name1, table = name2, column = c })
                |> Maybe.withDefault { schema = Nothing, table = name1, column = name2 }
        )
        |= schemaName
        |. symbol "."
        |= tableName
        |= maybe (succeed identity |. symbol "." |= columnName)


schemaName : Parser AmlSchemaName
schemaName =
    oneOf [ quoted '"' '"', untilNonEmpty [ '.', ' ', '\n', '*' ] ]


tableName : Parser AmlTableName
tableName =
    oneOf [ quoted '"' '"', untilNonEmpty [ '.', ' ', '\n', '*' ] ]


columnName : Parser AmlColumnName
columnName =
    oneOf [ quoted '"' '"', untilNonEmpty [ '.', ' ', '\n' ] ]


columnType : Parser AmlParsedColumnType
columnType =
    succeed buildColumnType
        |= columnTypeName
        |= maybe (succeed identity |. symbol "." |= columnTypeName)
        |. spaces
        |= maybe columnTypeValues
        |. spaces
        |= maybe columnTypeDefault


buildColumnType : String -> Maybe String -> Maybe (List String) -> Maybe String -> AmlParsedColumnType
buildColumnType name1 name2 values default =
    let
        ( schema, name ) =
            name2 |> Maybe.mapOrElse (\n -> ( Just name1, n )) ( Nothing, name1 )

        vals : List String
        vals =
            values |> Maybe.withDefault []
    in
    if 0 < List.length vals && List.length vals <= 2 && List.all (\v -> String.toInt v /= Nothing) vals then
        { schema = schema, name = name ++ "(" ++ String.join ", " vals ++ ")", values = Nothing, default = default }

    else
        { schema = schema, name = name, values = values |> Maybe.andThen (List.map String.trim >> Nel.fromList), default = default }


columnTypeName : Parser String
columnTypeName =
    oneOf
        [ quoted '"' '"'
        , variable
            { start = \c -> [ '.', '(', '=', ' ', '\n', '{', '|', '#' ] |> List.member c |> not
            , inner = \c -> [ '.', '(', '=', ' ', '\n' ] |> List.member c |> not
            , reserved = Set.fromList [ "nullable", "NULLABLE", "pk", "PK", "index", "INDEX", "unique", "UNIQUE", "check", "CHECK", "fk", "FK" ]
            }
        ]


columnTypeValues : Parser (List String)
columnTypeValues =
    sequence
        { start = "("
        , separator = ","
        , end = ")"
        , spaces = spaces
        , item = oneOf [ quoted '"' '"', untilNonEmpty [ ',', ')', '\n' ] ]
        , trailing = Optional
        }


columnTypeDefault : Parser AmlColumnValue
columnTypeDefault =
    succeed identity
        |. symbol "="
        |. spaces
        |= columnValue


columnValue : Parser AmlColumnValue
columnValue =
    oneOf [ quoted '"' '"', untilNonEmpty [ ' ', '\n' ] ]


notes : Parser AmlNotes
notes =
    succeed String.trim
        |. symbol "|"
        |. spaces
        |= oneOf [ quoted '"' '"', until [ '#', '\n' ] ]


comment : Parser AmlComment
comment =
    succeed String.trim
        |. symbol "#"
        |. spaces
        |= oneOf [ quoted '"' '"', until [ '\n' ] ]



-- UTILS


symbolI : String -> Parser ()
symbolI s =
    oneOf [ symbol (s |> String.toLower), symbol (s |> String.toUpper) ]


endOfLine : Parser ()
endOfLine =
    symbol "\n"


spaces : Parser ()
spaces =
    chompWhile (\c -> c == ' ')


quoted : Char -> Char -> Parser String
quoted first last =
    succeed identity
        |. chompIf (\c -> c == first)
        |= until [ last ]
        |. chompIf (\c -> c == last)


untilNonEmpty : List Char -> Parser String
untilNonEmpty stop =
    succeed (\first others -> first ++ others)
        |= (chompIf (\c -> stop |> List.member c |> not) |> getChompedString)
        |= until stop


until : List Char -> Parser String
until stop =
    chompWhile (\c -> stop |> List.member c |> not) |> getChompedString


maybe : Parser a -> Parser (Maybe a)
maybe p =
    oneOf
        [ succeed Just |= p
        , succeed Nothing
        ]


list : Parser a -> Parser (List a)
list p =
    loop [] (listHelp p)


listHelp : Parser a -> List a -> Parser (Step (List a) (List a))
listHelp p revList =
    oneOf
        [ succeed (\col -> Loop (col :: revList)) |= p
        , succeed () |> Parser.map (\_ -> Done (List.reverse revList))
        ]
